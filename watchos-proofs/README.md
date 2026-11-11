# watchOS proofs — one tiny test per untested idea

The GitHub Actions workflow (`.github/workflows/proofs.yml`, at the **repo root**) runs on a **macOS runner** with the
**watchOS Simulator**. Each *step name* is one concept — read the step list as the checklist.
When everything finishes, the last job (**"RESULTS — open this job and copy the block"**) prints one
result sheet. That block is also saved in the run's **Summary** page. Paste it back to get fixes.

> The runner provides a Mac and a *simulated* Apple Watch — not a physical watch. These tests prove
> that the code compiles, the logic works, and the pieces connect. They do **not** prove memory
> limits, speed, battery or real-hardware pixel parity (see "Not covered").

## How to read the result sheet

```
✅ pass   ❌ fail (evidence lines printed below)   ⛔ blocked by P1/P0   ⬜ no result recorded
```
Fix order: **F0 → P1 → P0 → everything else.** A failure in P1 or P0 blocks the Swift tests, so those
show ⛔ instead of failing for confusing reasons. Full logs are attached to the run as `logs-*`
artifacts, but only when something fails.

## Test catalog — what each check tests, why, and what a pass means

**34 checks in four jobs**, all run on a macOS GitHub runner with the watchOS Simulator. IDs are not contiguous (there is no P7 or P8 — they were planned and dropped).

**Honest labeling.** "Tested" always means *tested in the watchOS Simulator on a macOS runner*, never on a physical watch. The Simulator runs as an ordinary process on the Mac, so it uses the Mac's CPU and memory.

**Type:** **Setup** = prepares or checks the environment. **Proof** = a pass/fail claim. **Measure** = numbers are logged; a pass only means the numbers were produced. **Finding** = the output is information, not a verdict. **Experiment** = deliberately pushes something unsupported to see how far it gets.

### Job `flutter-side` (runs Flutter on a Mac)

| ID | Type | What it tests | Purpose | A pass means — and its limits |
|---|---|---|---|---|
| F0 | Setup | `flutter pub get` for the Flutter proof package | Everything Dart-side depends on it | The toolchain and packages resolve |
| P2 | Proof + Measure | `RepaintBoundary.toImage` captures a frame with no window, as raw RGBA | The dev loop needs frames from an app with no visible window | Capture works headless; byte counts are exact (191,664 B at pixel ratio 1.0, 766,656 B at 2.0). *Limit:* the test renderer, so timings are not real GPU readback cost |
| P3 | Proof | A tap injected through `GestureBinding` fires a `GestureDetector`, runs `setState`, and changes the next frame | The watch sends taps; the Mac must be able to replay them into the app | Pointer injection with public APIs works |
| X1 | Setup | Extracts the spec's Dart code blocks into files | Tests run the spec's *actual* code, not a copy | The spec still contains the blocks in the expected shape; fails loudly if the spec changes shape |
| S1 | Proof | The spec's real `WatchFrameStreamer` and `WatchInputInjector`: capture, tap, next frame | Checks the spec's own code, not a stand-in | Works. Also revealed that an idle app produces no frames (led to `captureNow()`) |
| S7 | Proof | `captureNow()` pushes the current frame from an idle app (and an idle app sends nothing by itself) | A watch that connects late must still get an image | Exactly one frame is pushed on demand |

### Job `swift-watchos` (watchOS Simulator)

