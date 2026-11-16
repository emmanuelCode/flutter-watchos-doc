# Flutter for watchOS — Maintainer Summary

> **Status:** Design specification + Simulator CI evidence (`commit 740962b`, run `43749925381`). **Not a working watchOS port.**

## What this is / is NOT

- **Is:** A proposed `embedder.h` architecture (`Path A`: Flutter engine software/compositor rasterization presented via SwiftUI `Canvas`), an SDK-gap and engine-source audit (`Q1`, `Q3`), a Simulator dev-loop proof (`34/34` checks passed in CI), and a zero-Material/Cupertino widget PoC (`packages/watchos_ui`, `14/14` Linux unit tests passed).
- **Is NOT:** A working or shippable watchOS engine build, an AOT runtime, or hardware-verified. Checks `Q4`–`Q7` run a **retagged macOS debug JIT engine** with stubbed frameworks in a Simulator process—a wiring experiment that **never ships**.
- **Public-API stance:** This design uses only public watchOS SDK APIs; the alternative route (`flutter-watchos`) is unassessed here.

## Evidence Summary (`740962b` / run `43749925381`, `Flutter 3.50.0` / `Dart 3.14.0`, `Xcode 26.6`, `watchOS 26.5 Simulator`)

| Claim | Evidence (check ID, file) | Limits | Transfers to real watch? |
|---|---|---|---|
| SwiftUI `Canvas` decodes & draws RGBA frames | `P0, P1, P4, P5, X2, S0, S3, S4` (`watchos-proofs/swift_proofs/Sources/WatchProofs/FrameImage.swift`, `watchos-proofs/swift_spec/Tests/SpecCodeTests/S3_FrameStoreViewTests.swift`, `S4_FrameViewRedrawTests.swift`) | `ImageRenderer` off-screen in `watchOS-26-5` Simulator (`46mm`); live on-screen display invalidation & AOD untested | **Partly** (compiles & decodes; live screen timing does not) |
| Headless Dart capture & pointer tap replay work | `F0, P2, P3, X1, S1, S7` (`watchos-proofs/flutter_proofs/test/p2_headless_frame_capture_test.dart`, `p3_tap_injection_test.dart`, `s1_spec_streamer_injector_test.dart`, `s7_capture_now_test.dart`) | `flutter test` renderer (`800x600`, `191664` B @ `1.0` / `766656` B @ `2.0`); not real GPU readback cost | **Yes** (runs on Mac host in dev mode) |
| Loopback `ws://` dev loop & sustained transport | `P6, P9, E0, E1` (`watchos-proofs/dart_tools/ws_stream_server.dart`, `watchos-proofs/swift_proofs/Tests/WatchProofsTests/P9_TransportThroughputTests.swift`, `watchos-proofs/swift_spec/Tests/SpecCodeTests/E1_EndToEndTests.swift`) | `P6`: `291 ms` first frame; `P9` (`100` static loopback frames): zlib `1047 B` / `2.5 ms` (`1.0`), `3935 B` / `8.9 ms` (`2.0`); `E1`: `2` frames in `flutter test`, no real Mac window or hot reload | **No** for `ws://` (**Simulator-only**; real LAN HTTP/`WCSession` untested) |
| Official engine & watchOS SDK gap audit | `Q1, Q3` (`watchos-proofs/scripts/q1_engine_source.sh`, `q3_gap.sh`, `engine_gap.py`) | Static `.tbd` + header compile probes only; full `ninja`/AOT build not attempted (`60 min` job cap, `5` cores, `14 GB` RAM, `93 GB` disk) | **Yes** (direct Apple SDK & engine source facts) |
| Patched `embedder.h` runs Dart + tap/scroll in Sim | `Q4, Q5, Q6, Q7` (`watchos-proofs/scripts/make_stubs.py`, `watchos-proofs/engine_probe/engine_host.c`, `app/lib/main.dart`) | Retagged macOS debug JIT binary (`8` path rewrites, `7` stubs, `4` CoreVideo overlays); `141.64`/`142.89 MB` (`Q6`) & `140.53–142.41 MB` (`Q7`) resident in Mac JIT Simulator; synthetic scroll only; **never ships** | **No** (API-wiring check only; no source/AOT/device proof) |
| Pure-Dart `watchos_ui` widgets & HIG checker | `watchos_ui` Linux CI (`packages/watchos_ui/test/watchos_ui_test.dart`, `packages/watchos_ui/lib/src/hig_checker.dart`, `.github/workflows/watchos_ui.yml`) | `9/9` unit tests passed (`linux_x64`); zero Material/Cupertino; v0 numeric HIG bounds unverified | **Partly** (Dart layer only; needs watchOS engine for prod) |
| Archived Path B display-list fixtures | `A1–A4, S2, S5, S6` (`watchos-proofs/swift_proofs/Tests/WatchProofsTests/`, `watchos-proofs/swift_spec/Tests/SpecCodeTests/`) | Stand-in writer & off-screen tests; `ZeroCopyCanvas` & `DRAW_TEXT` unverified; does **not** validate Path A | **Partly** (wire/anchor checks; perf unverified) |

