// Q5 — a minimal Flutter embedder host written from scratch against embedder.h (the API the spec's Mode 2 uses).
// It runs INSIDE a watchOS process: loads the engine library, runs the probe app with the SOFTWARE renderer,
// receives the rendered frame through surface_present_callback, and writes it to a file.
//   engine_host <engine-lib> <flutter_assets> <icudtl.dat> <out-file> <width> <height> <seconds>
// Output file: three uint32 (width, height, rowBytes) then raw BGRA bytes of the latest frame.
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <pthread.h>
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

static bool present(void* user_data, const void* allocation, size_t row_bytes, size_t height) {
  pthread_mutex_lock(&g_lock);
  size_t len = row_bytes * height;
  if (len != g_len) { free(g_frame); g_frame = malloc(len); g_len = len; }
  memcpy(g_frame, allocation, len);
  g_rows = height;
  g_rowBytes = row_bytes;
  pthread_mutex_unlock(&g_lock);
  atomic_fetch_add(&g_frames, 1);
  return true;
}

static void on_log(const char* tag, const char* message, void* user_data) {
  fprintf(stderr, "[engine %s] %s\n", tag ? tag : "", message ? message : "");
}

typedef FlutterEngineResult (*RunFn)(size_t, const FlutterRendererConfig*, const FlutterProjectArgs*, void*, FlutterEngine*);
typedef FlutterEngineResult (*MetricsFn)(FlutterEngine, const FlutterWindowMetricsEvent*);

int main(int argc, char** argv) {
  if (argc < 8) { fprintf(stderr, "usage: engine_host lib assets icu out width height seconds\n"); return 64; }
  const char *lib = argv[1], *assets = argv[2], *icu = argv[3], *out = argv[4];
  int width = atoi(argv[5]), height = atoi(argv[6]), seconds = atoi(argv[7]);

  void* h = dlopen(lib, RTLD_NOW | RTLD_LOCAL);
  if (!h) { fprintf(stderr, "DLOPEN FAIL: %s\n", dlerror()); return 2; }
  RunFn run = (RunFn)dlsym(h, "FlutterEngineRun");
  MetricsFn metrics = (MetricsFn)dlsym(h, "FlutterEngineSendWindowMetricsEvent");
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

  // The platform thread is this thread: keep its run loop turning so the engine's platform tasks execute.
  CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + seconds;
  CFAbsoluteTime settle = 0;
  while (CFAbsoluteTimeGetCurrent() < deadline) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    if (atomic_load(&g_frames) > 0 && settle == 0) settle = CFAbsoluteTimeGetCurrent() + 2.0;  // let later frames land
    if (settle != 0 && CFAbsoluteTimeGetCurrent() > settle) break;
  }
  fprintf(stderr, "frames presented: %lu\n", (unsigned long)atomic_load(&g_frames));

  pthread_mutex_lock(&g_lock);
  if (!g_frame) { pthread_mutex_unlock(&g_lock); fprintf(stderr, "NO FRAME within %d s\n", seconds); return 5; }
  FILE* f = fopen(out, "wb");
  uint32_t hdr[3] = {(uint32_t)(g_rowBytes / 4), (uint32_t)g_rows, (uint32_t)g_rowBytes};
  fwrite(hdr, sizeof hdr, 1, f);
  fwrite(g_frame, 1, g_len, f);
  fclose(f);
  pthread_mutex_unlock(&g_lock);
  fprintf(stderr, "wrote %s (%ux%u)\n", out, hdr[0], hdr[1]);
  _exit(0);  // do not wait for engine teardown
}
