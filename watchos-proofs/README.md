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

The frame the engine rendered is uploaded as the `engine-frame` artifact.

**Read the results correctly.** A retagged macOS binary is *not* a shippable port — it is an experiment to find out how far
the real engine code gets inside a watchOS process and exactly what stops it. Q3's numbers are findings, not pass/fail.
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

- **The Flutter engine on watchOS** (Open Question 9) — building it is far bigger than a smoke test.
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