| ID | Type | What it tests | Purpose | A pass means — and its limits |
|---|---|---|---|---|
| P1 | Setup | A watchOS Simulator exists on the runner and boots | Every Swift check needs one | Hosted runners ship a usable watchOS runtime (answers Open Question 10) |
| P0 | Setup + Proof | The Swift proof package compiles for watchOS and runs XCTest there with no host app | Confirms the test approach itself works | Swift builds for watchOS and tests execute in the Simulator |
| P4 | Proof | Raw RGBA bytes become a `CGImage` with the right pixels | This is how frames from Flutter reach the screen | The conversion is correct |
| P5 | Proof | A SwiftUI `Canvas` draws that image (pixels checked via `ImageRenderer`) | Confirms the display path | Canvas draws the right pixels. *Limit:* an off-screen renderer, not the on-screen watch display |
| P6 | Proof | A Dart WebSocket server and a watchOS client: a frame comes down, a tap goes up, over loopback | Proves the Mac-to-watch transport can work, and that the Simulator can reach the host | A 191,664 B frame and a tap round-trip. *Limit:* loopback only — not real Wi-Fi |
| P9 | Measure | 100 frames at pixel ratio 1.0 and 2.0, each raw, zlib and XOR-delta; every frame decoded and checked | Chooses the transport encoding and bounds bandwidth | Numbers logged. On mostly-static test frames zlib is about 1 KB (1.0) and 3.9 KB (2.0) per frame; XOR-delta saves only about 11–12% more and decodes about 20–40× slower. *Limit:* best case — static content, loopback, debug build, Mac CPU |
| A1 | Proof (Appendix A) | Canvas text anchored `.topLeading` stays in the corner; the default `.center` loses it | Display-list research path only | Confirms the anchor fix (47 lit pixels vs 10) |
| A2 | Proof (Appendix A) | Triple-buffer mailbox: the writer never blocks, the newest frame wins | Display-list research path only | The mailbox logic is correct |
| A3 | Proof (Appendix A) | Bytes written by Dart parse correctly in Swift (UTF-8, padding, misaligned base, truncation) | Display-list research path only | Wire format agrees across languages. *Limit:* a stand-in writer, not the real `ZeroCopyCanvas` |
| A4 | Proof (Appendix A) | A `@_cdecl` Swift function is found by `dlsym` (what Dart's `DynamicLibrary.process()` uses) | Display-list research path only | Symbol lookup works. *Limit:* not a Dart runtime on watchOS, and it does not prove the symbol survives dead-stripping in a release build |
| X2 | Setup | Extracts the spec's Swift code blocks into a separate package | Same as X1, isolated so a spec error cannot break the P-tests | The blocks are present and extractable |
| S0 | Proof | The spec's Swift code compiles for watchOS | The spec's code is real, not pseudocode | It builds |
| S2 | Proof | `Color(argb:)` renders the right channels, including alpha | The spec's colour helper | Channel order and alpha are correct |
| S3 | Proof | `WatchFrameStore` + `WatchFrameView` draw a frame stretched to fill the view | The primary renderer | Draws correctly at any captured size (2 px, 4 px, 16 px tested). Stretch-to-fill needs a matching aspect ratio |
| S4 | Proof (experimental) | `WatchFrameView` redraws when a new frame is published | A live view must update | The renderer reports invalidation. *Limit:* off-screen renderer |
| S5 | Proof (Appendix A) | `WatchRenderStore`, the `@_cdecl` slab API and `WatchCanvasView` draw bytes written the way Dart writes them | Display-list research path | The C API and Canvas agree with Dart-style bytes |
| S6 | Proof (experimental, Appendix A) | `WatchCanvasView` redraws on `frameTick` with no `TimelineView` | The fix for an earlier finding | Redraw occurs after submit. *Limit:* off-screen renderer |

### Job `e2e` (Flutter and the Simulator on one machine)

| ID | Type | What it tests | Purpose | A pass means — and its limits |
|---|---|---|---|---|
| E0 | Setup | Simulator boots, spec code extracted, Flutter deps resolve | Prepares E1 | Environment ready |
| E1 | Proof | **The whole dev loop with no stand-ins:** the real streamer and injector (inside `flutter test`, acting as the Mac) behind a real WebSocket, talking to a watchOS test using the real `WatchFrameStore` + `WatchFrameView`. Frame 0 shows red; a tap at (99, 121) is mapped into app coordinates and replayed; frame 1 shows green | Shows the pieces connect end to end | Frame down, tap up, next frame changes. *Limits:* the Mac side ran in `flutter test` (no real macOS window), only two frames, uncompressed, pixel ratio 1.0, no hot reload |

### Job `engine` (Open Question 9: the Flutter engine on watchOS)

Built only from official Flutter artifacts, Apple's SDK and `embedder.h` — no third-party toolchain. Building the engine from source is beyond a hosted runner, so these checks ask what *can* be answered.

| ID | Type | What it tests | Purpose | A pass means — and its limits |
|---|---|---|---|---|
| Q0 | Measure | What a hosted runner offers | Whether an engine build could fit | 3 cores, 7 GB RAM, about 92 GB free disk, 6 h job cap — a from-source engine build is not attempted here |
| Q1 | Finding + Proof | Facts from the real engine source at this SDK's pinned commit, and whether the engine's base layer (`fml`) compiles for watchOS with C++20 | Shows how much of the engine already fits watchOS | The build tool has no watchOS target; `embedder.h` has 47 functions with a software renderer; Apple's header gives `TARGET_OS_IPHONE 1` on watchOS, so `fml` treats it as iOS; 48 of 54 sampled `fml` files compile and none fail for an unavailable API (6 undecided for want of `third_party` headers) |
| Q2 | Setup | Gathers official pieces: the desktop embedder library (only `darwin-x64` is published; it is universal x86_64 + arm64), `icudtl.dat`, the iOS engine, and a probe app bundle | Inputs for Q3–Q5 | The artifacts exist and download |
| Q2s | Setup | A watch simulator boots in this job | Q4 and Q5 run in it | Ready |
| Q3 | Finding | Gap analysis: which libraries and symbols the official engines import that the watchOS SDK does not provide | Maps what a port must replace | Direct lookups are reliable: the watchOS SDK exports `CAMetalLayer`, `CGBitmapContextCreate` and `CTFontCreateWithName` but not `MTLCreateSystemDefaultDevice` or `IOSurfaceCreate`; 7 libraries are absent. **The per-library "missing symbol" totals are not reliable** — the script flags basic `libSystem` symbols such as `_bzero` as missing, so no total is quoted |
| Q4 | Experiment | Retag the official desktop embedder library as a watchOS Simulator binary and see whether a watchOS process can load it | Finds exactly what stops the real engine code | It loads, after rewriting 8 framework paths, stubbing 7 absent libraries and overlaying 4 CoreVideo symbols; `FlutterEngineRun` and two other API symbols resolve. A retagged macOS binary is not a shippable port |
| Q5 | Experiment | Run Flutter inside a watchOS process through `embedder.h` with the software renderer, using a host written from scratch; check the rendered pixels | Shows how far the real engine gets | Dart executed (a stripe is green only if `fib(20) == 6765`), text shaped and drew (1,516 glyph pixels) and a frame came through the present callback. The pixel byte order of the callback is RGBA in this engine build, inferred from the pass. *Limits:* a patched debug (JIT) engine in a Mac-hosted Simulator process; it proves nothing about a source build, AOT, a real watch, memory, speed or App Store review |
| Q6 | Experiment | Interactive loop inside watchOS process: tap injected via `FlutterEngineSendPointerEvent`, Dart `setState` executed, Frame 2 rendered and verified; memory footprint logged | Shows the engine runs an interactive event loop on watchOS | Dart received touch input, executed `setState`, reshaped text to 'TAP', repainted yellow/cyan stripes, and presented Frame 2. Resident and virtual memory measured via Mach task info. *Limits:* JIT debug engine in Simulator. |

### What the results mean together

- **The development loop works in the Simulator:** a Flutter app on the Mac can send frames to a watchOS client, and taps come back (25 dev-loop checks, including E1).
- **The official engine code can start and draw a frame under the watchOS Simulator SDK after patches that cannot ship** (Q0–Q5). That shows the engine is not fundamentally hostile to the SDK. It is not a port.
- **Still unproven:** an engine built from source for watchOS, the Dart VM on watchOS, AOT code, anything on a real watch, memory and speed there, real Wi-Fi, and App Store acceptance.

- **Interactive Flutter engine loop on watchOS (Q0–Q6):** the official engine starts, executes Dart, shapes text, renders frames, and processes live touch input (`FlutterEngineSendPointerEvent` -> `setState` -> Frame 2) with real Mach resident memory measured (~146 MB in debug mode, 390 KB frame delta).

**Latest result:** 34 of 34 checks passed (commit `8772c78`, macOS 26.7, Xcode 26.6, watchOS 26.5 Simulator, Flutter 3.47, Dart 3.13).

## Primary architecture (Path A — engine rasterizes)

| ID | What it proves | File |
|---|---|---|
| F0 | Flutter dependencies resolve | `flutter_proofs/pubspec.yaml` |
| P1 | A watchOS Simulator exists on the runner and boots | `scripts/pick_watch_sim.sh` |
| P0 | The Swift code compiles for watchOS | `scripts/build_swift.sh` |
| P2 | Flutter captures a frame with no window; raw RGBA byte counts match the bandwidth table; capture time is printed | `flutter_proofs/test/p2_headless_frame_capture_test.dart` |
| P3 | A tap injected through `GestureBinding` triggers `setState` and changes the next frame | `flutter_proofs/test/p3_tap_injection_test.dart` |
| P4 | Raw RGBA bytes become a `CGImage` with correct pixels | `swift_proofs/Tests/.../P4_RgbaToCGImageTests.swift` |
| P5 | SwiftUI `Canvas` draws that image (pixels checked via `ImageRenderer`) | `.../P5_CanvasDrawsPixelsTests.swift` |
| P6 | Dart WebSocket server → watchOS client: frame down, tap up, over loopback | `dart_tools/ws_server.dart` + `.../P6_WebSocketLoopbackTests.swift` |

## Display-list research path (Appendix A)

| ID | What it proves | File |
|---|---|---|
| A1 | `.topLeading` keeps Canvas text in the corner; the default `.center` clips it | `.../A1_TextAnchorTests.swift` |
| A2 | Triple-buffer mailbox: writer never blocks, newest frame wins | `Sources/.../Mailbox.swift` + `.../A2_MailboxTests.swift` |
| A3 | Bytes written by Dart are parsed correctly by Swift (UTF-8, padding, misaligned base, truncation) | `dart_tools/gen_wire_fixture.dart` + `.../A3_WireFormatTests.swift` |
| A4 | A `@_cdecl` Swift function is found by `dlsym` — what `DynamicLibrary.process()` does | `.../A4_CdeclSymbolTests.swift` |

## How the reporting works

`scripts/step.sh` wraps every proof step: it runs the command, keeps the exit code (so the step still
goes red), and appends `PASS` / `FAIL` plus a few evidence lines to a results file. Each job uploads
that file; the final job runs `scripts/report.py` to merge them into one block.

## Round 2 — testing the spec's REAL code, and sustained transport

`scripts/extract_spec_code.py` copies the spec's own code blocks (`Color(argb:)`, `WatchFrameStore`,
`WatchFrameView`, `WatchRenderStore`, `WatchCanvasView`, `WatchFrameStreamer`, `WatchInputInjector`)
into generated files at CI time, so these tests check exactly what the spec says. The Swift code goes
into its **own package** (`swift_spec/`) so a compile error there cannot break the P-tests above.
If the spec's code blocks change shape, the X1/X2 steps fail loudly. Generated files are git-ignored.

