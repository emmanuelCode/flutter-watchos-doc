# Flutter for watchOS
### Architecture & MVP Strategy
> A Flutter platform embedder targeting standalone Apple Watch

**Status:** Draft · **Last updated:** November 2026
*Provenance: AI-assisted spec and tests, human-reviewed.*

**Scope & validation state:** Partially validated in CI (macOS runner, watchOS Simulator). The Simulator loopback dev loop passes in CI within test-harness limits, and a *patched* official Flutter engine executes Dart, renders frames, and handles synthetic touch/scroll inside a Simulator process. **Nothing has run on a real watch, and no shippable engine build exists.** See [Validation](#validation).
**Minimum target:** watchOS 27+ (Apple Watch SE 3, Series 9+, Ultra 2+; `arm64`-only per developer toolchains/reports, see Resolved Design Decisions). Note: `watchos-proofs` keeps `Package.swift` at `.watchOS(.v10)` and CI runs on the watchOS 26.5 Simulator SDK, so CI does **not** validate the watchOS 27+ floor.

---

## Contents
1. [Vision](#vision) · 2. [Constraints](#core-constraints) · 3. [Compliance](#compliance-principles) · 4. [Architecture decision](#architecture-decision) · 5. [`watchos_ui`](#the-watchos_ui-package) · 6. [Two modes](#two-mode-architecture) · 7. [Frame streamer](#the-frame-streamer-dart-side) · 8. [Debug interceptor](#the-debug-interceptor) · 9. [Watch renderer](#the-swiftui-renderer-watch-side) · 10. [Events & haptics](#events--haptics) · 11. [Power & lifecycle](#power--lifecycle-rules-proposed) · 12. [MVP](#mvp) · 13. [Validation](#validation) · 14. [Engine on watchOS](#engine-on-watchos-findings-and-proposed-route) · 15. [Open questions](#open-questions) · 16. [Phases](#build-phases) · 17. [Related work](#related-work) · [Resolved decisions](#resolved-design-decisions) · [References](#references)

---

## Vision

Let Flutter developers write widgets in Dart, exactly as they do today, and run them on a standalone Apple Watch with no iPhone. Flutter's own engine rasterizes every frame; SwiftUI `Canvas` is the surface that puts those pixels on the watch.

Rather than forcing Material/Cupertino onto a 40 mm screen, a bespoke `watchos_ui` package encodes Apple's Human Interface Guidelines (HIG) by design: correct layout math, performance and native-feeling interaction from the start.

The scope is comparable to `flutter_pi` (the community embedder for Raspberry Pi): a new embedder for a constrained, non-phone target.

### Why Not `flutter-watchos`?

An independent community toolchain, [`flutter-watchos`](https://flutterwatch.dev), already exists. Per its documentation and website (not inspected or verified by us), it ships prebuilt profile/release engines behind GitHub sign-in and uses Impeller on Metal via an SDK overlay. This design pursues two distinct goals:

1. **An open, public-API-only `embedder.h` runtime (Layer 2):** Built from official Flutter sources plus an open patch set, avoiding un-audited SDK overlays or opaque engine binaries.
2. **Engine-agnostic `watchos_ui`, HIG validator, and Mode 1 tooling (Layer 1):** **Designed to run** on stock Flutter and target *any* watchOS engine underneath (`watchos_ui` is currently specified, not built).

Decoupling Layer 1 from Layer 2 means the UI constraint layer, validator, and remote preview tooling retain standalone value even if Layer 2 later targets an upstream or third-party watchOS engine.

---

## Core Constraints

| Constraint | Detail |
|---|---|
| No Metal directly | `MTKView` is unavailable and the watchOS SDK does not export `MTLCreateSystemDefaultDevice` (observed in the watchOS SDK dependency gap check), so GPU access is normally indirect (SwiftUI Canvas / SpriteKit). flutter-watchos reports reaching Metal through an SDK overlay; this design does not use that route (Open Question 12) |
| No UIKit | WatchKit + SwiftUI only |
| Memory | **~30 MB is an unverified working ceiling** pending real-watch RSS and jetsam measurement. As an **illustrative floor only** (excluding Dart heap, glyph caches, engine code pages, and OS overhead), our artifact check measured `icudtl.dat` at 844 KB and dual `208×248 @2x` RGBA framebuffers at ~1.6 MB (compared to the 23.1 MB debug `kernel_blob.bin` stripped by AOT). Primary production feasibility risk to validate per device |
| Skia CPU deprecation | Path A's boundary is `embedder.h` (`FlutterRendererConfig`), not Skia CPU permanently. Because Impeller provides no software/CPU backend as of late 2026, if upstream removes Skia's software rasterizer our two contingencies are: **(A)** pin Skia's minimal CPU subset behind `FlutterSoftwareRendererConfig` in our patch set, or **(B)** swap to `FlutterMetalRendererConfig` / `SpriteView` (`SKMutableTexture`) if the compliance gate clears it—requiring zero changes to `watchos_ui` or Dart code (Open Question 12) |
| No JIT on device | On-device Dart must be AOT-compiled, so there is no on-device hot reload. AOT output still carries a Dart runtime (GC etc.) |
| No dynamic code | Apple restricts downloading and executing executable code at runtime (App Review Guideline 2.5.2, subject to narrow exceptions) |
| Background limits & TN3135 | The OS suspends background work aggressively; any dev listener must stay in a foreground session. Furthermore, per Apple TN3135 (*Low-level networking on watchOS*), `URLSessionWebSocketTask`, `URLSessionStreamTask`, `NWConnection`, `NWBrowser` (Bonjour), `NSNetService`, and BSD sockets are blocked on physical watches (watchOS 9+) outside active audio streaming or CallKit VoIP, while the Simulator always allows them (`ws://` is Simulator-only) |
| Screen sizes | 40 mm & 44 mm (Apple Watch SE 3; provisional pending HIG verification) · 41 mm → 176×215 pt · 42 mm → 187×223 pt · 45 mm → 198×242 pt · 46 mm → 208×248 pt · 49 mm Ultra → 205×251 pt (CI Simulator device is 46 mm; current checks run at 45 mm; 42/46 mm specs per Apple Series 10 HIG) |
| Device floor & ABI | watchOS 27+ supports Apple Watch SE 3, Series 9+, and Ultra 2+ (per Apple Support *Update your Apple Watch* and Apple's watchOS 27 page), dropping Series 6–8, SE 2, and Ultra 1 (identified as `arm64_32` in developer toolchains/reports). Setting the floor at watchOS 27+ trades away those older watches to avoid the ILP32 Dart AOT porting risk |

---

## Compliance Principles

This document is a design, not a compliance review. It is built around Apple-supported mechanisms: public APIs only, pixels presented through SwiftUI, AOT builds with no downloaded code (see App Review Guidelines 2.5.1 and 2.5.2), and an engine build from official Flutter sources plus an open, published patch set. Stubbed or patched binaries, such as the retagged Simulator engine experiment, are research artifacts and never ship, and the Metal-overlay route reported for flutter-watchos is not used (Open Question 12). Whoever implements this, or the Flutter team, should verify these points against Apple's current guidelines and, where unclear, ask Apple before relying on them.

---

## Architecture Decision

Two incompatible answers to "who draws the pixels?" cannot share one pipeline, so this document picks one.

| | **Path A: engine rasterizes (primary)** | **Path B: display list ([research note](docs/display-list-research.md))** |
|---|---|---|
| Who rasterizes | Flutter engine via `embedder.h` (`FlutterRendererConfig`: software today, Metal/compositor if cleared) | SwiftUI `Canvas` executes drawing opcodes |
| What crosses the boundary | Dev: rendered frames over WebSocket · Prod: engine pixels, in-process | Draw commands (binary slabs in shared memory) |
| Role of `watchos_ui` | HIG / performance constraint layer; ordinary Flutter widgets | Hard requirement; only widgets that emit opcodes render |
| Needs a paint hook | No | Yes (Open Question 7) |
| Needs the Flutter engine | Yes | No, but then it is not Flutter widgets |
| Phases | 1–3 | 4 (optional) |

**Decision: Path A.** `watchos_ui` restricts widgets for HIG and performance reasons, not because the rasterizer is limited; the engine rasterizes whatever Flutter paints. Nothing in Phases 1–3 depends on Path B ([docs/display-list-research.md](docs/display-list-research.md)). New sections must say which path they belong to.

---

## The `watchos_ui` Package

> ⚠️ Must be specified before implementation: every other layer depends on its widget surface.

Under Path A, `watchos_ui` is a constraint layer (enforced by the validator and lints), not a renderer limit. `WatchText` and `WatchButton` are ordinary widgets composed from real Flutter widgets. `watchos_ui` intentionally targets Apple Watch HIG directly rather than a generic `wearable_ui` abstraction (mirroring Flutter's `cupertino` vs. `material` split; see [docs/wearables-ui-strategy.md](docs/wearables-ui-strategy.md)).

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

**Navigation (watchOS 27+; underlying SwiftUI APIs available since watchOS 10+):** `WatchPageScaffold` (horizontal pages, like Workout/Activity) and `WatchListScaffold` (vertical list driven by the Digital Crown). A push/pop `WatchHierarchicalRouter` is excluded from v0 as a scope decision; `NavigationStack` still exists on watchOS 10.

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

Two hosts, same Mac-side renderer contract:
- **1a: watchOS Simulator (default, only evidenced dev loop).** Loopback `ws://` WebSocket connection, no hardware, runs in CI. Because the Simulator always allows low-level networking (Apple TN3135), `ws://` is **Simulator-only**.
- **1b: physical watch (EXPERIMENTAL, unverified).** Per Apple TN3135, `URLSessionWebSocketTask` and `NWBrowser` (Bonjour) are blocked on physical watches outside active audio/VoIP sessions. Candidate transports, both **untested on hardware**:
  - **(a) HTTP via `URLSession.bytes`:** Chunked HTTP response for frames + HTTP POST for input. Known risks: developer reports of `URLSession` failing on a watch with no internet beyond a local router, plus unverified ATS behavior for local cleartext HTTP on watchOS.
  - **(b) `WatchConnectivity` via paired iPhone:** Requires an iPhone companion app; frame-streaming throughput unknown.
  - Host address must be baked into the debug build or delivered via the paired iPhone (no `NWBrowser`, no QR scanning or manual typing on the watch). Any dev server must require a pairing/auth token so LAN peers cannot view streamed UI, and be excluded from release builds with `#if DEBUG`.

Dev loop (Mode 1a target): save in VS Code → Dart VM hot reloads → Flutter produces a frame → interceptor validates → frame pushed to the watch → tap returns → inject → `setState` → repeat. Target: **≤ 300 ms from save or tap to updated pixels** (hypothesis anchored to interactive UI feedback latency; unmeasured).

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
    this.pixelRatio = 1.0, // 1.0 keeps bandwidth low (stretches 2x on watch and looks soft); 2.0 is opt-in for visual QA
  });

  final GlobalKey boundaryKey;
  final void Function(Uint8List rgba, int width, int height, int frameId) sink;
  final double pixelRatio;

  bool _captureInFlight = false;
  bool _capturePending = false;
  bool _active = false;
  bool _stopped = false;
  bool _callbackRegistered = false;
  int _frameId = 0;

  void start() {
    _active = true;
    _stopped = false;
    if (_callbackRegistered) return;
    _callbackRegistered = true;
    // Persistent callbacks fire on every produced frame — natural
    // "something changed" detection.
    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      if (!_active) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
    });
  }

  void stop() {
    _active = false;
    _stopped = true;
    _capturePending = false;
  }

  /// Call when a watch (re)connects. An idle app produces no frames, so without this a
  /// newly connected watch would show nothing until something on screen changes.
  Future<void> captureNow() => _capture();

  Future<void> _capture() async {
    if (_stopped) return;
    if (_captureInFlight) {
      _capturePending = true; // coalesce so the final frame is never dropped
      return;
    }
    final boundary = boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null || boundary.debugNeedsPaint) return;

    _captureInFlight = true;
    _capturePending = false;
    try {
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data != null && !_stopped) {
        sink(data.buffer.asUint8List(), image.width, image.height, _frameId++);
      }
      image.dispose();
    } finally {
      _captureInFlight = false;
      if (_capturePending && !_stopped) {
        _capturePending = false;
        unawaited(_capture());
      }
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
- After `start()` nothing is captured until Flutter next produces a frame, and an idle app produces none (found during headless capture testing). `captureNow()` fixes this: call it on connect or resync (verified in idle-app and end-to-end Simulator tests).
- The watch sends taps in logical points of its own screen; the host adds the app's screen origin before injecting. Verified at `pixelRatio` 1.0 only in the end-to-end Simulator test; at 2.0 the watch must divide frame-pixel coordinates by the ratio (untested).

### Known risks

| Risk | Notes |
|---|---|
| Readback cost | `toImage` + `toByteData` is an async GPU→CPU readback plus a full-frame copy, likely the frame-rate ceiling. Headless capture works in headless Flutter tests, but those timings come from the test renderer, which has no real GPU |
| Bandwidth | Raw RGBA ≈ 192 KB/frame at pixelRatio 1.0, ≈ 767 KB at 2.0 (table below). Measured zlib: ≈ 1 KB / 3.9 KB on mostly-static frames; worst-case content is unmeasured |
| Dev ≠ prod | Mode 1 does not exercise the watchOS engine, memory or performance |
| Input latency & preview softness | At `pixelRatio` 1.0, frames stretch 2x on Retina watch displays and look soft (`2.0` is opt-in for visual QA). A Wi-Fi round trip would feel laggy: acceptable only for experimental dev checks, not end users |
| Headless host | Proven under `flutter test` on a macOS runner; a hidden desktop window or `flutter-tester` process is untested (Open Question 1) |
| Rendering mismatch | Pixels rendered on the Mac may differ on-device (fonts, scaling, colour) |

**Bandwidth** (uncompressed RGBA, 45 mm screen 198×242 pt):

| Pixel ratio | Frame size | At 30 fps |
|---|---|---|
| 1.0 (198×242 px) | 191,664 B ≈ 192 KB | ≈ 5.7 MB/s |
| 2.0 (396×484 px) | 766,656 B ≈ 767 KB | ≈ 23 MB/s |

Candidate mitigations: default to `pixelRatio` 1.0 (`2.0` opt-in for visual QA) · send only on change (already true) · full-frame zlib (best-case Mac debug measurements below) · optional capture-rate cap (unmeasured) · long term, avoid GPU readback with Mode 2's software present callback. Dirty-rect/XOR-delta diffs were measured and rejected for now (≈ 11–12 % smaller than zlib, ≈ 20–40× slower to decode in a debug build).

Because Flutter rasterizes its own text in this mode, there is no Dart-vs-Core-Text parity problem (that applies only to Path B (`docs/display-list-research.md`)).

---

## The Debug Interceptor

Sits between the frame source and the WebSocket sender. Validates each frame against a `WatchConstraintProfile` by inspecting the **render tree** (sizes, touch targets, font sizes). Critical violations block transmission.

**Profile fields:** `screenWidth`, `screenHeight`, `maxPayloadBytes`, `minTouchTarget` (44 pt), `minFontSize` (14 pt), `maxFontSize` (34 pt), `crownExclusionZone`, with presets for all supported display sizes (provisional 40 and 44 mm for SE 3 pending HIG verification, plus 41, 42, 45, 46 and 49 mm). (`maxDrawCallsPerFrame` applies only to Path B (`docs/display-list-research.md`); under Path A use render-object count, layer count and capture time.) Numeric limits are provisional until checked against the HIG.

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

The frame is stretched to fill the view (verified in off-screen SwiftUI render tests), so it fits whatever `pixelRatio` was captured. That is only correct when the captured boundary has the same aspect ratio as the view: size the boundary to the watch's logical screen. Redraw-on-publish was verified with an off-screen `ImageRenderer`, not yet on a live screen.

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
| 2 | **Frames only on invalidation** | No free-running display link or `TimelineView(.animation)`. By design; idle frame count (0 frames) verified in Mode 1 Dart tests only, engine path unmeasured |
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

Steps 1–6 target **Mode 1a (real macOS desktop host + Simulator)** with live hot reload and sustained multi-frame streaming. Step 7 on a real watch (**Mode 1b**) is an experimental, contributor-gated hardware milestone and is not a Phase 1–2 headline.

**Excluded from the MVP:** desktop preview viewport (Phase 2), full `watchos_ui` catalog, constraint validator, FFI and display-list mode (Phase 4), production engine build (Phase 3), App Store submission (Phase 5).

**Timeline:** not estimated until Open Question 1 is answered on a real desktop host.

---

## Resolved Design Decisions

| Question | Decision |
|---|---|
| Layout / state | Run entirely Dart-side (on the Mac in dev, on the watch in prod). In dev only rendered output crosses the wire |
| Animations | Run inside Flutter; frames are streamed in dev |
| Fonts | Flutter rasterizes its own text in both modes, so no cross-renderer parity is needed (parity is open only for Path B (`docs/display-list-research.md`), Open Question 4) |
| Images | Pre-bundled in the `.watchapp` at build time |
| Navigation | `WatchPageScaffold` + `WatchListScaffold` only (scope decision) |
| Production runtime | Real Flutter engine on device via the embedder API |
| Dev loop host | Simulator over loopback first, physical watch second |
| Device floor & ABI | watchOS 27+ (SE 3, Series 9+, Ultra 2+; `arm64`-only per toolchains), trading away Series 6–8, SE 2, Ultra 1 (`arm64_32`) to avoid ILP32 Dart AOT risk |
| Frame rate | 30 fps burst throughput (≤ 33 ms per invalidated frame): a hypothesis, to be measured (idle behavior by design; idle frame count verified in Mode 1 Dart tests only, engine path unmeasured) |
| Frame encoding (dev) | Full-frame zlib; XOR-delta rejected for now. Provisional until worst-case content is measured |
| Late-joining client | Call `captureNow()` on connect / resync |
| Dart ↔ Swift interop | Dart FFI with `@_cdecl`, for Path B (`docs/display-list-research.md`) only (not needed for Path A rendering) |

---

## Validation

Checks run in CI on GitHub-hosted macOS runners with the watchOS Simulator, with no owned hardware needed (free for public repositories at the time of writing; verify current terms). The runnable proofs and capability-to-check traceability table live in [`watchos-proofs/README.md`](watchos-proofs/README.md), and the code blocks in this spec (plus the Path B research blocks in [`docs/display-list-research.md`](docs/display-list-research.md)) are extracted and tested automatically. **A code section counts as specified only once its snippet compiles in CI.**

Latest environment: macOS arm64 runner, Xcode 26.6, watchOS 26.5 Simulator, Flutter 3.50.0, Dart 3.14.0. Status values progress Unverified → Compiles → Tested → Measured; **"Tested" means tested in the Simulator, never on a physical watch.**

### Capability verification summary

| Capability | Status & Scope | Notes / Limits |
|---|---|---|
| **Watch-side SwiftUI renderer** (`WatchFrameStore`, `WatchFrameView`) | Tested in Simulator | Compiles for watchOS; RGBA → `CGImage` → `Canvas` renders stretched to fill; off-screen `ImageRenderer` confirms pixel updates on publish (does not prove live hardware screen invalidation) |
| **Headless Dart frame capture & input** (`WatchFrameStreamer`, `WatchInputInjector`) | Tested in `flutter test` | Captures raw RGBA with no window; `captureNow()` pushes current frame from an idle app; `stop()` and mid-capture coalescing verified; injected taps trigger `setState()` |
| **Loopback WebSocket transport** | Tested in Simulator | Dart server → watchOS Simulator client sends 192 KB frame down and tap up (first frame incl. handshake: 120–259 ms across runs). Passes because Simulator allows low-level networking per Apple TN3135; **not** valid evidence for physical watch `ws://` |
| **End-to-end dev loop** (Streamer + Injector ↔ WebSocket ↔ SwiftUI View) | Tested in Simulator | On connect `captureNow()` pushed frame 0 (red); tap at (99, 121) returned; frame 1 arrived (green). Host side ran inside `flutter test`, not a real macOS desktop app; no hot reload or sustained multi-frame animation tested |
| **Path B display-list fixtures** | Tested with stand-ins | Anchor fix (`.topLeading`), triple-buffer mailbox, Dart-to-Swift byte parsing, `@_cdecl` `dlsym` lookup, and `WatchCanvasView` (`DRAW_RECT`) pass; `ZeroCopyCanvas` and `DRAW_TEXT` remain unverified |

*(The dev-loop harness checks above are reported separately from the retagged engine smoke test below; CI setup and extraction helper steps are excluded from capability counts.)*

### Retagged engine smoke test (separate from dev loop)

- **Status:** Retagged Mac debug JIT binary with stubbed Apple frameworks running in a Simulator process; **proves `embedder.h` wiring only.** Not a source build, not AOT, not on-device memory.

**Sustained loopback transport:** 100 frames per configuration across CI runs, Simulator loopback, debug build.

| Pixel ratio | Encoding | Bytes/frame | ms/frame | Decode ms/frame |
|---|---|---|---|---|
| 1.0 | raw | 191,668 | 0.5–1.9 | 0.0–0.1 |
| 1.0 | zlib | 1,047 | 0.9–2.3 | 0.8–2.1 |
| 1.0 | XOR-delta + zlib | 922 | 22.5–42.8 | 22.4–42.5 |
| 2.0 | raw | 766,660 | 1.5–7.0 | 0.1–0.2 |
| 2.0 | zlib | 3,935 | 3.2–8.2 | 3.1–7.9 |
| 2.0 | XOR-delta + zlib | 3,495 | 90.9–169.8 | 90.7–169.5 |

Full-frame zlib shrank test frames ≈ 180–195× (≈ 31 KB/s at 1.0, ≈ 118 KB/s at 2.0 at 30 fps burst, vs 5.7 / 23 MB/s raw). **These are best-case Mac debug measurements:** mostly-static black frames, Simulator loopback, a Mac CPU (a real watch decodes more slowly), and a debug build.

### Known test limitations (open)

1. **SDK gap script (`libSystem` false positives):** `engine_gap.py` flags basic `libSystem` symbols (`_bzero`, `___error`) as missing on watchOS; only framework-level gaps are reliable.
2. **Off-screen redraw assertions:** The SwiftUI redraw tests verify updated pixel colors via off-screen `ImageRenderer`, but only log `invalidated` without asserting it; this does not prove live on-screen SwiftUI invalidation on watchOS hardware.
3. **Unexercised `WatchHost`:** Mode 1 has not run in a real macOS desktop host (`flutter test` stood in), with live hot reload, or under sustained multi-frame streaming (the E2E check sent two frames).
4. **Geometry drift across tests:** CI boots a 46 mm Simulator (`208×248 pt`), whereas the loopback, E2E, and engine smoke tests render `198×242` (45 mm) and headless Dart capture tests run on `flutter test`'s `800×600` surface.

**Not yet validated:**
- a from-source or AOT engine for watchOS, and anything on a real watch that depends on it (Open Question 9)
- memory, CPU and battery on a real watch; real Wi-Fi behaviour
- worst-case compressibility with busy content; real GPU readback cost
- on-screen redraw behaviour (checks used an off-screen renderer)
- Crown input end to end: capturing SwiftUI `.digitalCrownRotation` and mapping it to engine scroll events (Q7 injects the scroll signal synthetically)
- the dev loop with a real macOS app host (E1 ran inside `flutter test`), hot reload, sustained streaming (E1 sent two frames), and taps at pixelRatio 2.0
- Path B (`docs/display-list-research.md`): real `ZeroCopyCanvas`, DRAW_TEXT parsing, Dart FFI on watchOS, the paint hook

---

## Engine on watchOS: Findings and Proposed Route

This concerns Open Question 9 and is a starting point for anyone building a full implementation. Everything here uses official Flutter artifacts, Apple's SDK and `embedder.h`.

**Experiment (retagged Simulator smoke test).** Google's published macOS embedder library (universal x86_64 + arm64) was retagged as a watchOS Simulator binary and loaded by a small host written against `embedder.h` with the software renderer. Getting it to load took: rewriting 8 macOS-style framework paths to the flat watchOS layout, stubbing 7 libraries the watchOS SDK lacks (AppKit, Metal, MetalPerformanceShaders, OpenGL, ApplicationServices, two Swift overlays), overlaying 4 CoreVideo symbols watchOS does not export, a small real `NSFont` stand-in, and loading the library with `RTLD_GLOBAL` so the JIT engine finds its built-in snapshot.

| Result | Detail |
|---|---|
| Loads, exports the embedder API | `FlutterEngineRun`, `FlutterEngineSendWindowMetricsEvent`, `FlutterEngineSendPointerEvent` and others resolve |
| Dart executes, text renders | A 198×242 frame reached the present callback; a stripe coloured by `fib(20) == 6765` was green; 746–1,516 bright glyph pixels (varies by run) rendered on black |
| Byte order | The present callback delivered **RGBA** in this build (inferred from a checker that accepts only one consistent order). A real port must re-measure it |
| Interactive loop | Touch injected via `FlutterEngineSendPointerEvent` at (99, 121) (`kAdd` → `kDown` → `kUp`); the `GestureDetector` fired, `setState()` re-rendered text 'TAP' (1,039–1,355 bright glyph pixels, varies by run), and a distinct frame 2 was presented |
| Scroll signal and low-memory hook | A synthetic scroll signal (`kFlutterPointerSignalKindScroll`, delta_y 40.0) sent through `FlutterEngineSendPointerEvent` reached a Dart `Listener` as a `PointerScrollEvent`, `setState()` re-rendered the text as 'CROWN' (1,650 bright glyph pixels, one run), and a third distinct frame was presented. The embedder's `FlutterEngineNotifyLowMemoryWarning` returned 0 (success). Mach resident memory read 141.47 → 142.92 → 140.44 MB across frames 1–3, and 140.11 MB after the low-memory call, within the roughly ±2 MB fluctuation seen between frames, so no memory effect is claimed. **This is the engine half of Crown support only: no Crown hardware and no SwiftUI `.digitalCrownRotation` were involved** |
| Process memory | Mach resident memory reads **140.1–143.0 MB** under the current Flutter 3.50.0 / Dart 3.14.0 build (for example, tap loop: 141.20 → 142.89 MB; scroll loop: 141.47 → 142.92 → 140.44 MB, settling at 140.11 MB post-low-memory). Across earlier Flutter 3.47 runs with a larger probe bundle (26.4 MB vs 23.1 MB kernel), readings were 145.6–148.3 MB, reflecting a ~4–5 MB baseline shift between toolchain builds. It moves by up to about 2 MB between frames in either direction, so treat it as ≈ 142 MB ± 2 for the current build. **This is a Mac process running a debug JIT engine with the full Dart compiler and VM service. It is not a watchOS memory measurement and says nothing about a release AOT build on a watch** |

**What this does not show.** It is a normal Mac process tagged as a watchOS Simulator binary: Mac CPU and memory, and a debug engine that JIT-compiles Dart (which a real watch will not allow). The stubs are zeroed data and unused Metal code never ran. It proves nothing about a source build, AOT, device memory, speed or App Review, and the patched binary must never be distributed.

**Facts from the engine source (pinned commit `371f77202a…`, Dart 3.14.0):**
- The build tool's target OS list is `android, ios, mac, linux, fuchsia, wasm, win, qnx`: no watchOS, and `--simulator` is iOS-only.
- `qnx` is the precedent for a new OS: arm64 only, Skia GPU backends off (software-only). The embedder's software surface is on by default.
- `fml/build_config.h` treats watchOS as iOS (`TARGET_OS_IPHONE` is 1 there). 49 of 55 sampled `fml` files compile for watchOS with C++20; the other 6 stopped on `third_party` headers outside the sample.
- Dart's `tools/gn.py` accepts `watchos` / `watchos_simulator`. **Whether the Dart VM builds and runs on watchOS is not verified.**
- The watchOS SDK exports `CAMetalLayer`, `CGBitmapContextCreate`, `CTFontCreateWithName`, but not `MTLCreateSystemDefaultDevice` or `IOSurfaceCreate`.

**Proposed route (untested):**
0. *Build tool:* add `watchos` / `watchos_simulator` target OS, SDK and deployment-target variables; start with the arm64 simulator.
1. *Software-only config modelled on `qnx`:* turn off GL, Metal, Vulkan, Ganesh, Graphite; keep `shell_enable_software`; stop the macOS-host rule that forces Metal on.
2. *OS layers:* `fml` (largely compiles), `third_party` (likely the most small edits), the Dart VM and `gen_snapshot` for a watchOS AOT target, and the iOS-style text layer (not the macOS `NSFont` one).
3. *Host:* Swift over `embedder.h`: `FlutterEngineRun`, software present callback into `WatchFrameStore`/`WatchFrameView`, `FlutterEngineSendPointerEvent` for touch (the engine side of Crown input—a synthetic scroll signal—is verified in the smoke test; capturing SwiftUI `.digitalCrownRotation` and mapping it to that signal is untested).
4. *Packaging:* flat watchOS framework with `Info.plist`; AOT snapshot via the embedder's AOT options; `icudtl.dat` bundled.
5. *Device:* measure binary size, memory and frame time on real watches (watchOS 27+, `arm64`-only).

**Policy.** Release/AOT only (debug engine, JIT and hot reload are development tools); public Apple APIs only (not yet audited); App Review Guideline 2.5.2 requires apps to be self-contained. The Flutter team does not support custom engine builds long-term, so a port is community-maintained unless upstreamed.

**Smallest further tests:** compile all of `fml` with the missing `third_party` headers · build only the Dart VM for `watchos_simulator` · full from-source engine build on a larger or self-hosted machine (a hosted runner with 3 cores, 7 GB RAM and a 6 h cap is not expected to suffice) · finally a real watch.

---

## Open Questions

1. **Headless frame capture.** Can a stock app produce frames on the dev machine without a visible window, with `toImage` at an acceptable rate? *Answered for `flutter test` on a macOS runner: yes.* Open: a hidden desktop window or `flutter-tester` process, and real GPU readback timing.
2. **Reconnection.** watchOS may suspend or dim foreground apps in always-on / wrist-down states. Define a reconnect strategy plus a full-frame resync (`captureNow()`) after a drop.
3. **`save`/`restore` canvas state** *(Path B (`docs/display-list-research.md`))*: SwiftUI Canvas has no direct `saveGState`; needs nested canvases or manual transform tracking.
4. **Text measurement parity** *(Path B (`docs/display-list-research.md`))*: bundled font metrics must match on-device rendering. Not applicable where Flutter rasterizes its own text.
5. **Asset bundling.** How does `flutter build watchos` know which images to bake into the `.watchapp`?
6. **Xcode project structure.** Where does the Swift runtime layer live relative to the Flutter project tree?
7. **Paint hook** *(Path B (`docs/display-list-research.md`))*: `PaintingContext` creates its own canvases and recorded `Picture`s are opaque, so subclassing `Canvas` intercepts nothing. A hook needs a custom `PaintingContext` / `PipelineOwner` / `RenderView` stack, or primitives that paint through their own API.
8. **Device floor and ABI.** *Resolved:* Set to watchOS 27+ (SE 3, Series 9+, Ultra 2+; `arm64`-only per toolchains), dropping Series 6–8, SE 2, and Ultra 1 (`arm64_32`) to avoid the ILP32 Dart AOT porting risk.
9. **Engine on watchOS.** *Shown here:* patched official debug engine code runs in a Simulator process. *Third-party evidence (unverified by us):* flutter-watchos reports the engine running on the watch with App Store apps (see Related Work). *Open:* an open-source recipe, whether the Dart VM builds and runs on watchOS, AOT on a device, binary size, memory, and App Review acceptance.
10. **Simulator networking / CI.** *Answered for Simulator loopback: yes.* The watchOS Simulator allows `ws://` loopback and hosted runners ship a watchOS runtime. On physical watches, Apple TN3135 blocks `URLSessionWebSocketTask` and `NWBrowser` outside active audio/VoIP sessions (`ws://` is Simulator-only).
11. **Frame-transport budget.** Which mix of pixel ratio, diffs, zlib and capture-rate cap fits 30 fps, over loopback and then real Wi-Fi? *Partly answered (sustained loopback test):* zlib gives ≈ 1 KB / 3.9 KB per mostly-static frame. Open: busy content, real Wi-Fi, decode time on a watch.
12. **GPU rendering, CPU rasterization and API compliance.** flutter-watchos reports Impeller on Metal through an SDK overlay that supplies a Metal framework the watchOS SDK does not declare. Whether Apple accepts that is unknown here, so this design stays on the public-API software path. Open: whether a public-API route to GPU rasterization (`FlutterMetalRendererConfig` or `SpriteView` / `SKMutableTexture`) passes App Store Connect validation, pinning Skia's minimal CPU subset behind `FlutterSoftwareRendererConfig` if Skia is removed upstream, and the frame-time and battery cost of CPU rasterization on real devices.

---

## Build Phases

**Phase 0: `watchos_ui` specification**
- [ ] Full widget catalog and `WatchConstraintProfile` for all five screen sizes (41, 42, 45, 46, 49 mm)
- [ ] Verify HIG numbers against the current HIG and cite sources
- [x] Decide the device floor (watchOS 27+ / SE 3, Series 9+, Ultra 2+; verify SE 3 40/44 mm HIG specs)
- [ ] Navigation model and Digital Crown scroll-physics contract

**Phase 0.5: CI validation spikes**
- [x] macOS workflow with a watchOS Simulator destination
- [x] Simulator CI spikes: SwiftUI renderer, headless Dart capture, loopback WebSocket, Path B display-list fixtures
- [ ] Engine-on-watchOS feasibility (retagged smoke test passes in Simulator; from-source build needs a larger machine)

**Phase 1: Proof of concept (dev mode)**
- [ ] `WatchHost` + `WatchFrameStreamer`, Dart WebSocket server, SwiftUI frame view, watchOS listener
- [ ] Tap round trip: `WatchInputInjector` → `setState` → new frame
- [ ] **Milestone 1a:** `WatchText` + `WatchButton` in the Simulator driven by a real macOS desktop host, with live hot reload and sustained multi-frame animation streaming
- [ ] **Milestone 1b (experimental / contributor-gated):** HTTP (`URLSession.bytes`) or `WatchConnectivity` preview on a real watch
- [ ] Measure and publish frame time, bandwidth and tap-to-photon latency

**Phase 2: Debug tooling**
- [ ] `ConstraintValidator` (render tree → violations), debug overlay, preview viewport, send gate that blocks critical violations

**Phase 3: Production, engine on device**
- [ ] Feasibility (Open Question 9), Swift embedder host, watchOS AOT build targets, framework linkage
- [ ] Binary size within watchOS limits; memory and frame times per device with Instruments (oldest supported watch, a recent Series, Ultra)
- [ ] Public-API audit: imported symbols of the final binary all resolve against the public watchOS SDK; no stubs, overlays or private frameworks
- [ ] `flutter build watchos` produces a `.watchapp`

**Phase 4: Display-list / zero-copy research (optional, Path B (`docs/display-list-research.md`))**
- [ ] Solve the paint hook (Open Question 7), Dart FFI bridge, `ZeroCopyCanvas` + `WatchRenderStore`, haptic/event callbacks
- [ ] Measure allocation, frame drops and FFI cost against the hypotheses in Path B (`docs/display-list-research.md`)

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

## References

- Flutter custom engine embedders: https://github.com/flutter/flutter/wiki/Custom-Flutter-Engine-Embedders
- Embedder API (engine lives in the `flutter/flutter` monorepo; verify path): https://github.com/flutter/flutter/blob/main/engine/src/flutter/shell/platform/embedder/embedder.h
- `flutter_pi` (reference community embedder): https://github.com/ardera/flutter-pi
- Dart FFI: https://dart.dev/interop/c-interop
- Apple watchOS HIG: https://developer.apple.com/design/human-interface-guidelines/watchos
- Apple Support, *Update your Apple Watch* (watchOS 27 compatibility): https://support.apple.com/en-ca/118574
- Apple watchOS 27 overview: https://www.apple.com/ca/os/watchos-27/
- Apple Technical Note TN3135, *Low-level networking on watchOS*: https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos
- SwiftUI Canvas: https://developer.apple.com/documentation/swiftui/canvas · GraphicsContext: https://developer.apple.com/documentation/swiftui/graphicscontext
- flutter-watchos: https://flutterwatch.dev (docs: https://github.com/flutterwatch/flutter-watchos/blob/main/doc/get-started.md) · https://github.com/flutterwatch/flutter-watchos · article: https://itnext.io/yes-you-can-build-apple-watch-apps-with-flutter-now-909c3dc84804
- GitHub-hosted macOS runners: https://docs.github.com/en/actions/using-github-hosted-runners/using-github-hosted-runners/about-github-hosted-runners

