// Q4 — can this Mach-O library be loaded by a watchOS process, and does it export the embedder API?
// Usage (inside the watch simulator):  engine_dlopen <path-to-library>
#include <dlfcn.h>
#include <stdio.h>

int main(int argc, char** argv) {
  if (argc < 2) { fprintf(stderr, "usage: engine_dlopen <library>\n"); return 64; }
  void* h = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!h) { printf("DLOPEN FAIL: %s\n", dlerror()); return 2; }
  printf("DLOPEN OK\n");
  const char* names[] = {"FlutterEngineRun", "FlutterEngineSendWindowMetricsEvent", "FlutterEngineShutdown"};
  int missing = 0;
  for (int i = 0; i < 3; i++) {
    void* s = dlsym(h, names[i]);
    printf("SYMBOL %s: %s\n", names[i], s ? "found" : "MISSING");
    if (!s) missing++;
  }
  return missing ? 3 : 0;
}