| ID | What it proves | File |
|---|---|---|
| P9 | 100 frames at pixel ratio 1.0 / 2.0 in raw, zlib and XOR-delta encodings: every frame decodes correctly; bytes/frame, ms/frame and decode ms/frame are logged (loopback, debug build, optimistic frame content) | `dart_tools/ws_stream_server.dart` + `.../P9_TransportThroughputTests.swift` |
| X1 / X2 | The spec's Dart / Swift blocks can be extracted | `scripts/extract_spec_code.py` |
| S1 | The real `WatchFrameStreamer` captures frames and the real `WatchInputInjector` tap changes the next one | `flutter_proofs/test/s1_spec_streamer_injector_test.dart` |
| S7 | `captureNow()` pushes the current frame from an idle app (and an idle app sends nothing by itself) | `flutter_proofs/test/s7_capture_now_test.dart` |
| S0 | The spec's Swift code compiles for watchOS | `scripts/swift_pkg.sh` |
| S2 | `Color(argb:)` renders the right channels, incl. alpha | `swift_spec/Tests/.../S2_ColorARGBTests.swift` |
| S3 | `WatchFrameStore` + `WatchFrameView` draw a frame stretched to fill the view, whatever size it was captured at | `.../S3_FrameStoreViewTests.swift` |
| S4 | `WatchFrameView` redraws when a new frame is published (experimental) | `.../S4_FrameViewRedrawTests.swift` |
| S5 | `WatchRenderStore` + `@_cdecl` slab API + `WatchCanvasView` draw bytes written the way Dart writes them | `.../S5_RenderStoreCanvasTests.swift` |
| S6 | `WatchCanvasView` redraws on `frameTick` with no `TimelineView` (experimental) | `.../S6_CanvasTickRedrawTests.swift` |

