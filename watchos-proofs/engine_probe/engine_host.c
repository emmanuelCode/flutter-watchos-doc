// Q5 / Q6 / Q7 — minimal Flutter embedder host written from scratch against embedder.h.
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "embedder.h"

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

static uint8_t* g_frame = NULL;
static size_t g_len = 0, g_rows = 0, g_rowBytes = 0;
static atomic_ulong g_frames = 0;

static uint8_t* g_frame_post_tap = NULL;
static size_t g_len_post_tap = 0, g_rows_post_tap = 0, g_rowBytes_post_tap = 0;
static atomic_ulong g_frames_post_tap = 0;
static atomic_bool g_tap_injected = false;

static uint8_t* g_frame_post_crown = NULL;
static size_t g_len_post_crown = 0, g_rows_post_crown = 0, g_rowBytes_post_crown = 0;
static atomic_ulong g_frames_post_crown = 0;
static atomic_bool g_crown_injected = false;

static bool present(void* user_data, const void* allocation, size_t row_bytes, size_t height) {
  pthread_mutex_lock(&g_lock);
  size_t len = row_bytes * height;
  if (!atomic_load(&g_tap_injected)) {
    if (len != g_len) { free(g_frame); g_frame = malloc(len); g_len = len; }
    memcpy(g_frame, allocation, len);
    g_rows = height;
    g_rowBytes = row_bytes;
    atomic_fetch_add(&g_frames, 1);
  } else if (!atomic_load(&g_crown_injected)) {
    if (len != g_len_post_tap) { free(g_frame_post_tap); g_frame_post_tap = malloc(len); g_len_post_tap = len; }
    memcpy(g_frame_post_tap, allocation, len);
    g_rows_post_tap = height;
    g_rowBytes_post_tap = row_bytes;
    atomic_fetch_add(&g_frames_post_tap, 1);
  } else {
    if (len != g_len_post_crown) { free(g_frame_post_crown); g_frame_post_crown = malloc(len); g_len_post_crown = len; }
    memcpy(g_frame_post_crown, allocation, len);
    g_rows_post_crown = height;
    g_rowBytes_post_crown = row_bytes;
    atomic_fetch_add(&g_frames_post_crown, 1);
  }
  pthread_mutex_unlock(&g_lock);
  return true;
}

static void on_log(const char* tag, const char* message, void* user_data) {
  fprintf(stderr, "[engine %s] %s\n", tag ? tag : "", message ? message : "");
}

static void print_memory(const char* label) {
  struct mach_task_basic_info info;
  mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
  if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count) == KERN_SUCCESS) {
    fprintf(stderr, "host: memory %s: resident=%.2f MB (%lu KB), virtual=%.2f MB\n",
            label,
            (double)info.resident_size / (1024.0 * 1024.0),
            (unsigned long)(info.resident_size / 1024),
            (double)info.virtual_size / (1024.0 * 1024.0));
  }
}

typedef int (*BacktraceFn)(void**, int);
typedef void (*BacktraceFdFn)(void* const*, int, int);
typedef int (*SigAltStackFn)(const stack_t*, stack_t*);

static void on_crash(int sig, siginfo_t* si, void* uc) {
  char buf[160];
  int n = snprintf(buf, sizeof buf, "\nCRASH signal=%d code=%d fault_addr=%p\n", sig, si->si_code, si->si_addr);
  write(2, buf, n);
  BacktraceFn bt = (BacktraceFn)dlsym(RTLD_DEFAULT, "backtrace");
  BacktraceFdFn btfd = (BacktraceFdFn)dlsym(RTLD_DEFAULT, "backtrace_symbols_fd");
  if (bt && btfd) {
    void* frames[64];
    int c = bt(frames, 64);
    btfd(frames, c, 2);
  } else {
    const char m[] = "(backtrace not available in this runtime)\n";
    write(2, m, sizeof m - 1);
  }
  _exit(128 + sig);
}

