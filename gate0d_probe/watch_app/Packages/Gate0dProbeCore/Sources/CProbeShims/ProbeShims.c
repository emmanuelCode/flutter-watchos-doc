#include "ProbeShims.h"

#include <errno.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <netdb.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#if defined(__has_include)
#if __has_include(<os/proc.h>)
#include <os/proc.h>
#define HAS_OS_PROC_H 1
#endif
#endif

static uint64_t now_ns(void) {
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

int probe_sysctl_machine(char *buf, size_t len) {
    if (!buf || len == 0) return -1;
    size_t sz = len - 1;
    if (sysctlbyname("hw.machine", buf, &sz, NULL, 0) != 0) {
        buf[0] = '\0';
        return -1;
    }
    buf[sz] = '\0';
    return 0;
}

int probe_is_debugger_attached(void) {
#if defined(CTL_KERN) && defined(KERN_PROC) && defined(KERN_PROC_PID) && defined(P_TRACED)
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc info;
    memset(&info, 0, sizeof(info));
    size_t size = sizeof(info);
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) {
        return -1;
    }
    return (info.kp_proc.p_flag & P_TRACED) ? 1 : 0;
#else
    return -1;
#endif
}

int probe_memory_snapshot(double *out_resident_mb, double *out_footprint_mb, double *out_available_mb) {
    if (!out_resident_mb || !out_footprint_mb || !out_available_mb) return -1;
    *out_resident_mb = 0.0;
    *out_footprint_mb = 0.0;
    *out_available_mb = -1.0;

    struct mach_task_basic_info basic;
    mach_msg_type_number_t basic_count = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&basic, &basic_count) == KERN_SUCCESS) {
        *out_resident_mb = (double)basic.resident_size / (1024.0 * 1024.0);
    }

    task_vm_info_data_t vm;
    mach_msg_type_number_t vm_count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vm, &vm_count) == KERN_SUCCESS) {
        *out_footprint_mb = (double)vm.phys_footprint / (1024.0 * 1024.0);
    }

#if defined(HAS_OS_PROC_H)
    size_t avail = os_proc_available_memory();
    if (avail > 0) {
        *out_available_mb = (double)avail / (1024.0 * 1024.0);
    }
#endif
    return 0;
}

int probe_jit_mmap(int32_t *out_errno) {
#ifdef MAP_JIT
    size_t sz = (size_t)getpagesize();
    errno = 0;
    void *p = mmap(NULL, sz, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (p == MAP_FAILED) {
        if (out_errno) *out_errno = errno;
        return 0;
    }
    munmap(p, sz);
    if (out_errno) *out_errno = 0;
    return 1;
#else
    if (out_errno) *out_errno = ENOTSUP;
    return -1;
#endif
}

int probe_jit_mprotect(int32_t *out_errno) {
    size_t sz = (size_t)getpagesize();
    errno = 0;
    void *p = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (p == MAP_FAILED) {
        if (out_errno) *out_errno = errno;
        return 0;
    }
    errno = 0;
    int rc = mprotect(p, sz, PROT_READ | PROT_EXEC);
    int saved = errno;
    munmap(p, sz);
    if (rc != 0) {
        if (out_errno) *out_errno = saved;
        return 0;
    }
    if (out_errno) *out_errno = 0;
    return 1;
}

int probe_bsd_tcp_connect(const char *ip, uint16_t port, int32_t timeout_ms, double *out_rtt_ms, int32_t *out_errno) {
    if (!ip || !out_rtt_ms || !out_errno) return 0;
    *out_rtt_ms = 0.0;
    *out_errno = 0;

    char port_buf[16];
    snprintf(port_buf, sizeof(port_buf), "%u", (unsigned int)port);

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_NUMERICHOST;

    struct addrinfo *res = NULL;
    int gai = getaddrinfo(ip, port_buf, &hints, &res);
    if (gai != 0 || !res) {
        *out_errno = EINVAL;
        return 0;
    }

    int fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0) {
        *out_errno = errno;
        freeaddrinfo(res);
        return 0;
    }

    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0) {
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }

    uint64_t t0 = now_ns();
    int rc = connect(fd, res->ai_addr, res->ai_addrlen);
    int connect_errno = errno;
    freeaddrinfo(res);

    if (rc == 0) {
        *out_rtt_ms = (double)(now_ns() - t0) / 1e6;
        close(fd);
        return 1;
    }
    if (connect_errno != EINPROGRESS) {
        *out_errno = connect_errno;
        close(fd);
        return 0;
    }

    struct pollfd pfd;
    memset(&pfd, 0, sizeof(pfd));
    pfd.fd = fd;
    pfd.events = POLLOUT;

    int prc = poll(&pfd, 1, timeout_ms);
    if (prc == 0) {
        *out_errno = ETIMEDOUT;
        close(fd);
        return -1;
    }
    if (prc < 0) {
        *out_errno = errno;
        close(fd);
        return 0;
    }

    int so_err = 0;
    socklen_t slen = sizeof(so_err);
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &so_err, &slen) != 0) {
        *out_errno = errno;
        close(fd);
        return 0;
    }
    if (so_err != 0) {
        *out_errno = so_err;
        close(fd);
        return 0;
    }

    *out_rtt_ms = (double)(now_ns() - t0) / 1e6;
    close(fd);
    return 1;
}

int probe_getaddrinfo_local(const char *hostname, int32_t *out_count, double *out_ms, int32_t *out_gai_err) {
    if (!hostname || !out_count || !out_ms || !out_gai_err) return 0;
    *out_count = 0;
    *out_ms = 0.0;
    *out_gai_err = 0;

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    struct addrinfo *res = NULL;
    uint64_t t0 = now_ns();
    int rc = getaddrinfo(hostname, NULL, &hints, &res);
    *out_ms = (double)(now_ns() - t0) / 1e6;

    if (rc != 0 || !res) {
        *out_gai_err = rc;
        if (res) freeaddrinfo(res);
        return 0;
    }

    int count = 0;
    for (struct addrinfo *it = res; it != NULL; it = it->ai_next) {
        count++;
    }
    freeaddrinfo(res);
    *out_count = count;
    return count > 0 ? 1 : 0;
}
