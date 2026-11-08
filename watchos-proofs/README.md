# watchOS proofs — one tiny test per untested idea

The GitHub Actions workflow (`.github/workflows/proofs.yml`) runs on a **macOS runner** with the
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

## Run locally (Mac with Xcode + Flutter)

```bash
cd flutter_proofs && flutter pub get && flutter test           # P2, P3
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
