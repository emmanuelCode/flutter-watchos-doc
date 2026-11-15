# Changelog

## November 2026 — Audit fixes, TBD v5 `engine_gap.py` fix, and spec refocus
- **Fixed `engine_gap.py` & upgraded `Q1`/`Q3` for `--sdk watchos` (verified in CI `6adb57d`, run `43548272531`):** Added TBD v5 `libraries`/`reexported_symbols` and multi-doc YAML Simulator host-kernel `libSystem` sub-doc parsing, eliminating all `libSystem` false positives (`FlutterEmbedder`: `22/673` missing on both `watchsimulator` and `watchos`; `ios_Flutter`: `44/1,077` on `watchos`; `Q4`: `4` `CoreVideo` symbols). Added `--sdk watchos` Clang/Swift header compile probes (`Metal.h`, `CAMetalLayer`, `UIView`, `fork()` fail; `SKMutableTexture`, `SKTexture(data:size:)`, `SpriteView`, `CoreGraphics`, `CoreText`, `WKCrownSequencer`, `chdir` succeed) and `--sdk watchos` C++20 syntax checks in `Q1` (`fml`: `49/55`, `0` unavailable-API errors).
- **Fixed `WatchRender.swift` (`docs/display-list-research.md`):** Added missing `guard need(rawSize + padding)` check in `DRAW_TEXT` to match `WireReader.swift` and prevent `#if DEBUG` assertion crashes on streams truncated mid-padding.
- **Fixed `WatchFrameStreamer` & `WatchFrameView`:** Added `_generation` tracking to prevent stale frames across `stop()`/`start()`, passed `retryIfNeedsPaint: true` when draining `_capturePending`, hoisted `store.latest` outside `Canvas` in `WatchFrameView` for `@Observable` compatibility, and added `.ignoresSafeArea()`.
- **Fixed `engine_host.c`:** Set explicit `device` and `device_kind` (`kFlutterPointerDeviceKindTouch` / `kFlutterPointerDeviceKindMouse`) instead of relying on the legacy `device_kind == 0` fallback.
- **Spec & documentation cleanup:** Corrected SE 3 screen sizes (`162×197 pt` / `184×224 pt`), clarified that `FlutterMetalRendererConfig` is unavailable on public watchOS APIs without an overlay, marked Path B checks (`A1–A4`, `S2`, `S5`, `S6`) as archived research, marked Mode 1b / Phase 6 as non-goals for upstream Flutter, and flagged `watchos_ui` HIG bounds as v0 defaults to loosen for watchOS 10–27.

