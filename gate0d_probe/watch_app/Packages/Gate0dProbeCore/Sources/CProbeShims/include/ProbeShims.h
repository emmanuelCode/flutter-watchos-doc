#ifndef PROBE_SHIMS_H
#define PROBE_SHIMS_H

#include <stddef.h>
#include <stdint.h>

int probe_sysctl_machine(char *buf, size_t len);
/* 1 = traced (debugger attached), 0 = not traced, -1 = could not determine */
int probe_is_debugger_attached(void);
int probe_memory_snapshot(double *out_resident_mb, double *out_footprint_mb, double *out_available_mb);
/* 1 = allowed, 0 = failed (errno in out_errno), -1 = unsupported */
int probe_jit_mmap(int32_t *out_errno);
int probe_jit_mprotect(int32_t *out_errno);
/* 1 = connected, 0 = failed (errno), -1 = timeout */
int probe_bsd_tcp_connect(const char *ip, uint16_t port, int32_t timeout_ms, double *out_rtt_ms, int32_t *out_errno);
int probe_getaddrinfo_local(const char *hostname, int32_t *out_count, double *out_ms, int32_t *out_gai_err);

#endif