static void install_crash_handler(void) {
  static char altstack[1 << 16];
  int flags = SA_SIGINFO;
  SigAltStackFn sas = (SigAltStackFn)dlsym(RTLD_DEFAULT, "sigaltstack");
  if (sas) {
    stack_t ss;
    memset(&ss, 0, sizeof ss);
    ss.ss_sp = altstack;
    ss.ss_size = sizeof altstack;
    if (sas(&ss, NULL) == 0) flags |= SA_ONSTACK;
  }
  struct sigaction sa;
  memset(&sa, 0, sizeof sa);
  sa.sa_sigaction = on_crash;
  sa.sa_flags = flags;
  sigemptyset(&sa.sa_mask);
  int sigs[] = {SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT};
  for (size_t i = 0; i < sizeof sigs / sizeof sigs[0]; i++) sigaction(sigs[i], &sa, NULL);
}

typedef FlutterEngineResult (*RunFn)(size_t, const FlutterRendererConfig*, const FlutterProjectArgs*, void*, FlutterEngine*);
typedef FlutterEngineResult (*MetricsFn)(FlutterEngine, const FlutterWindowMetricsEvent*);
typedef FlutterEngineResult (*PointerFn)(FlutterEngine, const FlutterPointerEvent*, size_t);
typedef FlutterEngineResult (*LowMemFn)(FlutterEngine);