## Round 3 — the whole loop, no stand-ins

| ID | What it proves | File |
|---|---|---|
| E0 | The end-to-end job's setup: simulator boots, spec code extracted, Flutter deps resolve | `scripts/e2e_setup.sh` |
| E1 | **Real `WatchFrameStreamer` + `WatchInputInjector`** (inside `flutter test`, acting as the Mac) behind a real WebSocket **<->** a watchOS client test using the spec's real `WatchFrameStore` + `WatchFrameView`. On connect the server calls `captureNow()`; the watch checks the view shows red, sends a tap in watch-screen coordinates, the server maps it into app coordinates and replays it, and the watch checks the next frame turns the view green | `flutter_proofs/test/e2e_server_test.dart` + `swift_spec/Tests/.../E1_EndToEndTests.swift` + `scripts/run_e2e.sh` |

E1 runs in its own job (`e2e`) because it needs Flutter and the watchOS Simulator on the same machine.

## Round 4 — Open Question 9: can a Flutter engine run on watchOS?

Built from scratch with **official Flutter artifacts, Apple's SDK and `embedder.h` only** — no third-party toolchain —
so anyone (including the Flutter team) can reproduce it. Building the engine itself from source is far beyond a free
hosted runner (step Q0 prints what the runner actually offers), so this job asks the questions that CAN be answered:

| ID | What it answers | Files |
|---|---|---|
| Q0 | What a hosted runner offers (cores, memory, disk) | `scripts/q0_capacity.sh` |
| Q1 | Facts from the real engine source at this SDK's exact engine version (how the build tool and `fml/build_config.h` treat iOS vs macOS; any watchOS mentions) **and whether the engine's own base layer (`fml`) compiles for watchOS** | `scripts/q1_engine_source.sh`, `scripts/syntax_check_one.sh` |
| Q2 | Gathers the official pieces: desktop embedder library, `icudtl.dat`, iOS engine, and a `flutter_assets` bundle of the probe app | `scripts/q2_engine_artifacts.sh`, `engine_probe/app/` |
| Q3 | **Gap analysis:** which libraries and symbols the official engines import that the watchOS SDK does not provide | `scripts/engine_gap.py`, `scripts/q3_gap.sh` |
| Q4 | **Experiment:** retag the official desktop embedder library as a watchOS Simulator binary, stub the libraries watchOS lacks, and see whether a watchOS process can load it and find the embedder API | `scripts/q4_retarget_load.sh`, `scripts/make_stubs.py`, `engine_probe/engine_dlopen.c` |
| Q5 | **Experiment:** run Flutter inside a watchOS process through `embedder.h` with the software renderer, using a host written from scratch, and check the rendered pixels (Dart ran, text rendered, a second region painted) | `scripts/q5_run_engine.sh`, `engine_probe/engine_host.c`, `scripts/frame_check.py` |
| Q6 | **Experiment:** interactive loop inside a watchOS process: tap injected via `FlutterEngineSendPointerEvent`, Dart `setState` executed, Frame 2 rendered and verified; memory footprint logged | `scripts/q6_interactive_engine.sh`, `engine_probe/engine_host.c`, `scripts/frame_check.py` |

The frames the engine rendered are uploaded as the `engine-frame` (Frame 1) and `engine-interactive-frame` (Frame 2) artifacts.

**Read the results correctly.** A retagged macOS binary is *not* a shippable port — it is an experiment to find out how far
the real engine code gets inside a watchOS process and exactly what stops it. Q3's output is findings, not pass/fail, and its overall symbol counts are unreliable (see the catalog).
A real port needs the engine built with its own build tool for a watchOS SDK, which needs a larger machine than a
free runner. The gap list from Q3/Q4 is what that port has to replace.

## Run locally (Mac with Xcode + Flutter)

```bash
cd watchos-proofs/flutter_proofs && flutter pub get && flutter test           # P2, P3
bash scripts/pick_watch_sim.sh                                  # P1 (prints the simulator UDID)
export WATCH_UDID=<udid printed above>
dart run dart_tools/gen_wire_fixture.dart                       # needed by A3
bash scripts/run_swift_test.sh P4_RgbaToCGImageTests            # any single test class
bash scripts/run_p6_with_server.sh                              # P6 (starts/stops the server)
```

## Not covered (needs more than a free runner)

- **A source-built or AOT Flutter engine on watchOS, and anything on a real watch** (Open Question 9). Q4/Q5 run a patched, retagged *debug* engine in a Simulator process; they do not cover a from-source build, the Dart VM on watchOS, AOT, or App Store acceptance.
- **Memory ceiling, frame times, battery** — the Simulator uses the Mac's resources.
- **Real Wi-Fi behaviour** (foreground-session suspension, reconnect) — loopback only.
- **Dart FFI running on the watch** — A4 proves symbol lookup, not a Dart runtime on watchOS.
- **A4 caveat:** the test references the function directly, so it does not prove the symbol survives
  dead-stripping in a release app build.

## Known uncertainties (a failure here is informative, not necessarily a bug in the idea)

- **Running XCTest on a watchOS Simulator from a Swift package** — if P4 fails with a host-app /
  test-bundle message, that is the finding, and the fix is a minimal Xcode project with a watch host.
- **`ImageRenderer` + `Canvas`** (P5, A1) is the least certain piece.
- **`ws://127.0.0.1`** should pass App Transport Security (IP addresses are exempt) — P6 will tell.
- If the runner image has no watchOS runtime, P1 tries `xcodebuild -downloadPlatform watchOS`.