## November 2026 — On-device hot reload research candidate & hardware probe gate
- Added "On-device hot reload (research candidate, unbuilt)" under Two-Mode Architecture: the two physical-watch blockers (no JIT, TN3135 transport), a Mode 1b / Option C / Option A comparison, upstream dependencies (Dart #61635, `dart2bytecode`, `dynamic_modules`), Shorebird's iOS interpreter as precedent (and why it is not hot reload), and the Mac-side VM-service adapter that an on-device loop would need (hypothesis).
- Updated the "No JIT on device" constraint and the production hot-reload cell to point at that route without claiming it exists.
- Added a "Transfers to a physical watch?" column to the Capability verification summary so Simulator-only evidence is not read as hardware evidence.
- Added Gate 0d (contributor-run physical-watch probe: JIT test, blocked-socket checks, `URLSession.bytes` throughput/latency, `.local` resolution, `WCSession`, decode time, memory), a Metal SDK-annotation check in Phase 0, and Phase 6 (on-device hot reload, depends on upstream).
- Added Open Question 13, a Resolved Decisions row, a note on baking the host address at run time, and references for #61635, the JIT-on-iOS issues and Shorebird.
- No tested code blocks, measured numbers or CI steps were changed.

## November 2026 — Reorganization, Audit Fixes & Platform Gates (supersedes v9.1)
- Renamed `flutter_watchos_architecture_v9_1.md` to `flutter_watchos_architecture.md` (`Status: Draft`) and dropped version numbers from the main spec header.
- Split Appendix A into `docs/display-list-research.md`, `Future Horizon (wearos_ui)` into `docs/wearables-ui-strategy.md`, and version history into `CHANGELOG.md`.
- Raised product device floor to `watchOS 27+` (`SE 3, Series 9+, Ultra 2+`; `arm64`-only per toolchains), closed Open Question 8, and added provisional `40/44 mm` SE 3 presets.
- Updated `WatchFrameStreamer` with `_capturePending` coalescing and `stop()`, plus matching unit tests.
- Marked `ws://` WebSocket transport Simulator-only per Apple TN3135; documented experimental Mode 1b constraints.
- Synced Q7 memory figures to recent CI runs (`140.1–143.0 MB`) and moved opaque check IDs/run sheets to `watchos-proofs/README.md` with a capability traceability table.
- Added provenance disclosure, `"Why Not flutter-watchos?"`, `embedder.h` Path A boundary, illustrative memory floor, and explicit known test limitations.
- Added Platform Gaps & Scope (TN3179, unverified `NSAllowsLocalNetworking` / `ITSWatchOnlyContainer`, Accessibility, Text Input, WidgetKit exclusions) and reordered contributor-gated Gates 0a–0c up front.

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

### v7.4 — November 2026 (Interactive Engine Loop, Memory Footprint & Resource Strategy)
- **Validated (check Q6):** the official Flutter engine running inside a watchOS Simulator process executes a full interactive event loop: touch input (`kAdd` → `kDown` → `kUp`) injected via `FlutterEngineSendPointerEvent` at (99, 121), Dart `GestureDetector` triggered `setState()`, dynamic text re-shaping rendered 'TAP' (1,039 glyph pixels), and Frame 2 was presented with yellow (255, 255, 0) and cyan (0, 255, 255) stripes. Both frames confirmed distinct via `cmp -s`.
- **Measured (check Q6):** Mach task resident memory (RSS) recorded inside the watchOS Simulator process: **146.06 MB** after Frame 1, **146.45 MB** after Frame 2 (~390 KB frame delta). This provides the first empirical memory profile of the engine on watchOS; in a release AOT build (where the Dart compiler, analyzer, and VM service are stripped), memory is expected to drop by 70–80%, bringing it into the ~30 MB hardware budget. *(Corrected in v8.0: this is a Mac debug/JIT process, not an on-device watchOS measurement.)*
- **Added:** *Performance, Battery & Resource Optimization Strategy* section establishing seven architectural rules: OLED true-black `#000000` enforcement, strict demand-driven invalidation (0 FPS idle), Always-On Display (AOD) 1 Hz throttling, software renderer damage-rect blitting, zero-copy buffer sharing, Crown detent quantization, and proactive background suspension handling.
- **Updated:** Code Verification Status and Validation Results tables updated for Q6 (33 checks total).

### v7.3 — November 2026 (Engine Experiment and Route)
- **Added:** a short section, *Engine on watchOS — findings and proposed route*, written so someone else can pick the work up: what was run, what the engine source shows, a six-stage route, policy constraints, and the smallest further tests
- **Measured (checks Q0–Q5):** the official debug engine, retagged and patched, starts in a watchOS Simulator process, runs Dart, shapes text and presents a frame through the software renderer. It does not ship and says nothing about a source build, AOT, a real device, memory or App Store review
- **Found:** a retagged macOS engine cannot load on watchOS without path rewriting, library stubs and symbol overlays; the macOS text layer crashes on a fake `NSFont`; a JIT engine needs its snapshot symbols visible to the host; `fml` classifies watchOS as iOS; 48 of 54 sampled `fml` files compile with C++20
- **Found:** the software present callback delivers RGBA in this engine build. First run decoded it as BGRA and saw the blue stripe as red; the checker now measures the order and requires exactly one order to explain every stripe. It passed on its first run, so RGBA is inferred from the pass — the explicit line was cut off by the sheet's 10-line limit, now 30
- **Changed:** Open Question 9 reworded — existence is a third party's claim we have not verified; open items are the open-source recipe, Dart VM on watchOS, AOT, device cost and App Store acceptance. Spike S4 and the Phase 3 feasibility item updated
- **Withdrawn:** the first engine-base-layer compile result (C++17 where the source needs C++20), the early missing-library and symbol counts, and the gap script's overall symbol totals
- **Validated:** 32 of 32 checks pass in the latest run — the 25 dev-loop checks and Q0–Q5. Q5 is an experiment on a patched, retagged debug engine in the Simulator; it is not a shippable result
- **Unchanged:** every dev-loop "not validated" item

### v7.2 — November 2026 (Whole Loop Verified)
- **Validated (check E1):** the real `WatchFrameStreamer` + `WatchInputInjector` behind a real WebSocket, talking to a watchOS client that renders with the real `WatchFrameStore` + `WatchFrameView` — frame down, tap up, next frame changes, and the live view shows both states. First run, no code changes needed. 25 of 25 checks now pass
- **Status changes:** `captureNow()` Unverified → Tested (S7, E1); `WatchInputInjector` gained E1; the Code Verification Status table has a new row for the whole loop
- **Corrected:** the transport ranges in v7.1 came from four runs, and later runs fell outside some of them. Ranges now cover six runs (for example zlib at 1.0 reaches 1.9 ms/frame; delta at 2.0 reaches 169.8 ms/frame), and the delta decode penalty is stated as ≈ 20–40× slower rather than ≈ 30×. Byte counts did not change in any run
- **Recorded:** a design note on input coordinates (the watch sends logical points of its own screen; the host adds the screen origin), verified at `pixelRatio` 1.0 only
- **Limits stated plainly:** E1's host side ran inside `flutter test`, not a real macOS app; it exchanged two frames, raw (no zlib); hot reload, sustained streaming through the loop, real GPU readback, real Wi-Fi, device memory/speed and the engine on watchOS remain unvalidated

### v7.1 — November 2026 (First CI Results Folded In)
- **Validated:** 22 automated checks passed on a hosted macOS runner with the watchOS 26.5 Simulator — see Validation Results. Code Verification Status, spike statuses, Open Questions 1, 10 and 11, and the Phase 0.5 checklist updated accordingly
- **Found and fixed (check S1):** after `start()` the streamer captures nothing until Flutter next produces a frame, and an idle app produces none, so a client that connects late would see no image. Added `captureNow()`; covered by new check S7
- **Found and fixed (check S3):** `WatchFrameStore.scale` (added in v7.0) had no effect — the view stretches the frame to fill, so output was identical for scale 1 and 2. Removed it, and documented that stretch-to-fill needs a matching aspect ratio
- **Measured (check P9):** full-frame zlib shrinks mostly-static test frames ≈ 180–195×; XOR-delta saves only ≈ 11–12% more and decodes ≈ 30× slower. Dev-mode default is now full-frame zlib. Best-case numbers only: static frames, loopback, debug build, Mac CPU
- **Corrected:** the injector needed no `viewId` in the test environment (the check passed with the snippet as written); my earlier suspicion that the snippet lacked an import was also wrong — it compiles
- **Corrected:** the Sendable concern about `OSAllocatedUnfairLock` holding a raw-pointer struct did not materialise — the spec's Swift compiles for watchOS (check S0)
- **Unchanged and still open:** engine on watchOS, device memory and speed, real Wi-Fi, worst-case frame compression, real GPU readback cost

### v7.0 — November 2026 (Single Primary Path + Simulator-First Validation)
> Entries for v1–v6 are kept unchanged. Where v7 corrects a claim made in an earlier version, the correction is listed here.

- **Restructured (critical):** the document described two incompatible renderers at once — engine rasterization (Mode 1 / Mode 2) and a display-list path where SwiftUI `Canvas` executes opcodes. If the engine rasterizes, the opcode protocol, the five-primitive restriction and the shared-memory buffer are unnecessary; if `Canvas` executes opcodes, the engine's rasterizer is not in use and it is no longer Flutter widgets. All display-list material (Dart FFI bridge, `ZeroCopyCanvas`, `WatchRenderStore`, protobuf `DisplayList`, `WatchCanvas` interceptor, display-list renderer) moved into **Appendix A**, explicitly labelled a separate architecture
- **Added:** Architecture Decision section — Path A (engine rasterizes) is primary, Path B (display list) is research-only; new content must declare which path it belongs to
- **Changed:** `watchos_ui` is now described as a HIG / performance constraint layer under the primary path, not a rasterizer limit; the display-list mapping column is labelled Appendix A only; draw-call budget notes marked as Appendix A signals
- **Added (critical):** Mode 1 split into host 1a (watchOS Simulator over loopback, default) and host 1b (physical watch over Wi-Fi), plus a "What Each Mode Actually Validates" table — Mode 1 does not test the watchOS engine, memory ceiling, or performance, and its measurements must not be cited for those
- **Corrected:** bandwidth arithmetic — v6 quoted ≈ 192 KB per frame while the streamer defaulted to `pixelRatio: 2.0`; 192 KB is the 1.0 figure and 2.0 is ≈ 767 KB (≈ 23 MB/s at 30 fps). Streamer default is now 1.0; `WatchFrameStore` carries the capture scale so the viewer draws at the right size
- **Added:** Known Risks rows for readback cost and dev-vs-prod coverage, a bandwidth table, and six candidate mitigations (all unmeasured); Open Questions 10 and 11
- **Fixed:** `WatchCanvasView` wrapped its `Canvas` in `TimelineView(.animation)` while `frameTick` already invalidated the view on every frame — the timeline was redundant and redrew continuously at display rate, wasting battery. The timeline is removed; the Canvas redraws once per published frame. Rendering Target, mode diagram, invariants, trade-offs, MVP steps and tooling table updated to match. Whether `Canvas` redraws reliably on tick change is flagged for spike S0 (fallback: `.id(tick)`)
- **Fixed:** `SwiftUI.Canvas` `context.draw(Text, at:)` defaults to a `.center` anchor, but Flutter paints text from the top-left — both text-drawing sites now pass `anchor: .topLeading`
- **Fixed:** `paint.color.value` (deprecated) replaced by `paint.color.toARGB32()` in the interceptor
- **Fixed:** `Color(argb:)` was referenced but never defined — implemented in A.0
- **Added:** Validation Strategy — spikes S0–S4 on GitHub Actions macOS runners and the watchOS Simulator, a CI workflow sketch, a Code Verification Status table, and the rule that a code section is not specified until it compiles
- **Added:** Phase 0.5 (CI validation spikes); Phase 1 milestone split into 1a (Simulator, no hardware) and 1b (real watch)
- **Changed:** Antigravity strategy is gated — no agent starts against a spec section until its spike compiles in CI

### v6.0 — November 2026 (Engine Dependency Correction + Safer Render Buffer)
> Entries for v1–v5 are kept unchanged. Where v6 corrects a claim made in an earlier version, the correction is listed here.

- **Fixed (critical):** Production Mode assumed Flutter widgets could run as Dart AOT with the VM "compiled away" and no engine. The Flutter framework depends on `dart:ui`, which the engine implements in C++ (text shaping, `Paragraph`, `Path`, `Canvas`, scene building) — a binary without an engine has nothing to resolve those calls against. Production Mode now runs the real Flutter engine on device through the embedder API; a no-engine build would require a different, non-Flutter widget framework
- **Fixed (critical):** Canvas pipeline hook — `WatchCanvas implements Canvas` does not intercept Flutter's paint pipeline (`PaintingContext` constructs its own canvases, and recorded `Picture`s are opaque to Dart). Development Mode now captures frames from inside the app with `RepaintBoundary.toImage` and injects input through `GestureBinding`, using only public APIs. The display-list interceptor is retained as a research path, with the hook problem recorded as Open Question 7
- **Fixed:** Text — Flutter paints laid-out `Paragraph`s via `drawParagraph`, not strings. The display-list path now requires a custom `RenderObject` plus bundled font metrics; development and production modes avoid the problem because Flutter rasterizes its own text
- **Fixed:** `DRAW_TEXT` layout had no font size or weight — header extended to 28 bytes (`Font Size`, `Flags`)
- **Fixed:** single global `_commandSize = 24` replaced by per-op sizes (`DRAW_RECT` 24, `DRAW_CIRCLE` 20, `DRAW_RRECT` 28)
- **Replaced:** two slabs + `DispatchSemaphore` latch with a three-slab triple-buffer mailbox (FREE / WRITING / READY / READING states, lock-protected, Dart never blocks). The latch could deadlock if the Dart isolate ran on the main thread, and it guaranteed only that Swift picked up the pointer — not that it finished reading before Dart reused the slab
- **Replaced:** `@Published` raw pointers in `WatchRenderStore` with a single published frame counter; the store now owns the slabs and the mailbox state machine, and `watch_render_frame` is replaced by `watch_slab_base` / `watch_acquire_write_slab` / `watch_submit_slab` / `watch_abandon_slab`
- **Fixed:** Dart writer used `elementAt(n).cast<T>().value`, which allocates a `Pointer` object per field — now typed-data views (`ByteData`) created once per slab, `Endian.host`, explicit padding writes (malloc'd memory is not zeroed and reused slabs are dirty), overflow frames abandoned instead of shown
- **Fixed:** Swift reader — added bounds checks against `byteCount`, `loadUnaligned`, unknown-op bail-out, and a `DEBUG` end-of-stream assert
- **Corrected:** "true zero-allocation" → low-allocation (the text path still creates a `String`; `Text` / `Color` values allocate). The "< 1 µs", "~3–5× smaller", and "microsecond latency" figures are now labelled as expectations, not measurements
- **Corrected:** ARM64 alignment rationale — Swift's `load(as:)` requires alignment (undefined behaviour otherwise), but ARM64 hardware tolerates many unaligned accesses, so "hard bus error crash" was overstated
- **Corrected:** "No Dart VM at runtime — too heavy (~80 MB)" → watchOS prohibits JIT on device; AOT output still carries a Dart runtime
- **Corrected:** "watchOS 10 removed hierarchical navigation" — `NavigationStack` still exists and watchOS 10 added vertical `TabView` and `NavigationSplitView`; excluding the hierarchical router is now documented as a scope decision
- **Corrected:** Digital Crown input uses SwiftUI `.digitalCrownRotation`, not `WKCrownDelegate`
- **Corrected:** Resolved Design Decisions listed fonts as resolved while Open Question 4 said text parity was unproven — each mode's text handling is now stated explicitly
- **Changed:** Debug Interceptor validates the render tree (sizes, touch targets, font sizes) instead of the draw stream
- **Changed:** HIG numeric limits and section references marked provisional until verified against the current HIG
- **Changed:** Phase plan — Phase 3 is now Engine on Device (absorbs old Phase 4 AOT work); Phase 4 is Display-List / Zero-Copy Research (old Phase 3 FFI work)
- **Changed:** MVP re-scoped around frame streaming; "nobody has done before" framing removed; 5–7 week estimate withdrawn until Open Question 1 is answered
- **Changed:** Open Question 1 now asks about headless frame capture; Questions 3 and 4 marked as display-list-only
- **Added:** The Frame Streamer section — `WatchFrameStreamer`, `WatchInputInjector`, and a known-risks table
- **Added:** Pixel-stream renderer on the watch side (SwiftUI Canvas draws the latest received frame)
- **Added:** Open Questions 7 (paint hook), 8 (device floor / `arm64_32` ABI), 9 (engine on watchOS)
- **Added:** Related Work — flutter-watchos and a comparison table
- **Fixed:** References — "custom embedder docs" pointed to add-to-app docs; `embedder.h` path updated for the monorepo; removed unused `swift2objc`; added flutter-watchos links
- **Removed:** "novel" claim from the Big Picture section

### v5.0 — May 2026 (True Zero-Allocation Swift + Variable-Length Wire Protocol)
- **Fixed:** Swift FFI function was allocating a `[RectCommand]` array and calling `.append()` on every frame — reintroduced heap allocation and GC churn at 30–60 fps, defeating the zero-copy promise
- **Fixed:** `DispatchQueue.main.async` alone was insufficient — timing gap allowed Dart to flip the buffer before the main thread latched the pointer; fixed with `DispatchSemaphore` latch that blocks the FFI call until the pointer is safely held
- **Replaced:** `WatchRenderStore` intermediate struct array with raw pointer store (`UnsafeRawPointer` + `commandCount`) — zero allocations, zero intermediate objects
- **Moved:** Full command parsing loop from the FFI function into the `Canvas` closure — bytes are now read directly during the native SwiftUI draw pass, the only place they need to be
- **Added:** `DRAW_TEXT` variable-length command — length-prefixed UTF-8 wire layout with 4-byte alignment padding
- **Added:** Dart `drawText()` implementation — packs header + raw UTF-8 bytes + padding into the active slab
- **Added:** Swift `DRAW_TEXT` parser — uses `UnsafeBufferPointer` to bind raw bytes as a `String` without copying; calculates variable offset jump including padding
- **Added:** ARM64 alignment explanation — unaligned `Float` loads on S-series chips cause access traps or bus error crashes; 4-byte padding on all variable commands is non-negotiable
- **Updated:** Zero-copy vs. serialization comparison table — Swift allocations row now correctly shows "None — raw pointer passed directly to Canvas"; added ARM64 alignment row
- **Updated:** Trade-offs — replaced variable-length placeholder with full length-prefix + alignment padding specification; added semaphore latch cost note

### v4.0 — May 2026 (Zero-Copy Shared Memory Buffer)
- **Added:** Zero-Copy Shared Memory Buffer section — production render path for Phase 3+ FFI pipeline
- **Added:** Double-buffer strategy — two persistent `malloc` slabs, atomic frame flip, zero mutex, zero blocking; identical pattern to GPU double-buffering
- **Added:** `ZeroCopyCanvas` Dart implementation — writes primitives directly to unmanaged memory outside the GC heap; `commitFrame()` performs atomic slab flip
- **Added:** `watch_render_frame` Swift FFI receiver — parses raw buffer into `WatchRenderStore` and publishes to SwiftUI via `DispatchQueue.main.async`
- **Added:** `WatchCanvasView` SwiftUI component — `GraphicsContext` stays inside its closure; never passed as a raw pointer across FFI
- **Fixed:** Swift `DRAW_RECT` height offset corrected from `+14` to `+16` — previous value caused silent memory misalignment and garbage geometry/color reads
- **Fixed:** `GraphicsContext` FFI passing removed — SwiftUI value type cannot safely cross FFI boundary; replaced with `WatchRenderStore` publish pattern
- **Added:** Zero-copy vs. serialization comparison table — GC pressure, Swift allocations, FFI handoff cost, thread safety
- **Updated:** Core Constraints — memory limit row clarified from "~30 MB hard limit" to "~30 MB conservative target, varies by SKU, validate with Instruments"
- **Updated:** Phase 3 build tasks — added `ZeroCopyCanvas` double-buffer, `WatchRenderStore` receiver, and per-SKU Instruments validation tasks
- **Updated:** Antigravity agent table — added Agent 8 for `ZeroCopyCanvas` + `WatchRenderStore` (Phase 3)
- **Updated:** Tooling stack — added Zero-Copy Shared Memory Buffer as a named production-path component

### v3.0 — May 2026 (Dart FFI + MVP revision)
- **Removed:** swiftgen — removed from architecture entirely; ~33 downloads, 2-month-old unstable API, adds unnecessary abstraction over Dart FFI
- **Added:** Dart FFI as primary Dart ↔ Swift interop — direct `@_cdecl` Swift bridge, microsecond latency, production stable core SDK feature
- **Added:** swiftgen vs Dart FFI comparison table — stability, latency, adoption, maintenance risk
- **Added:** Dart FFI bridge code examples — `@_cdecl` Swift pattern + `DynamicLibrary.lookupFunction` Dart pattern
- **Added:** MVP section — proof of concept strategy targeting Flutter team and community attention
- **Added:** MVP scope — `WatchText` + `WatchButton` only, WebSocket dev mode, no desktop preview, no AOT
- **Added:** MVP timeline estimate — 5–7 weeks
- **Added:** MVP presentation strategy — GitHub repo, demo video, Flutter issue, community post, article
- **Added:** Desktop preview viewport explicitly excluded from MVP with rationale
- **Updated:** Resolved design decisions — Dart FFI entry replaces swiftgen entry
- **Updated:** Agent 6 reassigned from swiftgen to Dart FFI bridge
- **Updated:** Production mode diagram — draw commands now Dart FFI → Swift (in-process)
- **Updated:** Tooling stack — swiftgen removed, Dart FFI added
- **Added:** "What This Project Is" big picture section

### v2.0 — May 2026 (watchos_ui + haptics revision)
- **Added:** `watchos_ui` package concept — bespoke watch-first widget catalog replacing Material/Cupertino
- **Added:** `WatchApp` root widget — OLED black background, SF Compact typography, HIG-compliant gestures
- **Added:** Digital Crown `WatchScrollPhysics` — Crown rotational delta drives `WatchListScaffold`
- **Added:** `HAPTIC_TRIGGER` to `InputEvent` protobuf — Taptic Engine round-trip from Dart state changes
- **Added:** Full Protobuf `DrawCommand` schema with all op types and fields
- **Added:** Phase 0 — `watchos_ui` specification moved before Phase 1
- **Added:** Resolved design decisions table
- **Added:** watchOS 10+ navigation paradigm note — hierarchical router excluded from v0
- **Fixed:** `WatchHierarchicalRouter` description — watchOS 10 removed hierarchical navigation

### v1.0 — May 2026 (initial brainstorm)
- Initial architecture defined across brainstorming session
- Two-mode architecture established — dev WebSocket / prod AOT
- Rendering target selected: SwiftUI Canvas + TimelineView
- Display list protocol designed — draw command set v0
- Canvas Interceptor pattern defined (Dart side)
- Debug Interceptor / constraint validator designed
- swiftgen FFI interop layer identified (replaced by Dart FFI in v3.0)
- SwiftUI renderer skeleton written (Swift side)
- Event round-trip flow defined — tap, swipe, crown
- Five build phases outlined
- Antigravity 2.0 identified as implementation orchestration tool
