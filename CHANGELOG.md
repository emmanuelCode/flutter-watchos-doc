# Changelog

## November 2026 — Reorganization, Audit Fixes & Platform Gates (supersedes v9.1)
- Renamed `flutter_watchos_architecture_v9_1.md` to `flutter_watchos_architecture.md` (`Status: Draft`) and dropped version numbers from the main spec header.
- Split Appendix A into `docs/display-list-research.md`, `Future Horizon (wearos_ui)` into `docs/wearables-ui-strategy.md`, and version history into `CHANGELOG.md`.
- Raised product device floor to `watchOS 27+` (`SE 3, Series 9+, Ultra 2+`; `arm64`-only per toolchains), closed Open Question 8, and added provisional `40/44 mm` SE 3 presets.
- Updated `WatchFrameStreamer` with `_capturePending` coalescing and `stop()`, plus matching unit tests.
- Marked `ws://` WebSocket transport Simulator-only per Apple TN3135; documented experimental Mode 1b constraints.
- Synced Q7 memory figures to recent CI runs (`140.1–143.0 MB`) and moved opaque check IDs/run sheets to `watchos-proofs/README.md` with a capability traceability table.

### v9.1: November 2026 (Proof Suite Catalog Alignment & Toolchain Refresh)
- **Proof Suite Synchronization:** Added check Q7 (Crown scroll input & low-memory hook) to the test catalog in README.md, aligning the documentation with all 34 passing checks.
- **Q1 Source Facts Verified:** Confirmed GN target-OS choices (including `qnx`) and Dart `tools/gn.py` target acceptance directly from live CI runner output (run 43132069600).
- **Latency Upper Bound:** Widened P6 first-frame latency range to 120–259 ms reflecting run 43132069600.
- **Engine Toolchain Refresh:** Updated pinned engine commit to `371f77202a…` (Flutter 3.50.0 / Dart 3.14.0) and documented the ~4–5 MB baseline resident memory shift (141.0–143.0 MB vs 145.6–148.3 MB on 3.47).
- **fml Compilation Status:** Refreshed fml test compilation count to 49 of 55 files compiling cleanly for watchOS.
- **Environment Precision:** Clarified toolchain reporting across jobs (Flutter 3.50.0 on dev-loop, Dart 3.14.0 across all) and removed stale Dart commit pin.

### v9.0: November 2026 (Wearables Decoupling Strategy, Screen Profiles & Review Hardening)
- **Architectural Horizon:** Added decoupled wearable UI strategy (`watchos_ui` vs. `wearos_ui`) modeled after Flutter's `cupertino` vs. `material` decoupling, while identifying wearos_ui as out of scope for the watchOS embedder.
- **Refreshed Validation Numbers:** Widened process memory range to 145.6–148.3 MB (accounting for Q7 frame 2 reading 148.27 MB), updated P6 first-frame latency range to 120–232 ms, and documented toolchain differences across jobs (Dart 3.13.7 for dev-loop vs. Dart 3.14.0 for engine checks).
- **Modern Screen Profiles:** Added Apple Watch Series 10/11 display dimensions (42 mm 187×223 pt, 46 mm 208×248 pt) and noted test-profile resolution gap against the 46 mm CI runner.
- **Risk Assessment:** Added Skia CPU deprecation and Impeller's lack of a software rasterizer as a primary risk for Path A.
- **Compliance & Terminology:** Clarified engine provenance ("official Flutter sources plus an open patch set"), removed desktop IOSurface reference, and added missing sections to Table of Contents.
- **Consistency & Hedging:** Updated screen profile references to all five sizes (41/42/45/46/49 mm per Apple HIG), clarified CI device wording, hedged Impeller CPU status ("as of late 2026"), expanded Open Question 12, and corrected markdown fence spacing.

### v8.1: November 2026 (Engine scroll signal, check Q7)
- **Added check Q7** (now 34 of 34 checks: 25 dev-loop + 9 engine, Q0–Q7 plus Q2s): a synthetic scroll signal sent to the engine reached Dart (`Listener` → `PointerScrollEvent` → `setState`) and produced a third distinct frame; `FlutterEngineNotifyLowMemoryWarning` was called without a crash. Wording corrected: this is the engine half of Crown support, not Crown hardware or SwiftUI `.digitalCrownRotation`, so mapping the Crown to scroll events remains untested.
- **Fixed:** engine check count (9, not 8), version header, Q7 rows added to the Engine findings and Code verification tables, and a leftover duplicate table fragment under Related Work removed.