## Three Contributions Useful Regardless of Embedder Route

1. **Reproducible public-SDK gap analysis (`Q3`):** Parses watchOS `.tbd` stubs and compiles Clang/Swift header probes against `--sdk watchos`. `FlutterEmbedder` misses `22 of 673` imported symbols on both `watchsimulator` and `watchos` (`+0 libs, +0 / -0 syms` delta; `Metal`, `CoreVideo`, `MPS`, `IOKit`); `ios_Flutter` misses `44 of 1077` on `watchos` (`46` on `watchsimulator`). Compiler probes confirm `Metal/Metal.h`, `CAMetalLayer`, `UIView`, and `fork()` fail on `--sdk watchos`, while `SKMutableTexture`, `SKTexture(data:size:)`, `SpriteView`, `CoreGraphics`, `CoreText`, `WKCrownSequencer`, and `chdir` compile.
2. **Engine-source porting facts (`Q1`):** At pinned engine commit `371f77202a73e8dff57a8b3bff75bca55c090aee` (`Dart 3.14.0`), `embedder.h` exports `47` functions with software renderer config; `tools/gn` lists `android, ios, mac, linux, fuchsia, wasm, win, qnx` (`0` watchOS mentions; `qnx` is software-only `arm64`), while Dart `tools/gn.py` accepts `watchos` / `watchos_simulator`. `fml/build_config.h` maps `TARGET_OS_IPHONE` to `FML_OS_IOS`, and `49/55` `fml` files compile on both `watchsimulator` and `watchos` (`0` unavailable-API errors; `6` missing `third_party` headers).
3. **Engine-agnostic `watchos_ui` + HIG checker (`packages/watchos_ui`):** Standalone widgets strictly on `package:flutter/widgets.dart` (`WatchOSApp`, `WatchOSButton`, `WatchOSPageScaffold`, `WatchOSListScaffold`, `WatchOSProgressRing`, `WatchOSHigChecker`, `WatchOSPreviewFrame`).

## What Is NOT Proven & What Someone With Hardware Can Run (`Gate 0d`)

- **Unproven:** Source-built/AOT watchOS engine & Dart VM, real-watch RSS/jetsam headroom, CPU frame times & battery, live SwiftUI invalidation/AOD, physical `.digitalCrownRotation` mapping, LAN HTTP/`WCSession` streaming, and App Store review acceptance.
- **Hardware probe (`Gate 0d`, built in [`gate0d_probe/`](../gate0d_probe/watch_app/README.md); Simulator negative-control CI verified, unverified on physical hardware):** Build and sign `gate0d_probe/watch_app` on a physical watch (see [docs/gate-0d-probe.md](gate-0d-probe.md)) against `gate0d_probe/mac_echo_server/probe_server.dart` across the two-run `IPHONE_LINK` matrix to paste one output block recording: `mmap(MAP_JIT)` / `mprotect(PROT_EXEC)` result, BSD socket / `NWConnection` / `URLSessionWebSocketTask` blocked status, `URLSession.bytes` LAN latency & throughput (incl. offline router + `.local`), RGBA/zlib decode time, and Mach resident memory (`WCSession` deferred to v1.1; alongside `Gate 0b` TestFlight validation of `SpriteView` vs. Metal linkage and `Gate 0c` on-device AOT `hello_world` RSS).

## Links & Provenance

- **Architecture spec:** [flutter_watchos_architecture.md](../flutter_watchos_architecture.md) · **Proofs catalog & local commands:** [watchos-proofs/README.md](../watchos-proofs/README.md) · **UI package:** [packages/watchos_ui/README.md](../packages/watchos_ui/README.md) · **Hardware probe (`Gate 0d`):** [docs/gate-0d-probe.md](gate-0d-probe.md)
- **Changelog:** [CHANGELOG.md](../CHANGELOG.md) (full history: [docs/history/CHANGELOG-full.md](history/CHANGELOG-full.md))
- **CI results:** Latest archived `proofs.yml` sheet is [2026-11-15-740962b.md](results/2026-11-15-740962b.md) / run `43749925381` (also in [docs/results/latest.md](results/latest.md)); `watchos_ui` Linux CI was not triggered on `740962b` (`packages/watchos_ui/**` unchanged).
- **Who verified what:** See [AIREADME.md section 2](../AIREADME.md#2-how-ai-was-used-provenance). `TODO(author): state which parts I personally reviewed vs AI-generated`
