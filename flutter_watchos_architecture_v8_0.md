# Flutter for watchOS
### Architecture & MVP Strategy
> A Flutter platform embedder targeting standalone Apple Watch

**Version:** v8.0 · **Last updated:** November 2026
**Status:** Draft design, partially validated. In CI (macOS runner, watchOS Simulator) the development loop works end to end, and a *patched* official Flutter engine runs Dart, renders frames and handles touch inside a Simulator process. **Nothing has run on a real watch, and no shippable engine build exists.** See [Validation](#validation).
**Minimum target:** watchOS 10+ (device floor under review, see Open Question 8)

---

## Contents
1. [Vision](#vision) · 2. [Constraints](#core-constraints) · 3. [Compliance](#compliance-principles) · 4. [Architecture decision](#architecture-decision) · 5. [`watchos_ui`](#the-watchos_ui-package) · 6. [Two modes](#two-mode-architecture) · 7. [Frame streamer](#the-frame-streamer-dart-side) · 8. [Debug interceptor](#the-debug-interceptor) · 9. [Watch renderer](#the-swiftui-renderer-watch-side) · 10. [Events & haptics](#events--haptics) · 11. [Power & lifecycle](#power--lifecycle-rules-proposed) · 12. [MVP](#mvp) · 13. [Validation](#validation) · 14. [Engine on watchOS](#engine-on-watchos-findings-and-proposed-route) · 15. [Open questions](#open-questions) · 16. [Phases](#build-phases) · 17. [Related work](#related-work) · [Appendix A](#appendix-a-display-list-research-path) · [Changelog](#changelog)

---

## Vision

Let Flutter developers write widgets in Dart, exactly as they do today, and run them on a standalone Apple Watch with no iPhone. Flutter's own engine rasterizes every frame; SwiftUI `Canvas` is the surface that puts those pixels on the watch.

Rather than forcing Material/Cupertino onto a 40 mm screen, a bespoke `watchos_ui` package encodes Apple's Human Interface Guidelines (HIG) by design: correct layout math, performance and native-feeling interaction from the start.

The scope is comparable to `flutter_pi` (the community embedder for Raspberry Pi): a new embedder for a constrained, non-phone target.

---

## Core Constraints

| Constraint | Detail |
|---|---|
| No Metal directly | `MTKView` is unavailable and the watchOS SDK does not export `MTLCreateSystemDefaultDevice` (check Q3), so GPU access is normally indirect (SwiftUI Canvas / SpriteKit). flutter-watchos reports reaching Metal through an SDK overlay; this design does not use that route (Open Question 12) |
| No UIKit | WatchKit + SwiftUI only |
| Memory | ~30 MB is a conservative working target. It varies by watch generation; validate per device with Instruments |
| No JIT on device | On-device Dart must be AOT-compiled, so there is no on-device hot reload. AOT output still carries a Dart runtime (GC etc.) |
| No dynamic code | Apple prohibits downloading and executing code at runtime (App Review Guideline 2.5.2) |
| Background limits | The OS suspends background work aggressively; a WebSocket listener must stay in a foreground session |
| Screen sizes | 41 mm → 176×215 pt · 45 mm → 198×242 pt · 49 mm Ultra → 205×251 pt |
| Pointer width (unverified) | Older watches are believed to use the `arm64_32` (ILP32) ABI. Verify Dart AOT / engine support before fixing the device floor |

---

## Compliance Principles

This document is a design, not a compliance review. It is built around Apple-supported mechanisms: public APIs only, pixels presented through SwiftUI, AOT builds with no downloaded code (see App Review Guidelines 2.5.1 and 2.5.2), and an engine build from official Flutter sources. Stubbed or patched binaries, such as those in checks Q4–Q6, are research artifacts and never ship, and the Metal-overlay route reported for flutter-watchos is not used (Open Question 12). Whoever implements this, or the Flutter team, should verify these points against Apple's current guidelines and, where unclear, ask Apple before relying on them.

---

## Architecture Decision

Two incompatible answers to "who draws the pixels?" cannot share one pipeline, so this document picks one.

| | **Path A: engine rasterizes (primary)** | **Path B: display list (Appendix A, research only)** |
|---|---|---|
| Who rasterizes | Flutter engine (software / custom-compositor path) | SwiftUI `Canvas` executes drawing opcodes |
| What crosses the boundary | Dev: rendered frames over WebSocket · Prod: engine pixels, in-process | Draw commands (binary slabs in shared memory) |
| Role of `watchos_ui` | HIG / performance constraint layer; ordinary Flutter widgets | Hard requirement; only widgets that emit opcodes render |
| Needs a paint hook | No | Yes (Open Question 7) |
| Needs the Flutter engine | Yes | No, but then it is not Flutter widgets |
| Phases | 1–3 | 4 (optional) |

**Decision: Path A.** `watchos_ui` restricts widgets for HIG and performance reasons, not because the rasterizer is limited; the engine rasterizes whatever Flutter paints. Nothing in Phases 1–3 depends on Appendix A. New sections must say which path they belong to.

---

## The `watchos_ui` Package

> ⚠️ Must be specified before implementation: every other layer depends on its widget surface.

Under Path A, `watchos_ui` is a constraint layer (enforced by the validator and lints), not a renderer limit. `WatchText` and `WatchButton` are ordinary widgets composed from real Flutter widgets.

**Root: `WatchApp`** (replaces `MaterialApp`): pure black `#000000` background, SF Compact default typography, no mobile-only gestures (long-press menus, Material ripple), page-based navigation.

**Layout:** `Row`, `Column`, `Stack`, `Flex`, `Padding`, `SizedBox` are used as-is (spatial math only, no paint).

**Visual primitives**

| Widget | Constraint enforced | HIG rule |
|---|---|---|
| `WatchButton` | Minimum 44×44 pt touch target | Touch targets |
| `WatchText` | Font 14–34 pt, SF Compact only, no inline spans | Typography |
| `WatchProgressRing` | Standard activity-ring proportions | Progress |
| `WatchDivider` | 1 pt, system gray | Layout |
| `WatchImage` | Must reference a pre-bundled asset | Memory |

> ⚠️ The numeric limits (44×44 pt, 14–34 pt) and HIG section names are provisional until checked against the current HIG.

**Navigation (watchOS 10+):** `WatchPageScaffold` (horizontal pages, like Workout/Activity) and `WatchListScaffold` (vertical list driven by the Digital Crown). A push/pop `WatchHierarchicalRouter` is excluded from v0 as a scope decision; `NavigationStack` still exists on watchOS 10.

**Digital Crown:** a `WatchScrollPhysics` consumes Crown rotation deltas (from SwiftUI `.digitalCrownRotation`) to scroll `WatchListScaffold`.

---

## Two-Mode Architecture

> `dart:ui` is implemented by the Flutter **engine**, not by Dart. Both modes therefore keep a real engine in the loop: on the developer's Mac in development, on the watch in production.

### Mode 1: Development

The real Flutter app runs on the Mac (stock Dart VM, stock hot reload) and handles layout, state and rasterization. A `WatchHost` wrapper captures each rendered frame with public Flutter APIs and streams it to the watch over WebSocket. Input flows back and is injected through `GestureBinding`.

```
[ Mac ]  Flutter app (stock Dart VM)
           WatchHost: RepaintBoundary sized to the target profile
         → WatchFrameStreamer (captures a frame after each produced frame)
         → Debug Interceptor (validates the render tree; clean frames only)
         → WebSocket server
                ↓
[ Watch ] WebSocket listener (foreground) → frame decoder → SwiftUI Canvas
          ↑ InputEvent → WebSocket → WatchInputInjector → GestureBinding → setState() → new frame
```

Two hosts, same Mac-side code:
- **1a: watchOS Simulator (default).** Loopback connection, no hardware, runs in CI.
- **1b: physical watch over Wi-Fi.** Adds real latency, session suspension and the real display. This is the second milestone.

Dev loop: save in VS Code → Dart VM hot reloads → Flutter produces a frame → interceptor validates → frame pushed to the watch → tap returns → inject → `setState` → repeat. Target: **≤ 300 ms from save or tap to updated pixels** (unmeasured).

### Mode 2: Production

Dart AOT snapshot + a **Flutter engine built for watchOS** + a Swift host that drives the engine through the embedder API (`embedder.h`), the same mechanism `flutter_pi` uses. The engine rasterizes through a software or custom-compositor path; the host hands pixels to SwiftUI. No server, no network.

```
Build:   Dart + watchos_ui → gen_snapshot (AOT) → linked with the watchOS engine,
         Swift host (FlutterEngineRun, present callback, input forwarding), assets → .watchapp
Runtime: Swift host starts engine with AOT snapshot → engine renders → present callback (pixels)
         → SwiftUI Canvas / Image · SwiftUI input → FlutterEngineSendPointerEvent
```

**All unverified:** an engine can be built for watchOS · a usable renderer exists there (software/compositor; the Metal-overlay route is not adopted, see Open Question 12) · engine + framework + app fit the memory budget · frame times are acceptable on hardware · App Review accepts it.

| | Development | Production |
|---|---|---|
| Engine | On the Mac (stock Dart VM) | On the watch (AOT, embedder API) |
| Output to watch | Rendered frames over WebSocket | Present callback → SwiftUI, in-process |
| Hot reload | ✅ (watch driven from the Mac) | ❌ (no JIT on device) |
| Server / Mac needed | Yes | No |
| App Store | ❌ | ✅ (to be validated) |

### What each mode validates

| Question | 1a Simulator | 1b Watch (Wi-Fi) | Mode 2 on device |
|---|---|---|---|
| Dart logic and layout work? | ✅ | ✅ | ✅ |
| Swift renderer compiles and draws? | ✅ | ✅ | ✅ |
| Engine runs on watchOS? | ❌ | ❌ | ✅ |
| Fits watch memory? | ❌ uses Mac memory | ⚠️ viewer only | ✅ |
| Real frame times / battery? | ❌ | ⚠️ viewer only | ✅ |
| Real network behaviour? | ❌ loopback | ✅ | n/a |
| Pixel parity (fonts, colour)? | ❌ rendered on Mac | ❌ rendered on Mac | ✅ |

> ⚠️ Mode 1 is a layout-and-logic loop plus a remote display. Its measurements must not be cited as evidence for production memory, speed or visual parity.

---

## The Frame Streamer (Dart Side)

Captures each produced frame from inside the running app using only public APIs (no engine changes, no `Canvas` subclassing) and injects input through the gesture system.

```dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Captures frames from a RepaintBoundary and hands raw RGBA to a sink.
class WatchFrameStreamer {
  WatchFrameStreamer({
    required this.boundaryKey,
    required this.sink,
    this.pixelRatio = 1.0, // 1.0 keeps dev bandwidth low; 2.0 is 4x the bytes (see Known Risks)
  });

  final GlobalKey boundaryKey;
  final void Function(Uint8List rgba, int width, int height, int frameId) sink;
  final double pixelRatio;

  bool _captureInFlight = false;
  int _frameId = 0;

  void start() {
    // Persistent callbacks fire on every produced frame — natural
    // "something changed" detection.
    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
    });
  }

  /// Call when a watch (re)connects. An idle app produces no frames, so without this a
  /// newly connected watch would show nothing until something on screen changes.
  Future<void> captureNow() => _capture();

  Future<void> _capture() async {
    if (_captureInFlight) return; // drop frames rather than queue them
    final boundary = boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null || boundary.debugNeedsPaint) return;

    _captureInFlight = true;
    try {
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data != null) {
        sink(data.buffer.asUint8List(), image.width, image.height, _frameId++);
      }
      image.dispose();
    } finally {
      _captureInFlight = false;
    }
  }
}
```

```dart
import 'package:flutter/gestures.dart';

/// Replays watch input as Flutter pointer events.
class WatchInputInjector {
  int _pointer = 1;

  void tap(Offset logicalPosition) {
    final binding = GestureBinding.instance;
    final id = _pointer++;
    binding.handlePointerEvent(PointerDownEvent(pointer: id, position: logicalPosition));
    binding.handlePointerEvent(PointerUpEvent(pointer: id, position: logicalPosition));
  }

  // Crown rotation → scroll input. Mapping defined in Phase 0.
}
```

Notes:
- `debugNeedsPaint` is a debug-only getter (it throws in profile/release), which is fine for a debug dev loop.
- After `start()` nothing is captured until Flutter next produces a frame, and an idle app produces none (found by check S1). `captureNow()` fixes this: call it on connect or resync (checks S7, E1).
- The watch sends taps in logical points of its own screen; the host adds the app's screen origin before injecting. Verified at `pixelRatio` 1.0 only (E1); at 2.0 the watch must divide frame-pixel coordinates by the ratio (untested).

### Known risks

| Risk | Notes |
|---|---|
| Readback cost | `toImage` + `toByteData` is an async GPU→CPU readback plus a full-frame copy, likely the frame-rate ceiling. Headless capture works (P2, S1), but those timings come from the test renderer, which has no real GPU |
| Bandwidth | Raw RGBA ≈ 192 KB/frame at pixelRatio 1.0, ≈ 767 KB at 2.0 (table below). Measured zlib: ≈ 1 KB / 3.9 KB on mostly-static frames; worst-case content is unmeasured |
| Dev ≠ prod | Mode 1 does not exercise the watchOS engine, memory or performance |
| Input latency | A Wi-Fi round trip feels laggy: acceptable for development, not for end users |
| Headless host | Proven under `flutter test` on a macOS runner; a hidden desktop window or `flutter-tester` process is untested (Open Question 1) |
| Rendering mismatch | Pixels rendered on the Mac may differ on-device (fonts, scaling, colour) |

**Bandwidth** (uncompressed RGBA, 45 mm screen 198×242 pt):

| Pixel ratio | Frame size | At 30 fps |
|---|---|---|
| 1.0 (198×242 px) | 191,664 B ≈ 192 KB | ≈ 5.7 MB/s |
| 2.0 (396×484 px) | 766,656 B ≈ 767 KB | ≈ 23 MB/s |

Candidate mitigations: default to pixelRatio 1.0 · send only on change (already true) · full-frame zlib (measured, below) · cap capture at ~15 fps · long term, avoid GPU readback with Mode 2's software present callback. Dirty-rect/XOR-delta diffs were measured and rejected for now (≈ 11–12 % smaller than zlib, ≈ 20–40× slower to decode in a debug build).

Because Flutter rasterizes its own text in this mode, there is no Dart-vs-Core-Text parity problem (that applies only to Appendix A).

---

## The Debug Interceptor

Sits between the frame source and the WebSocket sender. Validates each frame against a `WatchConstraintProfile` by inspecting the **render tree** (sizes, touch targets, font sizes). Critical violations block transmission.

**Profile fields:** `screenWidth`, `screenHeight`, `maxPayloadBytes`, `minTouchTarget` (44 pt), `minFontSize` (14 pt), `maxFontSize` (34 pt), `crownExclusionZone`, with presets for 41, 45 and 49 mm. (`maxDrawCallsPerFrame` applies only to Appendix A; under Path A use render-object count, layer count and capture time.) Numeric limits are provisional until checked against the HIG.

| Category | Violation | Severity | Meaning |
|---|---|---|---|
| Layout | `horizontalOverflow` / `verticalOverflow` | 🔴 Critical | Wider / taller than the screen |
| Layout | `touchTargetTooSmall` | 🔴 Critical | Interactive area < 44×44 pt |
| Layout | `safeAreaViolation` | 🔴 Critical | Content outside the safe display area |
| Typography | `fontTooSmall` / `fontTooLarge` | 🟡 Warning | < 14 pt / > 34 pt |
| Typography | `textClipped` | 🟡 Warning | Text truncated or overflowing |
| Performance | `payloadTooBig` | 🟡 Warning | Frame exceeds the bandwidth budget |
| HIG | `crownZoneViolation` | 🟡 Warning | Interactive content too close to the Crown edge |

Off-black backgrounds are caught by a lint, not by the interceptor.

---

## The SwiftUI Renderer (Watch Side)

Draws the latest received frame. No `TimelineView`: each published frame invalidates the view.

```swift
import SwiftUI

// Latest frame received over the WebSocket, already decoded to a CGImage
// (wrap the RGBA bytes in a CGDataProvider and build the CGImage from it).
final class WatchFrameStore: ObservableObject {
    @Published var latest: CGImage? = nil
}

struct WatchFrameView: View {
    @ObservedObject var store: WatchFrameStore

    var body: some View {
        // No TimelineView needed — each published frame triggers a redraw.
        Canvas { context, size in
            guard let frame = store.latest else { return }
            context.draw(Image(decorative: frame, scale: 1),
                         in: CGRect(origin: .zero, size: size))
        }
    }
}
```

The frame is stretched to fill the view (checks S3, S4), so it fits whatever `pixelRatio` was captured. That is only correct when the captured boundary has the same aspect ratio as the view: size the boundary to the watch's logical screen. Redraw-on-publish was verified with an off-screen `ImageRenderer`, not yet on a live screen.

> Avoid `TimelineView(.animation)` here: it ticks at display rate even when nothing changed, a real battery cost. Add a `TimelineView` only for continuous local animation.

---

## Events & Haptics

```
Crown:  SwiftUI .digitalCrownRotation → InputEvent{CROWN, delta}
        → WebSocket (dev) or engine scroll/pointer event (prod)
        → Dart WatchScrollPhysics → new list offset (+ haptic tick if a threshold is crossed)
        → new frame → Canvas repaints → InputEvent{HAPTIC_TRIGGER} → WKInterfaceDevice.current().play(.click)

Tap:    InputEvent{TAP, x, y} → (dev) WatchInputInjector → GestureBinding → hit-test
        → GestureDetector → setState() → new frame → pushed to the watch
```

---

## Power & Lifecycle Rules (proposed)

Rules for Mode 2 (and the viewer in Mode 1). **None is implemented or measured yet.**

| # | Rule | Notes |
|---|---|---|
| 1 | **True-black background** (`#000000`) | Black OLED pixels draw essentially no power. `WatchApp` sets it; a lint flags off-black roots |
| 2 | **Frames only on invalidation** | No free-running display link or `TimelineView(.animation)`. An idle app produces no frames (verified for Mode 1, check S7) |
| 3 | **Always-On Display** | AOD hardware starts at Series 5; Series 4 has none. Read SwiftUI `scenePhase` and `isLuminanceReduced`; when luminance is reduced, hide or pause sub-second elements (seconds hands, spinners). The system limits AOD update rate itself. Exact app behaviour in AOD needs device testing |
| 4 | **Damage-rect copy** | The embedder's software present callback delivers the whole surface, so the saving would be in copying only the changed region into the display buffer. Unmeasured |
| 5 | **Avoid extra pixel copies** | With the plain present callback the buffer belongs to the engine, so one copy is unavoidable. A custom-compositor software backing store would let the host own the buffer (e.g. a `CVPixelBuffer`-backed one). Unmeasured |
| 6 | **Crown haptics** | `.digitalCrownRotation` can play detent haptics itself (`isHapticFeedbackEnabled`). Add manual Taptic calls only for Dart-driven events, and avoid doubling up. Detent spacing is a tunable |
| 7 | **Prompt backgrounding** | Forward lifecycle to the engine (`AppLifecycleState` over the `flutter/lifecycle` channel via `FlutterEngineSendPlatformMessage`) so the framework stops scheduling frames, and suspend quickly to avoid watchdog termination |

---

## MVP

> **Goal:** a measured demonstration of a Flutter-authored `WatchText` and `WatchButton` on a watch, driven by Dart with hot reload, published with honest numbers (including unfavourable ones). It is not a framework release. Other toolchains now target this platform (see [Related Work](#related-work)), so the contribution is the *measured* pixel-stream approach and its trade-offs.

**Build:**
1. Prove headless frame capture on the dev machine (Open Question 1)
2. Implement `WatchText` and `WatchButton` on the real framework
3. Dart WebSocket server: `WatchFrameStreamer` sends a frame per produced frame
4. watchOS Xcode project: SwiftUI Canvas + WebSocket listener + frame decoder
5. Tap round trip: watch sends `TAP`, `WatchInputInjector` replays it, `setState`, button changes colour
6. Verify hot reload and record measured latency (target ≤ 300 ms)
7. Record a demo: Mac and watch side by side, hot reload visible

Steps 1–6 can be CI-verified in the Simulator (host 1a). Step 7 on a real watch is a separate hardware milestone (1b).

**Excluded from the MVP:** desktop preview viewport (Phase 2), full `watchos_ui` catalog, constraint validator, FFI and display-list mode (Phase 4), production engine build (Phase 3), App Store submission (Phase 5).

**Timeline:** not estimated until Open Question 1 is answered on a real desktop host.

---

## Resolved Design Decisions

| Question | Decision |
|---|---|
| Layout / state | Run entirely Dart-side (on the Mac in dev, on the watch in prod). In dev only rendered output crosses the wire |
| Animations | Run inside Flutter; frames are streamed in dev |
| Fonts | Flutter rasterizes its own text in both modes, so no cross-renderer parity is needed (parity is open only for Appendix A, Open Question 4) |
| Images | Pre-bundled in the `.watchapp` at build time |
| Navigation | `WatchPageScaffold` + `WatchListScaffold` only (scope decision) |
| Production runtime | Real Flutter engine on device via the embedder API |
| Dev loop host | Simulator over loopback first, physical watch second |
| Frame rate | 30 fps target (~33 ms per frame throughput): a hypothesis, to be measured |
| Frame encoding (dev) | Full-frame zlib; XOR-delta rejected for now. Provisional until worst-case content is measured |
| Late-joining client | Call `captureNow()` on connect / resync |
| Dart ↔ Swift interop | Dart FFI with `@_cdecl`, for Appendix A only (not needed for Path A rendering) |

---

## Validation

Checks run in CI on GitHub-hosted macOS runners with the watchOS Simulator, with no owned hardware needed (free for public repositories at the time of writing; verify current terms). The runnable proofs live in `watchos-proofs/`, and the code blocks in this document are extracted and tested automatically. **A code section counts as specified only once its snippet compiles in CI.**

Latest run: macOS runner, Xcode 26.6, watchOS 26.5 Simulator, Flutter 3.47, Dart 3.13. **All 33 checks pass:** 25 dev-loop checks (F0, P0–P6, P9, X1–X2, S0–S7, A1–A4, E0–E1) and 8 engine checks (Q0–Q6 plus Q2s). X1/X2 extract the spec's code, E0 is the end-to-end setup, and Q2s boots a watch simulator. Status values progress Unverified → Compiles → Tested → Measured; "Tested" means tested in the Simulator, not on a watch.

### Spikes

| ID | Spike | Status |
|---|---|---|
| S0 | Swift compile + unit tests of the watch-side renderer | ✅ checks P0, P4, P5, S0, S2–S6 |
| S1 | `WatchFrameStreamer` + `WatchInputInjector` under `flutter test`, no window | ✅ checks P2, P3, S1 |
| S2 | Loopback WebSocket: Dart server → Simulator client | ✅ checks P6, P9, E1 |
| S3 | Appendix A wire format, mailbox, symbol lookup | ✅ with a stand-in writer (A1–A4); real `ZeroCopyCanvas` untested |
| S4 | Engine on watchOS feasibility | 🟨 patched debug engine runs in a Simulator process (Q0–Q6); source build, AOT and device not started |

(Spike IDs S0–S4 are planning milestones; the check IDs S0–S7 are individual steps of `proofs.yml`.)

### Code verification status

| Snippet | Status | Checks |
|---|---|---|
| `WatchFrameStreamer`, `captureNow()` | Tested: captures frames; idle app sends nothing by itself; `captureNow()` pushes the current frame | P2, S1, S7, E1 |
| `WatchInputInjector` | Tested: tap reaches a `GestureDetector` and the next frame changes (no `viewId` needed in the test environment) | P3, S1, E1 |
| `WatchFrameStore`, `WatchFrameView` | Tested: stretch-to-fill; redraws on publish (off-screen renderer) | S0, S3, S4 |
| Whole dev loop (streamer + injector ↔ WebSocket ↔ store/view) | Tested in the Simulator; host side ran inside `flutter test`, not a desktop app | E1 |
| Engine interactive loop (`FlutterEngineSendPointerEvent` → `setState` → frame 2) | Tested on a patched debug engine in a Simulator process | Q6 |
| `Color(argb:)` | Tested | S2 |
| `WatchRenderStore`, `@_cdecl` slab API, `WatchCanvasView` (DRAW_RECT) | Tested with Dart-style bytes | S0, S5, S6 |
| Mailbox state machine | Tested (stand-in and real store) | A2, S5 |
| `@_cdecl` symbol lookup | Tested via `dlsym`; a Dart FFI call on watchOS is unverified | A4 |
| `WatchCanvasView` DRAW_TEXT, `ZeroCopyCanvas` Dart writer | Unverified | A3 (stand-in only) |

### Results

| Checks | What they showed |
|---|---|
| F0, P0, P1 | A hosted runner has a bootable watchOS Simulator; the Swift package builds and runs XCTest there |
| P2 | Headless capture works: `RepaintBoundary.toImage` → raw RGBA, byte counts exactly as computed |
| P3, S1 | A tap injected via `GestureBinding` reaches a `GestureDetector` and changes the next frame |
| P4, P5 | RGBA → `CGImage` → SwiftUI `Canvas` draws the right pixels |
| P6 | Dart WebSocket server → watchOS client over loopback: a 192 KB frame down, a tap up (first frame incl. handshake: 158–232 ms across runs) |
| S0, S2–S6 | The spec's Swift compiles for watchOS; views stretch, redraw on publish, and the slab API draws Dart-written bytes |
| S7 | An idle app produces no frames; `captureNow()` pushes exactly the current one |
| A1–A4 | Text at `.topLeading` renders from the top-left; mailbox logic; Dart-written bytes parse in Swift; `@_cdecl` symbol found by `dlsym` |
| E1 | **Whole dev loop, no stand-ins:** on connect `captureNow()` sent frame 0 (view showed red); a tap at the watch-screen centre (99, 121) was replayed; frame 1 arrived (view showed green) |
| Q0–Q6 | Engine experiment, see [Engine on watchOS](#engine-on-watchos-findings-and-proposed-route) |

**Sustained transport (P9):** 100 frames per configuration, ranges across CI runs (latest included), loopback, debug build.

| Pixel ratio | Encoding | Bytes/frame | ms/frame | Decode ms/frame |
|---|---|---|---|---|
| 1.0 | raw | 191,668 | 0.5–1.9 | 0.0–0.1 |
| 1.0 | zlib | 1,047 | 0.9–1.9 | 0.8–1.7 |
| 1.0 | XOR-delta + zlib | 922 | 24.8–42.8 | 24.6–42.5 |
| 2.0 | raw | 766,660 | 1.5–7.0 | 0.1–0.2 |
| 2.0 | zlib | 3,935 | 3.2–8.2 | 3.1–7.9 |
| 2.0 | XOR-delta + zlib | 3,495 | 90.9–169.8 | 90.7–169.5 |

Full-frame zlib shrank test frames ≈ 180–195× (≈ 31 KB/s at 1.0, ≈ 118 KB/s at 2.0 for 30 fps, vs 5.7 / 23 MB/s raw). **These are best-case numbers:** mostly-static black frames, loopback, a Mac CPU (a real watch decodes more slowly) and a debug build.

**Not yet validated:**
- a from-source or AOT engine for watchOS, and anything on a real watch that depends on it (Open Question 9)
- memory, CPU and battery on a real watch; real Wi-Fi behaviour
- worst-case compressibility with busy content; real GPU readback cost
- on-screen redraw behaviour (checks used an off-screen renderer)
- the dev loop with a real macOS app host (E1 ran inside `flutter test`), hot reload, sustained streaming (E1 sent two frames), and taps at pixelRatio 2.0
- Appendix A: real `ZeroCopyCanvas`, DRAW_TEXT parsing, Dart FFI on watchOS, the paint hook

---

## Engine on watchOS: Findings and Proposed Route

This concerns Open Question 9 and is a starting point for anyone building a full implementation. Everything here uses official Flutter artifacts, Apple's SDK and `embedder.h`.

**Experiment (checks Q0–Q6).** Google's published macOS embedder library (universal x86_64 + arm64) was retagged as a watchOS Simulator binary and loaded by a small host written against `embedder.h` with the software renderer. Getting it to load took: rewriting 8 macOS-style framework paths to the flat watchOS layout, stubbing 7 libraries the watchOS SDK lacks (AppKit, Metal, MetalPerformanceShaders, OpenGL, ApplicationServices, two Swift overlays), overlaying 4 CoreVideo symbols watchOS does not export, a small real `NSFont` stand-in, and loading the library with `RTLD_GLOBAL` so the JIT engine finds its built-in snapshot.

| Result | Detail |
|---|---|
| Loads, exports the embedder API | Q4: `FlutterEngineRun`, `FlutterEngineSendWindowMetricsEvent`, `FlutterEngineSendPointerEvent` and others resolve |
| Dart executes, text renders | Q5: a 198×242 frame reached the present callback; a stripe coloured by `fib(20) == 6765` was green; 1,516 glyph pixels rendered on black |
| Byte order | The present callback delivered **RGBA** in this build (inferred from a checker that accepts only one consistent order). A real port must re-measure it |
| Interactive loop | Q6: touch injected via `FlutterEngineSendPointerEvent` at (99, 121) (`kAdd` → `kDown` → `kUp`); the `GestureDetector` fired, `setState()` re-rendered text 'TAP' (1,039 glyph pixels), and a distinct frame 2 was presented |
| Process memory | Q6: Mach resident memory ≈ **146.1–146.3 MB** after frame 1 and **146.5–146.6 MB** after frame 2 (two runs; the frame-to-frame delta was ≈ 0.3–0.4 MB). **This is a Mac process running a debug JIT engine with the full Dart compiler and VM service. It is not a watchOS memory measurement and says nothing about a release AOT build on a watch** |

**What this does not show.** It is a normal Mac process tagged as a watchOS Simulator binary: Mac CPU and memory, and a debug engine that JIT-compiles Dart (which a real watch will not allow). The stubs are zeroed data and unused Metal/IOSurface code never ran. It proves nothing about a source build, AOT, device memory, speed or App Review, and the patched binary must never be distributed.

**Facts from the engine source (pinned commit `89c39edf…`, Dart `416e33b0…`):**
- The build tool's target OS list is `android, ios, mac, linux, fuchsia, wasm, win, qnx`: no watchOS, and `--simulator` is iOS-only.
- `qnx` is the precedent for a new OS: arm64 only, Skia GPU backends off (software-only). The embedder's software surface is on by default.
- `fml/build_config.h` treats watchOS as iOS (`TARGET_OS_IPHONE` is 1 there). 48 of 54 sampled `fml` files compile for watchOS with C++20; the other 6 stopped on `third_party` headers outside the sample.
- Dart's `tools/gn.py` accepts `watchos` / `watchos_simulator`. **Whether the Dart VM builds and runs on watchOS is not verified.**
- The watchOS SDK exports `CAMetalLayer`, `CGBitmapContextCreate`, `CTFontCreateWithName`, but not `MTLCreateSystemDefaultDevice` or `IOSurfaceCreate`.

**Proposed route (untested):**
0. *Build tool:* add `watchos` / `watchos_simulator` target OS, SDK and deployment-target variables; start with the arm64 simulator.
1. *Software-only config modelled on `qnx`:* turn off GL, Metal, Vulkan, Ganesh, Graphite; keep `shell_enable_software`; stop the macOS-host rule that forces Metal on.
2. *OS layers:* `fml` (largely compiles), `third_party` (likely the most small edits), the Dart VM and `gen_snapshot` for a watchOS AOT target, and the iOS-style text layer (not the macOS `NSFont` one).
3. *Host:* Swift over `embedder.h`: `FlutterEngineRun`, software present callback into `WatchFrameStore`/`WatchFrameView`, `FlutterEngineSendPointerEvent` for touch (Crown → scroll events is untested).
4. *Packaging:* flat watchOS framework with `Info.plist`; AOT snapshot via the embedder's AOT options; `icudtl.dat` bundled.
5. *Device:* measure binary size, memory and frame time on real watches; check `arm64_32` (Open Question 8).

**Policy.** Release/AOT only (debug engine, JIT and hot reload are development tools); public Apple APIs only (not yet audited); App Review Guideline 2.5.2 requires apps to be self-contained. The Flutter team does not support custom engine builds long-term, so a port is community-maintained unless upstreamed.

**Smallest further tests:** compile all of `fml` with the missing `third_party` headers · build only the Dart VM for `watchos_simulator` · full from-source engine build on a larger or self-hosted machine (a hosted runner with 3 cores, 7 GB RAM and a 6 h cap is not expected to suffice) · finally a real watch.

---

## Open Questions

1. **Headless frame capture.** Can a stock app produce frames on the dev machine without a visible window, with `toImage` at an acceptable rate? *Answered for `flutter test` on a macOS runner (P2, S1): yes.* Open: a hidden desktop window or `flutter-tester` process, and real GPU readback timing.
2. **Reconnection.** watchOS may suspend or dim foreground apps in always-on / wrist-down states. Define a reconnect strategy plus a full-frame resync (`captureNow()`) after a drop.
3. **`save`/`restore` canvas state** *(Appendix A)*: SwiftUI Canvas has no direct `saveGState`; needs nested canvases or manual transform tracking.
4. **Text measurement parity** *(Appendix A)*: bundled font metrics must match on-device rendering. Not applicable where Flutter rasterizes its own text.
5. **Asset bundling.** How does `flutter build watchos` know which images to bake into the `.watchapp`?
6. **Xcode project structure.** Where does the Swift runtime layer live relative to the Flutter project tree?
7. **Paint hook** *(Appendix A)*: `PaintingContext` creates its own canvases and recorded `Picture`s are opaque, so subclassing `Canvas` intercepts nothing. A hook needs a custom `PaintingContext` / `PipelineOwner` / `RenderView` stack, or primitives that paint through their own API.
8. **Device floor and ABI.** Some older watches are believed to use `arm64_32` (ILP32). Does Dart AOT (and the engine) support it? The answer may raise the floor above Series 4.
9. **Engine on watchOS.** *Shown here:* patched official debug engine code runs in a Simulator process. *Third-party evidence (unverified by us):* flutter-watchos reports the engine running on the watch with App Store apps (see Related Work). *Open:* an open-source recipe, whether the Dart VM builds and runs on watchOS, AOT on a device, binary size, memory, and App Review acceptance.
10. **Simulator networking / CI.** *Answered (P1, P6): yes.* The Simulator reaches host loopback and hosted runners ship a watchOS runtime.
11. **Frame-transport budget.** Which mix of pixel ratio, diffs, zlib and capture-rate cap fits 30 fps, over loopback and then real Wi-Fi? *Partly answered (P9):* zlib gives ≈ 1 KB / 3.9 KB per mostly-static frame. Open: busy content, real Wi-Fi, decode time on a watch.
12. **GPU rendering and API compliance.** flutter-watchos reports Impeller on Metal through an SDK overlay that supplies a Metal framework the watchOS SDK does not declare. Whether Apple accepts that is unknown here, so this design stays on the public-API software path. Open: a public route to GPU rasterization, and the CPU-raster frame-time and battery cost on real devices.

---

## Build Phases

**Phase 0: `watchos_ui` specification**
- [ ] Full widget catalog and `WatchConstraintProfile` for all three screen sizes
- [ ] Verify HIG numbers against the current HIG and cite sources
- [ ] Decide the device floor (Open Question 8)
- [ ] Navigation model and Digital Crown scroll-physics contract

**Phase 0.5: CI validation spikes**
- [x] macOS workflow with a watchOS Simulator destination
- [x] S0 renderer · S1 headless capture · S2 loopback WebSocket · S3 Appendix A fixtures
- [ ] S4 engine-on-watchOS feasibility (partly done; needs a larger machine)

**Phase 1: Proof of concept (dev mode)**
- [ ] `WatchHost` + `WatchFrameStreamer`, Dart WebSocket server, SwiftUI frame view, watchOS listener
- [ ] Tap round trip: `WatchInputInjector` → `setState` → new frame
- [ ] **Milestone 1a:** `WatchText` + `WatchButton` in the Simulator with hot reload (loop verified by E1; hot reload and a real desktop host are not)
- [ ] **Milestone 1b:** the same on a real watch over Wi-Fi (MVP demo)
- [ ] Measure and publish frame time, bandwidth and tap-to-photon latency

**Phase 2: Debug tooling**
- [ ] `ConstraintValidator` (render tree → violations), debug overlay, preview viewport, send gate that blocks critical violations

**Phase 3: Production, engine on device**
- [ ] Feasibility (Open Question 9), Swift embedder host, watchOS AOT build targets, framework linkage
- [ ] Binary size within watchOS limits; memory and frame times per device with Instruments (oldest supported watch, a recent Series, Ultra)
- [ ] Public-API audit: imported symbols of the final binary all resolve against the public watchOS SDK; no stubs, overlays or private frameworks
- [ ] `flutter build watchos` produces a `.watchapp`

**Phase 4: Display-list / zero-copy research (optional, Appendix A)**
- [ ] Solve the paint hook (Open Question 7), Dart FFI bridge, `ZeroCopyCanvas` + `WatchRenderStore`, haptic/event callbacks
- [ ] Measure allocation, frame drops and FFI cost against the hypotheses in Appendix A

**Phase 5: App Store pipeline**
- [ ] Xcode integration and monorepo layout, signing and provisioning, submission validation, example app and docs

---

## Related Work

**flutter-watchos** is an independent, non-official toolchain (macOS on Apple Silicon) that, according to its website (flutterwatch.dev) and its author's August 2026 article, runs the real Flutter engine and framework on the watch itself. It reports: the standard `flutter`-style CLI, hot reload, DevTools and `integration_test` on the watchOS Simulator; profile builds on a paired physical watch (hot reload and debugging stay on the Simulator); Impeller on Metal, using an engine built against an SDK overlay because watchOS declares no Metal framework (with a CPU-rasterizer fallback); Digital Crown input; federated plugins over `dart:ffi`; native SwiftUI platform views; VoiceOver semantics; and watch-only or iPhone-companion apps. Its site lists apps on the App Store (for example Speedrist, Crown Breaker, Chiman) and an open-source Crown Breaker. The August article called it a closed beta; the site now describes GitHub sign-in to download the profile and release engines, with the Simulator needing no account. A companion `flutter_watchos` package (beta, BSD-3) is on pub.dev under the verified publisher flutterwatch.dev.

All of this is taken from those public pages. The site describes the profile and release engines as downloads after sign-in; it does not say whether the engine source is public, and this document has not inspected its code, run its builds or verified the App Store listings. Its compliance with Apple's guidelines has not been assessed here. This design does not depend on it. Its design is closest to Mode 2, and its reported GPU path is a route this document has not tested (see Open Question 12).

| | This design | flutter-watchos (per its website) |
|---|---|---|
| Runtime on watch | Dev: frame viewer · Prod: engine on device (unverified) | Real engine on the watch, AOT for device builds |
| Rendering | Engine software / custom-compositor path → SwiftUI (software path tested only in a patched Simulator process) | Impeller on Metal via an SDK overlay; CPU fallback |
| Widgets | Real framework + `watchos_ui` constraint layer | Standard Flutter widgets (Cupertino works) |
| Dev loop | Mac-hosted VM driving a watch (hypothesis) | Simulator hot reload; profile builds on device, no on-device hot reload |
| Constraint enforcement | Built-in validator (proposed) | No HIG validator mentioned on its site |
| Status | Draft design, partly validated in CI | Public site and docs; GitHub sign-in for device/release engines; apps listed on the App Store |

---

## Appendix A: Display-List Research Path

> ⚠️ **Not part of the primary design.** It describes a different architecture. Under Path A the engine rasterizes every frame, so none of this is needed: no custom wire protocol, no draw-primitive subset, no shared-memory buffer.
>
> It only makes sense if SwiftUI `Canvas` *executes* drawing opcodes instead of showing engine pixels. Something other than the engine must then produce them (a custom `RenderObject` tree or lightweight framework): a different UI framework borrowing Flutter's Dart layer, not "Flutter on watchOS". Consider it only if Phase 3 proves infeasible or too heavy. Open Questions 3, 4 and 7 apply.

**Why not generate Swift bindings?** Dart FFI with `@_cdecl` Swift functions (found at runtime with `DynamicLibrary.process()`) is a core-SDK mechanism with no generated glue layer, so no binding generator is used. `@_cdecl` symbol lookup was verified on watchOS (A4); a Dart FFI call on watchOS was not.

### A.0 `Color(argb:)`

Flutter packs colours as 32-bit ARGB (`Color.toARGB32()`); SwiftUI needs separate sRGB components.

```swift
import SwiftUI

extension Color {
    /// Unpacks 0xAARRGGBB into a SwiftUI sRGB color.
    init(argb: UInt32) {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8)  & 0xFF) / 255.0
        let b = Double( argb        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
```

### A.1 Binary wire format

Dart writes draw commands into native memory slabs shared with Swift. Every command starts with a `Uint32` op ID, and the layout is per op:

| Op | ID | Layout after the 4-byte ID | Bytes | Reader implemented? |
|---|---|---|---|---|
| `DRAW_RECT` | 1 | `Float32 x, y, w, h` · `Uint32 color` | 24 | Yes |
| `DRAW_CIRCLE` | 2 | `Float32 cx, cy, r` · `Uint32 color` | 20 | Skipped (placeholder) |
| `DRAW_TEXT` | 3 | header below + UTF-8 bytes + padding | 28 + N + padding | Yes (untested) |
| `DRAW_RRECT` | 4 | `Float32 x, y, w, h, radius` · `Uint32 color` | 28 | **No**: an unknown op ends the frame |

`DRAW_TEXT` header (offsets in bytes): 0 `Uint32` ID=3 · 4 `Float32` x · 8 `Float32` y · 12 `Uint32` ARGB color · 16 `Float32` font size · 20 `Uint32` flags (weight/alignment, layout set in Phase 0) · 24 `Uint32` string byte length · 28… raw UTF-8, then 0–3 zero bytes so the next command is 4-byte aligned.

Alignment: Swift's `load(as:)` requires correct alignment (undefined behaviour otherwise), while ARM64 hardware tolerates many unaligned accesses. Variable-length commands therefore pad to 4 bytes, and the reader uses `loadUnaligned` as a safety net.

Flutter paints text as an already laid-out `Paragraph`, which cannot be turned back into a string. On this path `WatchText` must be a custom `RenderObject` that measures with bundled font metrics and emits `DRAW_TEXT` itself.

### A.2 Triple-buffer mailbox

A single shared buffer is unsafe (Dart can overwrite it mid-read), and a blocking latch only proves Swift *picked up* the pointer, not that it finished reading. So three persistent slabs live under a lock-protected state machine on the Swift side (classic GPU "mailbox" presentation): the producer never waits and the consumer always shows the newest complete frame.

```
FREE ──acquireWrite──▶ WRITING ──submit──▶ READY ──acquireRead──▶ READING ──(newer frame arrives)──▶ FREE
                                             └── superseded by a newer submit ──▶ FREE
```

- At most one slab each is `WRITING` (Dart), `READY` and `READING` (Swift).
- Dart never blocks: with no `FREE` slab, or on overflow, the frame is dropped.
- Swift redraws only when SwiftUI invalidates the view (no free-running timer).
- Design caveat: this sketch calls `acquireRead()` inside the `Canvas` closure, which mutates mailbox state during drawing. `Canvas` closures may be re-run, so a production version should do that step when the tick is published. (The code below is the tested version and is unchanged.)

**Dart writer** (`drawRect` and `drawText` only; `drawText` is untested):

```dart
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

final DynamicLibrary _dylib = DynamicLibrary.process();

final Pointer<Uint8> Function(int) _slabBase = _dylib.lookupFunction<
    Pointer<Uint8> Function(Int32), Pointer<Uint8> Function(int)>('watch_slab_base');
final int Function() _acquireWriteSlab =
    _dylib.lookupFunction<Int32 Function(), int Function()>('watch_acquire_write_slab');
final void Function(int) _abandonSlab =
    _dylib.lookupFunction<Void Function(Int32), void Function(int)>('watch_abandon_slab');
final void Function(int, int) _submitSlab =
    _dylib.lookupFunction<Void Function(Int32, Int32), void Function(int, int)>('watch_submit_slab');

/// Triple-buffered, low-allocation canvas.
/// Slab memory is owned by the Swift side; Dart only holds typed views over it.
/// Views are created ONCE, so per-field writes allocate no Pointer objects.
class ZeroCopyCanvas {
  final int maxBufferSize;
  final List<ByteData> _views;
  final Map<String, Uint8List> _utf8Cache = {}; // bound this in real code

  int _slab = -1;
  late ByteData _write;
  int _byteOffset = 0;
  bool _overflow = false;

  ZeroCopyCanvas(this.maxBufferSize)
      : _views = List.generate(
          3,
          (i) => _slabBase(i).asTypedList(maxBufferSize).buffer.asByteData(),
          growable: false,
        );

  /// Returns false when no slab is free — skip this frame, never block.
  bool beginFrame() {
    _slab = _acquireWriteSlab();
    if (_slab < 0) return false;
    _write = _views[_slab];
    _byteOffset = 0;
    _overflow = false;
    return true;
  }

  void drawRect(double x, double y, double width, double height, int color) {
    if (_byteOffset + 24 > maxBufferSize) { _overflow = true; return; }

    final o = _byteOffset;
    _write.setUint32(o,      1,      Endian.host);   // DRAW_RECT
    _write.setFloat32(o + 4,  x,      Endian.host);
    _write.setFloat32(o + 8,  y,      Endian.host);
    _write.setFloat32(o + 12, width,  Endian.host);
    _write.setFloat32(o + 16, height, Endian.host);
    _write.setUint32(o + 20, color,   Endian.host);

    _byteOffset += 24;
  }

  void drawText(double x, double y, String text, double fontSize, int color, int flags) {
    // Encoding allocates, so cache by string (mostly static UI text).
    final utf8Bytes = _utf8Cache.putIfAbsent(text, () => Uint8List.fromList(utf8.encode(text)));
    final stringLength = utf8Bytes.length;

    // Total size = 28-byte header + string bytes, padded to 4-byte boundary
    final rawSize = 28 + stringLength;
    final padding = (4 - (rawSize % 4)) % 4;
    final totalCommandSize = rawSize + padding;

    if (_byteOffset + totalCommandSize > maxBufferSize) { _overflow = true; return; }

    final o = _byteOffset;
    _write.setUint32(o,      3,          Endian.host);   // DRAW_TEXT
    _write.setFloat32(o + 4,  x,          Endian.host);
    _write.setFloat32(o + 8,  y,          Endian.host);
    _write.setUint32(o + 12, color,       Endian.host);
    _write.setFloat32(o + 16, fontSize,   Endian.host);
    _write.setUint32(o + 20, flags,       Endian.host);
    _write.setUint32(o + 24, stringLength, Endian.host);

    for (int i = 0; i < stringLength; i++) {
      _write.setUint8(o + 28 + i, utf8Bytes[i]);
    }

    // Zero the padding explicitly — malloc'd memory is not zeroed and slabs are reused
    for (int i = 0; i < padding; i++) {
      _write.setUint8(o + rawSize + i, 0);
    }

    _byteOffset += totalCommandSize;
  }

  /// Hands the completed frame to Swift. Non-blocking.
  /// An overflowed (incomplete) frame is abandoned instead of shown.
  void commitFrame() {
    if (_overflow) {
      _abandonSlab(_slab);
    } else {
      _submitSlab(_slab, _byteOffset);
    }
  }
}
```

**Swift store, C entry points and reader:**

```swift
import os
import SwiftUI

enum SlabState { case free, writing, ready, reading }

struct Slab {
    let base: UnsafeMutableRawPointer
    var state: SlabState = .free
    var byteCount: Int = 0
}

// Owns the slabs and the mailbox state machine.
// SwiftUI observes ONE value — a frame counter. Raw pointers are never published.
final class WatchRenderStore: ObservableObject {
    @Published var frameTick: UInt64 = 0

    private let lock: OSAllocatedUnfairLock<[Slab]>   // watchOS 9+

    init(slabBytes: Int) {
        var slabs: [Slab] = []
        for _ in 0..<3 {
            var p: UnsafeMutableRawPointer?
            posix_memalign(&p, 16, slabBytes)
            memset(p!, 0, slabBytes)
            slabs.append(Slab(base: p!))
        }
        lock = OSAllocatedUnfairLock(initialState: slabs)
    }

    func base(_ i: Int) -> UnsafeMutableRawPointer { lock.withLock { $0[i].base } }

    /// Free slab index, or -1 (Dart drops the frame).
    func acquireWrite() -> Int {
        lock.withLock { s in
            guard let i = s.firstIndex(where: { $0.state == .free }) else { return -1 }
            s[i].state = .writing
            return i
        }
    }

    func submit(_ i: Int, byteCount: Int) {
        lock.withLock { s in
            for j in s.indices where s[j].state == .ready { s[j].state = .free } // superseded
            s[i].state = .ready
            s[i].byteCount = byteCount
        }
    }

    func abandon(_ i: Int) { lock.withLock { $0[i].state = .free } }

    /// Newest frame to draw; re-returns the current slab until a newer one is ready.
    func acquireRead() -> (UnsafeRawPointer, Int)? {
        lock.withLock { s in
            if let r = s.firstIndex(where: { $0.state == .ready }) {
                for j in s.indices where s[j].state == .reading { s[j].state = .free }
                s[r].state = .reading
            }
            guard let cur = s.firstIndex(where: { $0.state == .reading }) else { return nil }
            return (UnsafeRawPointer(s[cur].base), s[cur].byteCount)
        }
    }
}

let sharedRenderStore = WatchRenderStore(slabBytes: 64 * 1024)   // size is a placeholder

@_cdecl("watch_slab_base")
public func watchSlabBase(_ i: Int32) -> UnsafeMutableRawPointer { sharedRenderStore.base(Int(i)) }

@_cdecl("watch_acquire_write_slab")
public func watchAcquireWriteSlab() -> Int32 { Int32(sharedRenderStore.acquireWrite()) }

@_cdecl("watch_abandon_slab")
public func watchAbandonSlab(_ i: Int32) { sharedRenderStore.abandon(Int(i)) }

@_cdecl("watch_submit_slab")
public func watchSubmitSlab(_ i: Int32, _ byteCount: Int32) {
    sharedRenderStore.submit(Int(i), byteCount: Int(byteCount))
    DispatchQueue.main.async { sharedRenderStore.frameTick &+= 1 }   // non-blocking: Dart never waits
}

// SwiftUI Canvas — reads raw bytes directly during the native draw pass.
// GraphicsContext stays inside this closure. Every read is bounds-checked.
struct WatchCanvasView: View {
    @ObservedObject var store = sharedRenderStore

    var body: some View {
        // No TimelineView: each submitted slab bumps frameTick, which invalidates
        // this view, so the Canvas redraws once per new frame.
        let tick = store.frameTick
        Canvas { context, _ in
            _ = tick  // explicit dependency so the closure is re-evaluated per frame
            guard let (buffer, byteCount) = store.acquireRead() else { return }

            var offset = 0
            func need(_ n: Int) -> Bool { offset + n <= byteCount }

            while need(4) {
                let commandId = buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)

                switch commandId {
                case 1: // DRAW_RECT — 24 bytes
                    guard need(24) else { return }
                    let x     = buffer.loadUnaligned(fromByteOffset: offset + 4,  as: Float.self)
                    let y     = buffer.loadUnaligned(fromByteOffset: offset + 8,  as: Float.self)
                    let w     = buffer.loadUnaligned(fromByteOffset: offset + 12, as: Float.self)
                    let h     = buffer.loadUnaligned(fromByteOffset: offset + 16, as: Float.self)
                    let color = buffer.loadUnaligned(fromByteOffset: offset + 20, as: UInt32.self)

                    let rect = CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h))
                    context.fill(Path(rect), with: .color(Color(argb: color)))
                    offset += 24

                case 2: // DRAW_CIRCLE — placeholder, 20 bytes
                    guard need(20) else { return }
                    offset += 20

                case 3: // DRAW_TEXT — variable length
                    guard need(28) else { return }
                    let x          = buffer.loadUnaligned(fromByteOffset: offset + 4,  as: Float.self)
                    let y          = buffer.loadUnaligned(fromByteOffset: offset + 8,  as: Float.self)
                    let color      = buffer.loadUnaligned(fromByteOffset: offset + 12, as: UInt32.self)
                    let fontSize   = buffer.loadUnaligned(fromByteOffset: offset + 16, as: Float.self)
                    // flags at offset + 20: weight / alignment (bit layout defined in Phase 0)
                    let textLength = Int(buffer.loadUnaligned(fromByteOffset: offset + 24, as: UInt32.self))
                    guard need(28 + textLength) else { return }

                    // Swift keeps small strings inline (≤ 15 UTF-8 bytes on 64-bit, 10 on ILP32);
                    // longer strings allocate.
                    let stringPtr = buffer.advanced(by: offset + 28)
                        .assumingMemoryBound(to: UInt8.self)
                    let text = String(
                        decoding: UnsafeBufferPointer(start: stringPtr, count: textLength),
                        as: UTF8.self
                    )
                    context.draw(
                        Text(verbatim: text)
                            .font(.system(size: CGFloat(fontSize)))
                            .foregroundColor(Color(argb: color)),
                        at: CGPoint(x: CGFloat(x), y: CGFloat(y)),
                        anchor: .topLeading   // Flutter paints from the top-left; SwiftUI defaults to .center
                    )

                    // Advance by variable size + 4-byte alignment padding
                    let rawSize = 28 + textLength
                    let padding = (4 - (rawSize % 4)) % 4
                    offset += rawSize + padding

                default:
                    return // corrupted stream — bail; add debug logging in non-release builds
                }
            }
            #if DEBUG
            assert(offset == byteCount, "command stream ended mid-command")
            #endif
        }
    }
}
```

**Caveats**
- If SwiftUI skips a redraw because the closure compares equal, add `.id(tick)` to the `Canvas`; do not fall back to `TimelineView(.animation)`. (Redraw on `frameTick` was verified off-screen, S6.)
- `DynamicLibrary.process()` finds the `@_cdecl` symbols only if they are exported and not dead-stripped. Verify with the real Xcode build settings.
- Expected benefits (low GC pressure, no payload copy at the FFI boundary, no blocking) are **design expectations, not measurements**. Candidate measurements: Dart DevTools allocations, Instruments → Allocations, the drop rate from failed `acquireWrite`, FFI call time vs the 33 ms frame budget.
- Three slabs cost memory; check headroom per device.

---

## References

- Flutter custom engine embedders: https://github.com/flutter/flutter/wiki/Custom-Flutter-Engine-Embedders
- Embedder API (engine lives in the `flutter/flutter` monorepo; verify path): https://github.com/flutter/flutter/blob/main/engine/src/flutter/shell/platform/embedder/embedder.h
- `flutter_pi` (reference community embedder): https://github.com/ardera/flutter-pi
- Dart FFI: https://dart.dev/interop/c-interop
- Apple watchOS HIG: https://developer.apple.com/design/human-interface-guidelines/watchos
- SwiftUI Canvas: https://developer.apple.com/documentation/swiftui/canvas · GraphicsContext: https://developer.apple.com/documentation/swiftui/graphicscontext
- flutter-watchos: https://flutterwatch.dev (docs: https://github.com/flutterwatch/flutter-watchos/blob/main/doc/get-started.md) · https://github.com/flutterwatch/flutter-watchos · article: https://itnext.io/yes-you-can-build-apple-watch-apps-with-flutter-now-909c3dc84804
- GitHub-hosted macOS runners: https://docs.github.com/en/actions/using-github-hosted-runners/using-github-hosted-runners/about-github-hosted-runners

---

## Changelog

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
- **Numbers refreshed from the latest CI sheet:** Q6 memory is now a range across two runs (146.06–146.58 MB), P6 first-frame time 158–232 ms, and P9 raw/1.0 encode time 0.5–1.9 ms (the previous upper bound, 1.2, was exceeded).

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