### v8.0: November 2026 (Accuracy pass and condensation)
**Corrections**
- **Memory claims (v7.4):** removed "first empirical memory profile on watchOS" and the unsupported "70–80% reduction → ~30 MB" projection, and the meaningless virtual-memory figure. The 146 MB reading is now labelled a Mac debug/JIT process, not a watchOS measurement (it contradicted the document's own "Simulator uses Mac memory" rule). The "patched, retagged, cannot ship" caveat now appears in the status block.
- **Check totals:** verified against `proofs.yml`: 25 dev-loop + 8 engine = 33 is correct. The breakdown is now stated in Validation, with the helper steps (X1, X2, E0, Q2s) explained. Stale "Q0–Q5" references (spike S4, Phase 0.5) updated to Q0–Q6.
- **Power & lifecycle rules (v7.4):** rewritten as *proposed, unmeasured*. Fixed AOD facts (hardware from Series 5, not "watchOS 8+"; `scenePhase` / `isLuminanceReduced` instead of deprecated `WKExtension`; dropped unsourced luminance and "microtask 1 Hz" claims). Backgrounding now uses the `flutter/lifecycle` channel (the embedder API has no "pause isolate"). Damage-rect and zero-copy rules now state the embedder-API constraints. Crown haptics note the built-in detent haptics. Removed the claim that the interceptor flags off-black backgrounds (no such violation existed; it is a lint).
- **Internal conflicts:** one latency target (≤ 300 ms; "33 ms" clarified as per-frame throughput); Open Question 2 no longer contradicts the AOD rule; Phase 3 no longer names Series 4 as a measurement target.
- **Appendix A:** the binary op table is now the single wire spec, with the missing DRAW_RRECT reader and the skipped DRAW_CIRCLE stated explicitly; ILP32 small-string note corrected (10 bytes); the `acquireRead()`-inside-`Canvas` hazard documented; `debugNeedsPaint` debug-only note added to the streamer. Tested code is otherwise unchanged.
- Removed LaTeX markup (`$\to$`).
- **Compliance:** added a short Compliance Principles section (a design-scope statement, not a compliance review). The Metal-overlay route reported for flutter-watchos is recorded as an unassessed risk (Open Question 12) and not adopted; a public-API audit was added to Phase 3.
- **Related Work:** rewritten from flutterwatch.dev, the August 2026 article and the pub.dev pages. The site confirms App Store apps, so that claim stands (sourced to the site); status updated from "closed beta" to the site's current public sign-in model. Added its reported Impeller-on-Metal route (consistent with check Q3: the SDK lacks `MTLCreateSystemDefaultDevice`) as new Open Question 12 and a note in Constraints and Mode 2.
- **Numbers refreshed from the latest CI sheet:** memory is shown as a range across runs (145.6–148.3 MB, fluctuating ±2 MB; the Q7 low-memory call is logged), P6 first-frame time 120–232 ms, bright-glyph counts shown as per-run ranges, and P9 raw/1.0 encode time 0.5–1.9 ms (the previous upper bound, 1.2, was exceeded).

**Condensation (~1,670 → ~930 lines, about 250 of them verbatim tested code)**
- Removed the protobuf `DisplayList` schema, the untested `WatchCanvas` interceptor (A.4) and display-list renderer (A.5), the FFI bridge example and the swiftgen history, all untested or superseded research. Removed the Antigravity agent-strategy and tooling-stack sections and the "present the MVP" marketing steps (author workflow, not architecture).
- Merged the Big Picture section into Vision; merged the performance, MVP and validation text; trimmed duplicated caveats and repeated "unverified" disclaimers.
- Condensed the v1–v7.4 changelog below to one line each.
- ⚠️ If CI extracts code blocks from this file, point it at the Appendix A blocks that remain (A.0, Dart writer, Swift store/reader) and drop the removed ones.

### Earlier versions (condensed)
- **v7.4:** interactive engine loop in a Simulator process (Q6), a memory reading, and a performance-rules section.
- **v7.3:** engine experiment Q0–Q5 (patched official debug engine in a Simulator process) and proposed route.
- **v7.2:** whole dev loop verified (E1); transport ranges corrected over six runs; input-coordinate note.
- **v7.1:** first CI results; `captureNow()` added after the idle-app gap (S1/S7); unused `scale` field removed; transport measured (P9).
- **v7.0:** single primary path (engine rasterizes), display-list material moved to Appendix A; hosts 1a/1b; bandwidth arithmetic corrected (192 KB is pixelRatio 1.0); redundant `TimelineView` removed; text anchor fixed to `.topLeading`; CI validation strategy added.
- **v6.0:** production mode corrected to run the real engine (`dart:ui` needs it); dev mode switched to `RepaintBoundary.toImage` capture; per-op command sizes; triple-buffer mailbox.
- **v5.0 / v4.0:** zero-copy buffer and variable-length text for the display-list path (research).
- **v3.0:** Dart FFI chosen over swiftgen; MVP defined.
- **v2.0:** `watchos_ui`, Digital Crown scrolling and haptics added.
- **v1.0:** initial brainstorm: two-mode architecture, SwiftUI Canvas target, validator concept.
