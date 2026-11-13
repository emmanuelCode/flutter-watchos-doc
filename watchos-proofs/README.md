# watchOS proofs — one tiny test per untested idea

> **TL;DR — What is actually proven vs. unproven:**
> - **Proven (Simulator only):** SwiftUI `Canvas` draws RGBA frames, `RepaintBoundary.toImage` captures headless frames, `ws://` loopback streams frames and returns taps (`E1`), and a *retagged* macOS debug JIT engine runs Dart and handles synthetic tap/scroll events in a Simulator process (`Q4`–`Q7`).
> - **Not proven:** Any from-source or AOT watchOS engine build, real watch memory/jetsam/battery, real Wi-Fi/BLE transport (Mode 1b), `watchos_ui` widgets (not yet built), or App Store acceptance.


Each check in this folder answers one question about running a Flutter app on Apple Watch. The checks run
in CI (GitHub Actions, macOS runner, watchOS Simulator) and most of them can also be run on your own Mac.

- **CI:** `.github/workflows/proofs.yml` (at the **repo root**) runs on push, pull request and manual dispatch.
  Each *step name* is one concept, so read the step list as the checklist. The last job,
  **"RESULTS — open this job and copy the block"**, prints one result sheet (also saved in the run Summary page).
- **Locally:** see [Run locally](#run-locally-mac-with-xcode--flutter).

> The runner provides a Mac and a *simulated* Apple Watch, not a physical watch. These tests prove that the code
> compiles, the logic works and the pieces connect. They do **not** prove memory limits, speed, battery or
> real-hardware pixel parity (see [Not covered](#not-covered)).

## How to read the result sheet

```
✅ pass   ❌ fail (evidence lines printed below)   ⛔ blocked by P1/P0   ⬜ no result recorded
```

Fix order: **F0 → P1 → P0 → everything else.** A failure in P1 or P0 blocks the Swift tests, so those show ⛔
instead of failing for confusing reasons. Full logs are attached to the run as `logs-*` artifacts, but only when
something fails.

**Latest result:** 34 of 34 checks passed (commit ba93b27, run 43286738502; runner image macos26 20261102.0473.1, macOS 26.7.2,
Xcode 26.6, watchOS 26.5 Simulator, Flutter 3.50.0, Dart 3.14.0 on all jobs).

## Capability-to-check traceability

The main spec (`flutter_watchos_architecture.md`) summarizes validation by capability; this table maps each capability to its CI check IDs:

| Spec capability | Check IDs |
|---|---|
| Watch-side SwiftUI renderer (`WatchFrameStore`, `WatchFrameView`) | `P0, P1, P4, P5, X2, S0, S3, S4` |
| Headless Dart frame capture & input (`WatchFrameStreamer`, `WatchInputInjector`) | `F0, P2, P3, X1, S1, S7` |
| Loopback WebSocket transport & sustained throughput (Simulator-only per TN3135) | `P6, P9` |
| End-to-end Simulator dev loop | `E0, E1` |
| Path B display-list fixtures (`docs/display-list-research.md`) | `A1, A2, A3, A4, S2, S5, S6` |
| Engine-on-watchOS smoke test (retagged Mac JIT binary in Simulator) | `Q0, Q1, Q2, Q2s, Q3, Q4, Q5, Q6, Q7` |

## Test catalog

**34 checks in four jobs**, all run on a macOS GitHub runner with the watchOS Simulator. IDs are not contiguous
(there is no P7 or P8: they were planned and dropped).

**Honest labeling.** "Tested" always means *tested in the watchOS Simulator on a macOS runner*, never on a physical
watch. The Simulator runs as an ordinary process on the Mac, so it uses the Mac CPU and memory.

**Type:** **Setup** = prepares or checks the environment. **Proof** = a pass/fail claim. **Measure** = numbers are
logged; a pass only means the numbers were produced. **Finding** = the output is information, not a verdict.
**Experiment** = deliberately pushes something unsupported to see how far it gets.

### Job `flutter-side` (runs Flutter on a Mac)

| ID | Type | What it tests | Purpose | A pass means — and its limits |
|---|---|---|---|---|
| F0 | Setup | `flutter pub get` for the Flutter proof package | Everything Dart-side depends on it | The toolchain and packages resolve |
| P2 | Proof + Measure | `RepaintBoundary.toImage` captures a frame with no window, as raw RGBA | The dev loop needs frames from an app with no visible window | Capture works headless; byte counts are exact (191,664 B at pixel ratio 1.0, 766,656 B at 2.0). *Limit:* the test renderer, so timings are not real GPU readback cost |
| P3 | Proof | A tap injected through `GestureBinding` fires a `GestureDetector`, runs `setState`, and changes the next frame | The watch sends taps; the Mac must be able to replay them into the app | Pointer injection with public APIs works |
| X1 | Setup | Extracts the Dart code blocks of the spec into files | Tests run the actual spec code, not a copy | The spec still contains the blocks in the expected shape; fails loudly if the spec changes shape |
| S1 | Proof | The real `WatchFrameStreamer` and `WatchInputInjector` from the spec: capture, tap, next frame | Checks the spec code itself, not a stand-in | Works. Also revealed that an idle app produces no frames (led to `captureNow()`) |
| S7 | Proof | `captureNow()` pushes the current frame from an idle app (and an idle app sends nothing by itself) | A watch that connects late must still get an image | Exactly one frame is pushed on demand |

### Job `swift-watchos` (watchOS Simulator)

| ID | Type | What it tests | Purpose | A pass means — and its limits |
|---|---|---|---|---|
| P1 | Setup | A watchOS Simulator exists on the runner and boots | Every Swift check needs one | Hosted runners ship a usable watchOS runtime (answers Open Question 10) |
| P0 | Setup + Proof | The Swift proof package compiles for watchOS and runs XCTest there with no host app | Confirms the test approach itself works | Swift builds for watchOS and tests execute in the Simulator |
| P4 | Proof | Raw RGBA bytes become a `CGImage` with the right pixels | This is how frames from Flutter reach the screen | The conversion is correct |
| P5 | Proof | A SwiftUI `Canvas` draws that image (pixels checked via `ImageRenderer`) | Confirms the display path | Canvas draws the right pixels. *Limit:* an off-screen renderer, not the on-screen watch display |
| P6 | Proof | A Dart WebSocket server and a watchOS client: a frame comes down, a tap goes up, over loopback | Proves the Mac-to-watch transport can work, and that the Simulator can reach the host | A 191,664 B frame and a tap round-trip. *Limit:* loopback only, not real Wi-Fi |
| P9 | Measure | 100 frames at pixel ratio 1.0 and 2.0, each raw, zlib and XOR-delta; every frame decoded and checked | Chooses the transport encoding and bounds bandwidth | Numbers logged. On mostly-static test frames zlib is about 1 KB (1.0) and 3.9 KB (2.0) per frame; XOR-delta saves only about 11–12% more and decodes about 20–40× slower. *Limit:* best case: static content, loopback, debug build, Mac CPU |
| A1 | Proof (Appendix A) | Canvas text anchored `.topLeading` stays in the corner; the default `.center` loses it | Display-list research path only | Confirms the anchor fix (47 lit pixels vs 10) |
| A2 | Proof (Appendix A) | Triple-buffer mailbox: the writer never blocks, the newest frame wins | Display-list research path only | The mailbox logic is correct |
| A3 | Proof (Appendix A) | Bytes written by Dart parse correctly in Swift (UTF-8, padding, misaligned base, truncation) | Display-list research path only | Wire format agrees across languages. *Limit:* a stand-in writer, not the real `ZeroCopyCanvas` |
| A4 | Proof (Appendix A) | A `@_cdecl` Swift function is found by `dlsym` (what `DynamicLibrary.process()` in Dart uses) | Display-list research path only | Symbol lookup works. *Limit:* not a Dart runtime on watchOS, and it does not prove the symbol survives dead-stripping in a release build |
| X2 | Setup | Extracts the Swift code blocks of the spec into a separate package | Same as X1, isolated so a spec error cannot break the P-tests | The blocks are present and extractable |
| S0 | Proof | The Swift code of the spec compiles for watchOS | The spec code is real, not pseudocode | It builds |
| S2 | Proof | `Color(argb:)` renders the right channels, including alpha | The colour helper from the spec | Channel order and alpha are correct |
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

Built only from official Flutter artifacts, Apple SDK and `embedder.h`, with no third-party toolchain. Building the
engine from source is beyond a hosted runner, so these checks ask what *can* be answered.

| ID | Type | What it tests | Purpose | A pass means — and its limits |
|---|---|---|---|---|
| Q0 | Measure | What a hosted runner offers | Whether an engine build could fit | 3 cores, 7 GB RAM, about 93 GB free disk; hosted jobs are capped at 6 h and the engine job at 60 min. A from-source engine build is not attempted here |
| Q1 | Finding + Proof | Facts from the real engine source at the commit pinned by this SDK, and whether the engine base layer (`fml`) compiles for watchOS with C++20 | Shows how much of the engine already fits watchOS | The engine build tool (`tools/gn`) has no watchOS target, although the Dart SDK `tools/gn.py` accepts `watchos` and `watchos_simulator`; `embedder.h` has 47 functions with a software renderer; the Apple header gives `TARGET_OS_IPHONE 1` on watchOS, so `fml` treats it as iOS; 49 of 55 sampled `fml` files compile cleanly and none fail for an unavailable API (6 undecided for want of `third_party` headers) |
| Q2 | Setup | Gathers official pieces: the desktop embedder library (only `darwin-x64` is published; it is universal x86_64 + arm64), `icudtl.dat`, the iOS engine, and a probe app bundle | Inputs for Q3–Q5 | The artifacts exist and download |
| Q2s | Setup | A watch simulator boots in this job | Q4 and Q5 run in it | Ready |
| Q3 | Finding | Gap analysis: which libraries and symbols the official engines import that the watchOS SDK does not provide | Maps what a port must replace | Direct lookups are reliable: the watchOS SDK exports `CAMetalLayer`, `CGBitmapContextCreate` and `CTFontCreateWithName` but not `MTLCreateSystemDefaultDevice` or `IOSurfaceCreate`; 7 libraries are absent. **The per-library missing-symbol totals are not reliable** (the script flags basic `libSystem` symbols such as `_bzero` as missing), so no total is quoted |
| Q4 | Experiment | Retag the official desktop embedder library as a watchOS Simulator binary and see whether a watchOS process can load it | Finds exactly what stops the real engine code | It loads, after rewriting 8 framework paths, stubbing 7 absent libraries and overlaying 4 CoreVideo symbols; `FlutterEngineRun` and two other API symbols resolve. A retagged macOS binary is not a shippable port |
| Q5 | Experiment | Run Flutter inside a watchOS process through `embedder.h` with the software renderer, using a host written from scratch; check the rendered pixels | Shows how far the real engine gets | Dart executed (a stripe is green only if `fib(20) == 6765`), text shaped and drew (746 bright glyph pixels in the latest run) and a frame came through the present callback. The pixel byte order of the callback is RGBA in this engine build, inferred from the pass. *Limits:* a patched debug (JIT) engine in a Mac-hosted Simulator process; it proves nothing about a source build, AOT, a real watch, memory, speed or App Store review |
| Q6 | Experiment | Interactive loop inside a watchOS process: tap injected via `FlutterEngineSendPointerEvent`, Dart `setState` executed, frame 2 rendered and verified; memory footprint logged | Shows the engine runs an interactive event loop on watchOS | Dart received touch input, executed `setState`, reshaped text to TAP, repainted yellow/cyan stripes and presented frame 2. Resident and virtual memory measured via Mach task info (about 140.1–143.0 MB resident under Flutter 3.50.0 debug mode). *Limits:* JIT debug engine in the Simulator |
| Q7 | Experiment | Crown scroll input (`signal_kind=scroll` -> `setState` -> frame 3) and the low-memory hook | Demonstrates rotary event handling and the low-memory embedder hook | The scroll signal reached Dart (`Listener` -> `PointerScrollEvent` -> `setState`), text repainted to CROWN, frame 3 rendered; `FlutterEngineNotifyLowMemoryWarning` succeeded without crashing. *Limits:* synthetic engine signal, no hardware Crown or SwiftUI `.digitalCrownRotation` |

The frames the engine rendered are uploaded as the `engine-frames` artifact (frames 1, 2 and 3).

**Read the engine results correctly.** A retagged macOS binary is *not* a shippable port. It is an experiment to find
out how far the real engine code gets inside a watchOS process and exactly what stops it. Q3 output is findings, not
pass/fail. A real port needs the engine built with its own build tool for a watchOS SDK, which needs a larger machine
than a free runner. The gap list from Q3 and Q4 is what that port has to replace.

### What the results mean together

- **The development loop works in the Simulator:** a Flutter app on the Mac can send frames to a watchOS client, and
  taps come back (25 dev-loop checks, including E1).
- **The official engine code can start, draw frames and take input under the watchOS Simulator SDK after patches that
  cannot ship** (Q0–Q7): it executes Dart, shapes text, renders frames and processes tap and scroll input. That shows
  the engine is not fundamentally hostile to the SDK. It is not a port.
- **Still unproven:** an engine built from source for watchOS, the Dart VM on watchOS, AOT code, anything on a real
  watch, memory and speed there, real Wi-Fi, and App Store acceptance.

## Where each check lives

| IDs | Files |
|---|---|
| F0 | `flutter_proofs/pubspec.yaml` |
| P1 | `scripts/pick_watch_sim.sh` |
| P0 | `scripts/build_swift.sh` |
| P2, P3 | `flutter_proofs/test/p2_headless_frame_capture_test.dart`, `flutter_proofs/test/p3_tap_injection_test.dart` |
| P4, P5 | `swift_proofs/Tests/WatchProofsTests/P4_RgbaToCGImageTests.swift`, `.../P5_CanvasDrawsPixelsTests.swift` |
| P6 | `dart_tools/ws_server.dart`, `scripts/run_p6_with_server.sh`, `.../P6_WebSocketLoopbackTests.swift` |
| P9 | `dart_tools/ws_stream_server.dart`, `scripts/run_with_server.sh`, `.../P9_TransportThroughputTests.swift` |
| A1–A4 | `.../A1_TextAnchorTests.swift`, `.../A2_MailboxTests.swift` (+ `Sources/WatchProofs/Mailbox.swift`), `.../A3_WireFormatTests.swift` (+ `dart_tools/gen_wire_fixture.dart`), `.../A4_CdeclSymbolTests.swift` |
| X1, X2 | `scripts/extract_spec_code.py` (writes generated files, which are git-ignored) |
| S1, S7 | `flutter_proofs/test/s1_spec_streamer_injector_test.dart`, `flutter_proofs/test/s7_capture_now_test.dart` |
| S0 | `scripts/swift_pkg.sh` |
| S2–S6 | `swift_spec/Tests/SpecCodeTests/S2_…` to `S6_…` |
| E0, E1 | `scripts/e2e_setup.sh`, `scripts/run_e2e.sh`, `flutter_proofs/test/e2e_server_test.dart`, `swift_spec/Tests/SpecCodeTests/E1_EndToEndTests.swift` |
| Q0 | `scripts/q0_capacity.sh` |
| Q1 | `scripts/q1_engine_source.sh`, `scripts/syntax_check_one.sh` |
| Q2 | `scripts/q2_engine_artifacts.sh`, `engine_probe/app/` |
| Q3 | `scripts/q3_gap.sh`, `scripts/engine_gap.py` |
| Q4 | `scripts/q4_retarget_load.sh`, `scripts/make_stubs.py`, `engine_probe/engine_dlopen.c` |
| Q5 | `scripts/q5_run_engine.sh`, `engine_probe/engine_host.c`, `scripts/frame_check.py` |
| Q6 | `scripts/q6_interactive_engine.sh`, `engine_probe/engine_host.c`, `scripts/frame_check.py` |
| Q7 | `scripts/q7_crown_and_memory.sh`, `engine_probe/engine_host.c`, `scripts/frame_check.py` |

The primary spec is `flutter_watchos_architecture.md` at the repo root (and Path B display-list blocks live in `docs/display-list-research.md`). The CI step wrapper
`scripts/step.sh` is described in [How the reporting works](#how-the-reporting-works).

## Run locally (Mac with Xcode + Flutter)

**Prerequisites:** macOS with Xcode and the watchOS platform installed (Xcode > Settings > Components), Flutter
(stable channel; it ships Dart), `python3` and `nc` (both are on macOS by default).

**Every command below is run from the `watchos-proofs/` folder** (the one that holds `scripts/` and `dart_tools/`),
unless a command says otherwise. Start with:

```bash
cd watchos-proofs
```

### 1. Flutter side (F0, P2, P3, X1, S1, S7)

```bash
( cd flutter_proofs && flutter pub get )                                              # F0
python3 scripts/extract_spec_code.py ../flutter_watchos_architecture.md dart     # X1 (needed by S1, S7)
( cd flutter_proofs && flutter test test/p2_headless_frame_capture_test.dart test/p3_tap_injection_test.dart test/s1_spec_streamer_injector_test.dart test/s7_capture_now_test.dart )
```

Do **not** run a bare `flutter test`: it would also pick up `test/e2e_server_test.dart` (E1), which waits for a
watchOS client and fails on its own. E1 is run through `scripts/run_e2e.sh` (step 4).

### 2. Watch simulator and Swift proofs (P1, P0, P4, P5, P6, P9, A1–A4)

```bash
bash scripts/pick_watch_sim.sh                      # P1: look for the line "INFO: watch simulator ... <UDID>"
export WATCH_UDID=<udid from that line>

# P0 scheme. CI picks it automatically (it resolved to WatchProofs on Xcode 26.6); locally you set it yourself:
if ( cd swift_proofs && xcodebuild -list 2>/dev/null | grep -q WatchProofs-Package ); then export SCHEME=WatchProofs-Package; else export SCHEME=WatchProofs; fi

bash scripts/build_swift.sh                         # P0 (compile for watchOS)
bash scripts/run_swift_test.sh P4_RgbaToCGImageTests        # P4 (any single test class works the same way)
bash scripts/run_swift_test.sh P5_CanvasDrawsPixelsTests    # P5
bash scripts/run_p6_with_server.sh                          # P6 (starts and stops the Dart server)
bash scripts/run_swift_test.sh A1_TextAnchorTests           # A1
bash scripts/run_swift_test.sh A2_MailboxTests              # A2
dart run dart_tools/gen_wire_fixture.dart                   # needed by A3 (writes /tmp/watch_fixture/frame.bin)
bash scripts/run_swift_test.sh A3_WireFormatTests           # A3
bash scripts/run_swift_test.sh A4_CdeclSymbolTests          # A4
bash scripts/run_with_server.sh dart_tools/ws_stream_server.dart 8766 P9_TransportThroughputTests   # P9
```

Measurements logged by the tests are appended to `/tmp/watch_proofs/results.log`.

### 3. Spec code on watchOS (X2, S0, S2–S6)

```bash
python3 scripts/extract_spec_code.py ../flutter_watchos_architecture.md swift    # X2
bash scripts/swift_pkg.sh build swift_spec SpecCode                                   # S0
bash scripts/swift_pkg.sh test swift_spec SpecCode SpecCodeTests/S2_ColorARGBTests    # S2 (same pattern for S3 to S6)
```

The test classes are `S2_ColorARGBTests`, `S3_FrameStoreViewTests`, `S4_FrameViewRedrawTests`,
`S5_RenderStoreCanvasTests` and `S6_CanvasTickRedrawTests`.

### 4. End to end (E0, E1)

Needs `WATCH_UDID` from step 2, and the spec code extracted for both Dart and Swift (steps 1 and 3).

```bash
( cd flutter_proofs && flutter pub get )     # E0 (Flutter deps)
bash scripts/run_e2e.sh                      # E1 (builds swift_spec, starts the Flutter server, runs the watchOS client)
```

### 5. Engine checks (Q0–Q7)

These download official Flutter engine artifacts and patch and retag binaries, and they were written for the CI runner
(`engine` job). They are **not verified for local use**, so run them through CI. If you try them locally anyway, run
them in order from `watchos-proofs/`: each later step depends on files the earlier ones leave in `/tmp`.

### If something fails

- `No such file or directory: scripts/...` means you are in the wrong folder. Run `cd` to `watchos-proofs/`.
- `scheme ... not found` means `SCHEME` is wrong: run `( cd swift_proofs && xcodebuild -list )` and export the
  scheme it lists.
- `WATCH_UDID is not set` or `Unable to find a destination` means step 2 was skipped or the simulator is gone: rerun
  `bash scripts/pick_watch_sim.sh` and export the UDID again.
- Compile errors about `flutter_proofs/lib/spec/...` or `SpecCode` mean the spec extraction (X1 or X2) has not run.
- A port already in use (8765, 8766, 8767) means a previous server is still running: stop it with `pkill -f ws_server.dart`,
  `pkill -f ws_stream_server.dart` or `pkill -f e2e_server_test`.

## How the reporting works

`scripts/step.sh` wraps every proof step in CI: it runs the command, keeps the exit code (so the step still goes red),
and appends `PASS` / `FAIL` plus a few evidence lines to a results file (`/tmp/proof_results.txt`). Each job uploads
that file; the final job runs `scripts/report.py` to merge them into one block. When you run the scripts directly, as
above, you get each script output and exit code instead; use `scripts/step.sh <ID> <command>` if you want the same
result lines locally.

## Not covered

Needs more than a free runner:

- **A source-built or AOT Flutter engine on watchOS, and anything on a real watch** (Open Question 9). Q4–Q7 run a
  patched, retagged *debug* engine in a Simulator process; they do not cover a from-source build, the Dart VM on
  watchOS, AOT, or App Store acceptance.
- **Memory ceiling, frame times, battery:** the Simulator uses the resources of the Mac.
- **Real Wi-Fi behaviour** (foreground-session suspension, reconnect): loopback only.
- **Dart FFI running on the watch:** A4 proves symbol lookup, not a Dart runtime on watchOS.
- **A4 caveat:** the test references the function directly, so it does not prove the symbol survives dead-stripping in
  a release app build.

## Known uncertainties

A failure here is informative, not necessarily a bug in the idea.

- **Running XCTest on a watchOS Simulator from a Swift package:** if P4 fails with a host-app or test-bundle message,
  that is the finding, and the fix is a minimal Xcode project with a watch host.
- **`ImageRenderer` + `Canvas`** (P5, A1) is the least certain piece.
- **`ws://127.0.0.1`** should pass App Transport Security (IP addresses are exempt); P6 will tell.
- If the runner image has no watchOS runtime, P1 tries `xcodebuild -downloadPlatform watchOS`.