int main(int argc, char** argv) {
  if (argc < 8) { fprintf(stderr, "usage: engine_host lib assets icu out width height seconds [out2] [out3]\n"); return 64; }
  install_crash_handler();
  const char *lib = argv[1], *assets = argv[2], *icu = argv[3], *out = argv[4];
  int width = atoi(argv[5]), height = atoi(argv[6]), seconds = atoi(argv[7]);
  const char *out2 = (argc >= 9) ? argv[8] : NULL;
  const char *out3 = (argc >= 10) ? argv[9] : NULL;

  void* h = dlopen(lib, RTLD_NOW | RTLD_GLOBAL);
  if (!h) { fprintf(stderr, "DLOPEN FAIL: %s\n", dlerror()); return 2; }
  RunFn run = (RunFn)dlsym(h, "FlutterEngineRun");
  MetricsFn metrics = (MetricsFn)dlsym(h, "FlutterEngineSendWindowMetricsEvent");
  PointerFn send_pointer = (PointerFn)dlsym(h, "FlutterEngineSendPointerEvent");
  LowMemFn notify_low_mem = (LowMemFn)dlsym(h, "FlutterEngineNotifyLowMemory");

  if (!run || !metrics) { fprintf(stderr, "embedder API symbols missing\n"); return 3; }

  FlutterRendererConfig cfg;
  memset(&cfg, 0, sizeof cfg);
  cfg.type = kSoftware;
  cfg.software.struct_size = sizeof(FlutterSoftwareRendererConfig);
  cfg.software.surface_present_callback = present;

  FlutterProjectArgs args;
  memset(&args, 0, sizeof args);
  args.struct_size = sizeof(FlutterProjectArgs);
  args.assets_path = assets;
  args.icu_data_path = icu;
  args.log_message_callback = on_log;

  FlutterEngine engine = NULL;
  FlutterEngineResult r = run(FLUTTER_ENGINE_VERSION, &cfg, &args, NULL, &engine);
  fprintf(stderr, "FlutterEngineRun -> %d\n", (int)r);
  if (r != kSuccess) return 4;

  FlutterWindowMetricsEvent ev;
  memset(&ev, 0, sizeof ev);
  ev.struct_size = sizeof(FlutterWindowMetricsEvent);
  ev.width = (size_t)width;
  ev.height = (size_t)height;
  ev.pixel_ratio = 1.0;
  r = metrics(engine, &ev);
  fprintf(stderr, "FlutterEngineSendWindowMetricsEvent -> %d\n", (int)r);

  if (!out2) {
    // Single-frame mode (Q5)
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + seconds;
    CFAbsoluteTime settle = 0;
    while (CFAbsoluteTimeGetCurrent() < deadline) {
      CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
      if (atomic_load(&g_frames) > 0 && settle == 0) settle = CFAbsoluteTimeGetCurrent() + 2.0;
      if (settle != 0 && CFAbsoluteTimeGetCurrent() > settle) break;
    }
    fprintf(stderr, "frames presented: %lu\n", (unsigned long)atomic_load(&g_frames));
    print_memory("after frame 1");

    pthread_mutex_lock(&g_lock);
    if (!g_frame) { pthread_mutex_unlock(&g_lock); fprintf(stderr, "NO FRAME within %d s\n", seconds); return 5; }
    FILE* f = fopen(out, "wb");
    uint32_t hdr[3] = {(uint32_t)(g_rowBytes / 4), (uint32_t)g_rows, (uint32_t)g_rowBytes};
    fwrite(hdr, sizeof hdr, 1, f);
    fwrite(g_frame, 1, g_len, f);
    fclose(f);
    pthread_mutex_unlock(&g_lock);
    fprintf(stderr, "wrote %s (%ux%u)\n", out, hdr[0], hdr[1]);
    _exit(0);
  }

  // Phase 1: Wait for initial frame
  CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + seconds;
  CFAbsoluteTime settle = 0;
  while (CFAbsoluteTimeGetCurrent() < deadline) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    if (atomic_load(&g_frames) > 0 && settle == 0) settle = CFAbsoluteTimeGetCurrent() + 1.0;
    if (settle != 0 && CFAbsoluteTimeGetCurrent() > settle) break;
  }

  pthread_mutex_lock(&g_lock);
  if (!g_frame) { pthread_mutex_unlock(&g_lock); fprintf(stderr, "NO INITIAL FRAME\n"); return 5; }
  FILE* f1 = fopen(out, "wb");
  uint32_t hdr1[3] = {(uint32_t)(g_rowBytes / 4), (uint32_t)g_rows, (uint32_t)g_rowBytes};
  fwrite(hdr1, sizeof hdr1, 1, f1);
  fwrite(g_frame, 1, g_len, f1);
  fclose(f1);
  pthread_mutex_unlock(&g_lock);
  fprintf(stderr, "wrote initial frame to %s (%ux%u)\n", out, hdr1[0], hdr1[1]);
  print_memory("after frame 1");

  if (!send_pointer) { fprintf(stderr, "FlutterEngineSendPointerEvent missing\n"); return 6; }

  // Phase 2: Inject Tap
  atomic_store(&g_tap_injected, true);
  double tap_x = width / 2.0;
  double tap_y = height / 2.0;
  size_t now_us = (size_t)(CFAbsoluteTimeGetCurrent() * 1e6);

  FlutterPointerEvent pev;
  memset(&pev, 0, sizeof pev);
  pev.struct_size = sizeof(FlutterPointerEvent);
  pev.phase = kAdd;
  pev.timestamp = now_us;
  pev.x = tap_x;
  pev.y = tap_y;
  send_pointer(engine, &pev, 1);
  CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);

  now_us = (size_t)(CFAbsoluteTimeGetCurrent() * 1e6);
  memset(&pev, 0, sizeof pev);
  pev.struct_size = sizeof(FlutterPointerEvent);
  pev.phase = kDown;
  pev.timestamp = now_us;
  pev.x = tap_x;
  pev.y = tap_y;
  send_pointer(engine, &pev, 1);
  CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);

  now_us = (size_t)(CFAbsoluteTimeGetCurrent() * 1e6);
  memset(&pev, 0, sizeof pev);
  pev.struct_size = sizeof(FlutterPointerEvent);
  pev.phase = kUp;
  pev.timestamp = now_us;
  pev.x = tap_x;
  pev.y = tap_y;
  send_pointer(engine, &pev, 1);
  fprintf(stderr, "injected tap at (%.1f, %.1f)\n", tap_x, tap_y);

  // Phase 3: Wait for post-tap frame 2
  deadline = CFAbsoluteTimeGetCurrent() + 20.0;
  settle = 0;
  while (CFAbsoluteTimeGetCurrent() < deadline) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    if (atomic_load(&g_frames_post_tap) > 0 && settle == 0) settle = CFAbsoluteTimeGetCurrent() + 1.5;
    if (settle != 0 && CFAbsoluteTimeGetCurrent() > settle) break;
  }

  pthread_mutex_lock(&g_lock);
  if (!g_frame_post_tap) { pthread_mutex_unlock(&g_lock); fprintf(stderr, "NO POST-TAP FRAME\n"); return 7; }
  FILE* f2 = fopen(out2, "wb");
  uint32_t hdr2[3] = {(uint32_t)(g_rowBytes_post_tap / 4), (uint32_t)g_rows_post_tap, (uint32_t)g_rowBytes_post_tap};
  fwrite(hdr2, sizeof hdr2, 1, f2);
  fwrite(g_frame_post_tap, 1, g_len_post_tap, f2);
  fclose(f2);
  pthread_mutex_unlock(&g_lock);
  fprintf(stderr, "wrote post-tap frame to %s (%ux%u)\n", out2, hdr2[0], hdr2[1]);
  print_memory("after frame 2");

  if (!out3) {
    _exit(0);
  }

  // Phase 4: Inject Digital Crown Scroll Event (signal_kind = kFlutterPointerSignalKindScroll)
  atomic_store(&g_crown_injected, true);
  now_us = (size_t)(CFAbsoluteTimeGetCurrent() * 1e6);
  memset(&pev, 0, sizeof pev);
  pev.struct_size = sizeof(FlutterPointerEvent);
  pev.phase = kHover;
  pev.signal_kind = kFlutterPointerSignalKindScroll;
  pev.timestamp = now_us;
  pev.x = tap_x;
  pev.y = tap_y;
  pev.scroll_delta_x = 0.0;
  pev.scroll_delta_y = 40.0;
  send_pointer(engine, &pev, 1);
  fprintf(stderr, "injected Crown scroll signal (delta_y=40.0) at (%.1f, %.1f)\n", tap_x, tap_y);

  // Phase 5: Wait for post-crown frame 3
  deadline = CFAbsoluteTimeGetCurrent() + 20.0;
  settle = 0;
  while (CFAbsoluteTimeGetCurrent() < deadline) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    if (atomic_load(&g_frames_post_crown) > 0 && settle == 0) settle = CFAbsoluteTimeGetCurrent() + 1.5;
    if (settle != 0 && CFAbsoluteTimeGetCurrent() > settle) break;
  }

  pthread_mutex_lock(&g_lock);
  if (!g_frame_post_crown) { pthread_mutex_unlock(&g_lock); fprintf(stderr, "NO POST-CROWN FRAME\n"); return 8; }
  FILE* f3 = fopen(out3, "wb");
  uint32_t hdr3[3] = {(uint32_t)(g_rowBytes_post_crown / 4), (uint32_t)g_rows_post_crown, (uint32_t)g_rowBytes_post_crown};
  fwrite(hdr3, sizeof hdr3, 1, f3);
  fwrite(g_frame_post_crown, 1, g_len_post_crown, f3);
  fclose(f3);
  pthread_mutex_unlock(&g_lock);
  fprintf(stderr, "wrote post-crown frame to %s (%ux%u)\n", out3, hdr3[0], hdr3[1]);
  print_memory("after frame 3");

  // Phase 6: Notify Low Memory hook test
  if (notify_low_mem) {
    FlutterEngineResult lmr = notify_low_mem(engine);
    fprintf(stderr, "FlutterEngineNotifyLowMemory -> %d\n", (int)lmr);
    for (int i = 0; i < 6; i++) {
      CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    }
    print_memory("after notify low memory");
  }

  fprintf(stderr, "frames presented total: %lu (f1: %lu, f2: %lu, f3: %lu)\n",
          (unsigned long)(atomic_load(&g_frames) + atomic_load(&g_frames_post_tap) + atomic_load(&g_frames_post_crown)),
          (unsigned long)atomic_load(&g_frames),
          (unsigned long)atomic_load(&g_frames_post_tap),
          (unsigned long)atomic_load(&g_frames_post_crown));

  _exit(0);
}
