# Flutter for watchOS
### Architecture & MVP Strategy Document
> A Flutter platform embedder targeting standalone Apple Watch

**Status:** Draft — partially validated: 25 automated CI checks pass on a macOS runner with the watchOS Simulator, including an end-to-end run of the whole dev loop (see Validation Results). Not yet validated: the Flutter engine on watchOS, on-device memory and speed, real-network behaviour.
**Minimum target:** watchOS 10+ / Apple Watch Series 4+ (device floor under review — see Open Questions)
**Last updated:** November 2026
**Version:** v7.2

---

## Vision

Build a system that allows Flutter developers to write widgets in Dart — exactly as they do today — and have them rendered natively on a standalone Apple Watch, with no iPhone required. Flutter's own engine rasterizes every frame; SwiftUI `Canvas` is the presentation surface that puts those pixels on the watch.

Instead of forcing standard mobile widgets (Material / Cupertino) onto a watch screen, this platform introduces a bespoke `watchos_ui` package. This widget catalog enforces Apple's Human Interface Guidelines (HIG) by design, ensuring correct layout math, optimal performance, and native-feeling interactions from the start.

---

## Core Constraints — watchOS Reality

| Constraint | Detail |
|---|---|
| No Metal directly | `MTKView` unavailable on watchOS — GPU access only indirectly via SpriteKit / SwiftUI Canvas |
| No UIKit | watchOS uses WatchKit + SwiftUI only |
| Memory limit | ~30 MB conservative target — varies by watch generation; validate per SKU with Instruments |
| No JIT on device | Apple prohibits JIT on physical hardware — on-device Dart must be AOT-compiled, so there is no on-device hot reload. AOT output still carries a Dart runtime (GC etc.) |
| No dynamic code execution | Apple prohibits downloading and running code at runtime |
| Background process limits | OS suspends background tasks aggressively — WebSocket listener must stay in foreground session |
| Screen sizes | 41mm → 176×215pt / 45mm → 198×242pt / 49mm Ultra → 205×251pt |
| Pointer width (unverified) | Some older watches are believed to use the `arm64_32` (ILP32) ABI — verify Dart AOT / engine support before fixing the device floor |

---

## Architecture Decision — One Primary Path

Earlier drafts accumulated two incompatible answers to "who draws the pixels?". They cannot be mixed in one pipeline, so this document now picks one and quarantines the other.

| | **Path A — Engine rasterizes (PRIMARY)** | **Path B — Display list (Appendix A, research only)** |
|---|---|---|
| Who rasterizes | The Flutter engine (software / custom-compositor path) | SwiftUI `Canvas` executes drawing opcodes |
| What crosses the boundary | Dev: rendered frames over WebSocket · Prod: engine present-callback pixels, in-process | Draw commands (protobuf, or binary slabs in shared memory) |
| Custom wire protocol | Frame transport only | Full opcode set + `ZeroCopyCanvas` |
| Role of `watchos_ui` | HIG / constraint layer enforced by the validator — widgets are ordinary Flutter widgets | Hard requirement — only widgets that emit opcodes can render |
| Needs a paint hook | No | Yes (Open Question 7) |
| Needs the Flutter engine | Yes | No — but then it is not Flutter widgets (custom `RenderObject` tree or custom framework) |
| Phases | 1–3 | 4 (optional) |

**Decision:** Path A is the architecture.

1. `watchos_ui` restricts the widget set for HIG and performance reasons — **not** because the rasterizer can only draw a handful of primitives. The engine rasterizes whatever Flutter paints.
2. The `DisplayList` protobuf schema, `WatchCanvas` interceptor, `ZeroCopyCanvas`, `WatchRenderStore` slab state machine and display-list renderer all live in **Appendix A**. Nothing in Phases 1–3 depends on them.
3. Any new section must say which path it belongs to. Text that mixes the two is a defect.

---

## Rendering Target

**SwiftUI `Canvas`**, redrawn when a new frame is published — the closest equivalent to Flutter's `CustomPainter` on watchOS. Available since watchOS 8, stable on watchOS 10+.

```swift
// Redraw is driven by published state (a new frame arrived), not by a free-running timer.
Canvas { context, size in
    // Primary path: draw the latest rasterized frame (CGImage)
    // Appendix A only: interpret display-list commands
}
```

| API | Verdict |
|---|---|
| SwiftUI Canvas | ✅ Chosen — full 2D, GPU-indirect, redraws on state change (add `TimelineView` only for continuous local animation) |
| SwiftUI Path / Shape | ⚠️ Vector only, no frame loop |
| SpriteKit | ⚠️ Viable but heavier, game-oriented |
| Core Graphics | ⚠️ CPU-only rasterizer, no animation loop |
| Metal / MTKView | ❌ Not available on watchOS |

> ⚠️ `TimelineView(.animation)` ticks continuously (up to the display refresh rate) and keeps the CPU/GPU busy even when nothing changed — a real battery cost on a watch. It is not used here: every published frame already invalidates the view. In the primary path the Canvas only draws the latest received frame; the command-interpreter role belongs to Appendix A.

---

## The `watchos_ui` Package

> ⚠️ This package must be **specified before implementation begins** — every other layer (frame streamer, canvas interceptor, constraint validator, SwiftUI renderer) depends on knowing the exact widget surface area.

Rather than allowing developers to reach for any Flutter widget — most of which will fail or render incorrectly on a watch — `watchos_ui` exposes only what the watch can correctly render.

> **Role under the primary architecture (Path A):** the engine rasterizes everything Flutter paints, so this package is a HIG and performance constraint layer — enforced by the Debug Interceptor and lints — not a limit imposed by the renderer. `WatchText` and `WatchButton` are ordinary widgets composed from real Flutter widgets. They only need custom `RenderObject`s that emit draw opcodes under the display-list path (Appendix A).

### Root Widget — `WatchApp`

Replaces `MaterialApp`. Enforces:
- Pure black (`#000000`) background — critical for OLED power savings
- Default SF Compact system typography
- Removal of mobile-specific gesture recognizers (no long-press menus, no Material ripple)
- watchOS 10+ navigation paradigm (page-based, not hierarchical)

### Layout Primitives

Flutter's `Row`, `Column`, `Stack`, `Flex`, `Padding`, and `SizedBox` are kept as-is. They compute spatial math only and produce no paint calls — safe to use without modification.

### Visual Primitives

| Widget | Display-list mapping (Appendix A only) | Constraint enforced | HIG Rule |
|---|---|---|---|
| `WatchButton` | `drawRRect` | Minimum 44×44pt touch target | Apple HIG §Touch Targets |
| `WatchText` | `drawText` | Font 14–34pt, SF Compact only, no inline spans | Apple HIG §Typography |
| `WatchProgressRing` | `drawPath` (arc) | Standard activity ring proportions | Apple HIG §Progress |
| `WatchDivider` | `drawLine` | 1pt, system gray | Apple HIG §Layout |
| `WatchImage` | `drawImage` | Must reference pre-bundled asset | Memory constraint |

> ⚠️ Numeric limits (44×44pt touch target, 14–34pt font range) and HIG section references are provisional until verified against the current HIG text.

### Navigation — watchOS 10+ Only

Locked to watchOS 10+ paradigms:

- **`WatchPageScaffold`** — horizontal page swiping (mirrors Apple Workout / Activity apps)
- **`WatchListScaffold`** — vertical scrollable list driven by Digital Crown rotation

> ⚠️ `WatchHierarchicalRouter` (push/pop navigation) is intentionally excluded from v0 as a scope decision. Hierarchical navigation (`NavigationStack`) still exists on watchOS 10, which also added vertical `TabView` and `NavigationSplitView` — page- and list-based navigation simply fits the watch best.

### Digital Crown Input

A custom `WatchScrollPhysics` listens to Crown rotational delta events rather than finger swipes to power `WatchListScaffold` scrolling. Each threshold tick triggers a haptic feedback response via the Taptic Engine. On the watch side, rotation values come from SwiftUI's `.digitalCrownRotation(...)`.

---

## Two-Mode Architecture

> ⚠️ The Flutter framework depends on `dart:ui`, which is implemented by the Flutter **engine**, not by Dart itself. Both modes therefore keep a real Flutter engine in the loop: on the developer's machine in development mode, on the watch in production mode.

### Mode 1 — Development Mode

The real Flutter app runs on the developer's machine (stock Dart VM, stock hot reload) and handles all layout, state, and rasterization. A `WatchHost` wrapper captures each rendered frame using public Flutter APIs and streams it to the watch over a local WebSocket. Input events flow back and are injected through `GestureBinding`.

```
[ Developer Machine ]
  Flutter app (stock Dart VM)
    - Full Flutter layout + paint pipeline
    - Widget tree → RenderObject tree
    - WatchHost: RepaintBoundary sized to the target profile
  ↓ WatchFrameStreamer (captures a frame after each produced frame)
  ↓ Debug Interceptor (validates render tree against WatchConstraintProfile)
  ↓ only clean frames pass
  WebSocket Server
  ↓ WiFi

[ Apple Watch — Standalone ]
  WebSocket Listener (foreground session)
  → Frame decoder
  → SwiftUI Canvas (redraws when a new frame is published)
  ↑ InputEvent → WebSocket → WatchInputInjector → GestureBinding → setState() → new frame
```

**Two development hosts** (both are Mode 1 — the Mac-side code is identical):

- **1a — watchOS Simulator (default).** The watch client runs in the Xcode watchOS Simulator on the same Mac and connects to the Dart server over loopback. No hardware and no Wi-Fi in the path, and it can run in CI on a macOS runner. Assumption to verify: the Simulator can reach the host's `localhost` (Open Question 10).
- **1b — Physical watch over Wi-Fi.** Adds real network latency, foreground-session suspension, and the real display. This is the *second* milestone, not the first.

**Developer hot reload cycle:**
1. Write `watchos_ui` widgets in VSCode
2. Save → Dart VM hot reloads (~milliseconds)
3. Flutter produces a new frame
4. Debug Interceptor validates constraints
5. Clean frame pushed to watch over WebSocket (~100–200ms round trip — target, unmeasured)
6. User interacts with watch → event flows back → injected → `setState` → repeat from 3

> ✅ A **display-list mode** (vector draw commands instead of frames — see Appendix A) remains documented as a research alternative. It needs a working paint hook (Open Question 7) and is not required for the MVP.

### Mode 2 — Production Mode

Dart AOT produces the app snapshot. It is linked with a **Flutter engine built for watchOS** and a Swift host that drives the engine through Flutter's embedder API (`embedder.h`) — the same mechanism community embedders such as `flutter_pi` use. The engine rasterizes through a software / custom-compositor path; the Swift host hands the resulting pixels to SwiftUI. No server, no network required at runtime.

```
[ Build Pipeline — flutter build watchos ]
  Dart source + watchos_ui widgets
  → gen_snapshot (AOT) → app snapshot (watchOS target)
  → Linked with:
       Flutter engine built for watchOS
       Swift host: FlutterEngineRun, present callback, input forwarding
       Asset bundle (fonts, images pre-baked)
  → .watchapp bundle → App Store

[ At Runtime on Watch ]
  Swift host starts the engine with the AOT snapshot — no JIT, no server
  Engine renders → present callback (pixel buffer)
  Swift host → SwiftUI Canvas / Image at native watch resolution
  SwiftUI input (tap, Crown) → FlutterEngineSendPointerEvent
  ✅ Fully offline   ✅ Fully standalone   ✅ App Store compliant (to be validated)
```

**What must be true for this mode (all unverified):**
- A Flutter engine can be built for watchOS
- A renderer usable on watchOS is available through the embedder renderer configs (software or custom compositor)
- Engine + framework + app fit the memory budget of the target watches
- Frame times are acceptable on real hardware
- The result passes App Store review

| | Development Mode | Production Mode |
|---|---|---|
| Flutter engine | Runs on developer Mac (stock Dart VM) | Runs on the watch (AOT, via embedder API) |
| Widget logic | JIT on the Mac | Native ARM64 (AOT) |
| Output to watch | Rendered frames over WebSocket | Engine present callback → SwiftUI (in-process) |
| Server required | Yes (local) | No |
| Hot reload | ✅ (watch driven from the Mac) | ❌ (no JIT on device) |
| App Store | ❌ | ✅ (to be validated) |
| Standalone | Needs Mac nearby | Fully standalone |

### What Each Mode Actually Validates

| Question | 1a — Simulator | 1b — Physical watch (Wi-Fi) | Mode 2 — Engine on device |
|---|---|---|---|
| Does the app's Dart logic and layout work? | ✅ | ✅ | ✅ |
| Does the watch-side Swift renderer compile and draw? | ✅ | ✅ | ✅ (host layer) |
| Is the Flutter engine running on watchOS? | ❌ | ❌ | ✅ |
| Does it fit the watch memory ceiling? | ❌ Simulator uses Mac memory | ⚠️ Viewer footprint only — no engine | ✅ |
| Real frame times and battery? | ❌ | ⚠️ Viewer decode + draw only | ✅ |
| Real network behaviour (latency, suspension, reconnect)? | ❌ Loopback | ✅ | n/a |
| Pixel parity (fonts, colour, scaling)? | ❌ Rendered on the Mac | ❌ Rendered on the Mac | ✅ |

> ⚠️ Mode 1 is a layout-and-logic loop plus a remote display. It does **not** exercise the watchOS engine, memory ceiling, or performance. Measurements taken in Mode 1 must not be cited as evidence for production memory, speed, or visual parity — those claims need Mode 2 (Phase 3).

---

## The Frame Streamer — Dart Side

Default development path. Captures each produced frame from inside the running Flutter app using only public APIs — no engine modification and no `Canvas` subclassing — and injects input events back through the gesture system.

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

> ✅ **Verified (check S1):** the real streamer captures frames and the real injector's tap changes the next one. The check also showed that after `start()` nothing is captured until Flutter next produces a frame, and an idle app produces none. `captureNow()` (new in v7.1, covered by check S7) closes that gap: call it whenever a client connects or asks for a resync (Open Question 2).

### Known Risks

| Risk | Notes |
|---|---|
| `toImage` + `toByteData` cost | Each capture is an asynchronous GPU→CPU readback plus a full-frame copy — the likely frame-rate ceiling regardless of network. Headless capture works (checks P2, S1), but those timings come from the test renderer, which has no real GPU, so real readback cost is still unmeasured |
| Bandwidth | Raw RGBA is ≈ 192 KB per frame at pixelRatio 1.0 and ≈ 767 KB at 2.0 — see the arithmetic below. Measured: full-frame zlib shrank the test frames to ≈ 1 KB / 3.9 KB (≈ 180–195×) — but those frames are mostly static, so worst-case content is still unmeasured (see Validation Results) |
| Dev ≠ prod coverage | Mode 1 does not exercise the watchOS engine, memory ceiling, or performance — see "What Each Mode Actually Validates" |
| Input latency | A WiFi round trip makes interaction feel laggy — acceptable for development, not for end users |
| Headless host | The app must produce frames on the dev machine without a visible window (hidden desktop window or `flutter-tester`) — works in `flutter test` on a macOS runner (checks P2, S1); a real hidden desktop window or `flutter-tester` process is still untested (Open Question 1) |
| Rendering mismatch | Pixels rendered on the dev machine are not guaranteed to match on-device rendering (fonts, scaling, colour) |

#### Bandwidth arithmetic (uncompressed RGBA, 4 bytes per pixel)

| Screen | Pixel ratio | Frame size | At 30 fps |
|---|---|---|---|
| 45mm (198×242 pt) | 1.0 (198×242 px) | 191,664 B ≈ 192 KB | ≈ 5.7 MB/s |
| 45mm (198×242 pt) | 2.0 (396×484 px) | 766,656 B ≈ 767 KB | ≈ 23 MB/s |

> v6 quoted ≈ 192 KB per frame while the streamer defaulted to `pixelRatio: 2.0`; those do not match. 192 KB is the 1.0 figure, and the 2.0 default was 4× larger. The default is now 1.0.

Candidate mitigations (none measured):

1. Default to `pixelRatio` 1.0 in development; raise it only for fidelity checks.
2. Send only on change — already the case, because the persistent frame callback fires only when Flutter produces a frame.
3. Diff against the previous frame and send only changed tiles (dirty rectangles). Measured for XOR-delta + zlib: only ≈ 11–12% smaller than plain zlib, and ≈ 20–40× slower to decode in a debug build — not worth it as a first step.
4. Compress with zlib — measured ≈ 180–195× smaller on mostly-static test frames (≈ 31 KB/s at 1.0 and ≈ 118 KB/s at 2.0 for 30 fps); busy content will compress worse.
5. Cap the capture rate (for example 15 fps) in development; the readback is the bottleneck anyway.
6. Long term: avoid GPU readback entirely by using Mode 2's software present callback.

Loopback (host 1a) removes the Wi-Fi limit but not the readback cost, so measure them separately (spike S1 for capture, S2 for transport).

> ✅ Because Flutter rasterizes its own text in this mode, there is no Dart-vs-Core-Text layout parity problem here — that question applies only to the display-list research path.

---

## The Debug Interceptor

Sits between the frame source and the WebSocket sender. Validates every frame against the `WatchConstraintProfile` before it reaches the watch. In pixel-stream mode it inspects the **render tree** (sizes, touch targets, font sizes), which is richer than inspecting a draw stream. Critical violations block frame transmission.

### Constraint Profiles

```dart
class WatchConstraintProfile {
  final double screenWidth;
  final double screenHeight;
  final int    maxDrawCallsPerFrame;
  final int    maxPayloadBytes;
  final double minTouchTarget;      // 44pt Apple HIG
  final double minFontSize;         // 14pt
  final double maxFontSize;         // 34pt
  final double crownExclusionZone;

  static const mm41 = WatchConstraintProfile(screenWidth: 176, screenHeight: 215, ...);
  static const mm45 = WatchConstraintProfile(screenWidth: 198, screenHeight: 242, ...);
  static const mm49 = WatchConstraintProfile(screenWidth: 205, screenHeight: 251, ...);
}
```

> ⚠️ Numeric limits in the profile (touch target, font range) are provisional until verified against the current HIG.

> ℹ️ `maxDrawCallsPerFrame` and the `drawCallBudgetExceeded` violation only make sense when a draw stream exists (Appendix A). Under the primary path the equivalent signals come from the render tree (render-object count, layer count, capture time) and `maxPayloadBytes` applies to the transported frame.

### Violation Types

| Category | Violation | Severity | Description |
|---|---|---|---|
| Layout | `horizontalOverflow` | 🔴 Critical | Widget wider than screen width |
| Layout | `verticalOverflow` | 🔴 Critical | Widget taller than screen height |
| Layout | `touchTargetTooSmall` | 🔴 Critical | Interactive area < 44×44pt (HIG) |
| Layout | `safeAreaViolation` | 🔴 Critical | Content outside safe display area |
| Typography | `fontTooSmall` | 🟡 Warning | fontSize < 14pt — unreadable on watch |
| Typography | `fontTooLarge` | 🟡 Warning | fontSize > 34pt — inappropriate scale |
| Typography | `textClipped` | 🟡 Warning | Text truncated or overflowing bounds |
| Performance | `drawCallBudgetExceeded` | 🟡 Warning | Too many commands per frame |
| Performance | `payloadTooBig` | 🟡 Warning | Frame exceeds bandwidth budget |
| HIG | `crownZoneViolation` | 🟡 Warning | Interactive content too close to Crown edge |

---

## The SwiftUI Renderer — Watch Side

In pixel-stream mode the renderer only draws the latest received frame. The display-list renderer (Appendix A.5) belongs to the research path.

### Pixel-Stream Renderer

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

> ✅ **Verified (checks S3, S4):** the frame is stretched to fill the view, so it fills the screen whatever `pixelRatio` the Dart side captured at. That is why v7.0's `scale` field had no effect and was removed. Stretching is only correct when the captured frame has the same aspect ratio as the view: capture a boundary sized to the watch's logical screen, because a mismatched aspect ratio would distort the image. Publishing a new frame redraws the view with no `TimelineView` (shown with an off-screen `ImageRenderer`, not yet on a live screen).

---

## Event & Haptics Round-Trip

All user input on the watch flows back to Dart. Dart can also trigger Taptic Engine haptics in response to state changes.

```
[ Watch — User spins Digital Crown ]
  SwiftUI .digitalCrownRotation captures rotational delta
  InputEvent { type: CROWN, delta: 0.5 }
  → WebSocket (dev) or engine pointer / scroll event (prod)
  → Dart: WatchScrollPhysics calculates list translation
  → Determines if delta crosses haptic tick threshold
  → Produces new frame + InputEvent { type: HAPTIC_TRIGGER }
  → Watch: SwiftUI Canvas repaints
  → Watch: WKInterfaceDevice.current().play(.click)  ← Taptic Engine fires

[ Watch — User taps at (x: 45, y: 120) ]
  InputEvent { type: TAP, x: 45, y: 120 }
  → (dev) WatchInputInjector → GestureBinding → hit-test against current widget tree
  → GestureDetector callback fires
  → setState() → new widget tree → new frame → pushed to watch
```

---

## MVP — Proof of Concept Strategy

> **Goal:** produce one video of a Flutter-authored `WatchText` and `WatchButton` rendering on a real Apple Watch, driven by Dart code, with hot reload working — then share it with the Flutter team and community as a measured demonstration of the architecture.

### Why This MVP Is the Right Target

Attention is earned by showing something running, not by showing a complete framework. `flutter_pi` earned its place in the Flutter conversation by demonstrating a single Flutter app running on a Raspberry Pi. The equivalent milestone here is a single Flutter widget rendering on a real Apple Watch, driven by Dart, with hot reload. Other toolchains now target the same platform (see Related Work), so the contribution of this MVP is a *measured* demonstration of the pixel-stream approach and its trade-offs — not a first.

Everything else — the full widget catalog, the constraint validator, the production build, the desktop preview viewport — is polish on a proof that does not yet exist. The desktop preview is explicitly excluded from the MVP: it improves developer experience but does not prove the core claim and belongs in Phase 2.

### MVP Scope — What Gets Built

- `WatchHost` + `WatchFrameStreamer` — captures frames from a `RepaintBoundary` using public Flutter APIs
- `WatchText` and `WatchButton` — two widgets, nothing more
- Minimal frame transport — WebSocket, raw or simply compressed RGBA
- WebSocket listener + SwiftUI Canvas frame view (Swift) — receives and draws the latest frame on watch
- One tap event round-trip — tap `WatchButton`, injected via `GestureBinding`, `setState`, button changes color
- Hot reload — save Dart file, watch updates; ~200ms on local WiFi is the target to test

### MVP Scope — What Gets Excluded

- Desktop preview viewport — deferred to Phase 2
- Full `watchos_ui` widget catalog — only `WatchText` and `WatchButton` for MVP
- Dart FFI bridge and display-list mode — deferred to Phase 4 research
- Constraint validator — not required to prove rendering works
- Production build (engine on device) — deferred to Phase 3
- App Store submission — deferred to Phase 5

### MVP Build Steps

1. Prove headless frame capture on the dev machine — a Flutter app producing frames with no visible window, captured with `RepaintBoundary.toImage` (Open Question 1)
2. Implement `WatchText` and `WatchButton` as `watchos_ui` widgets on the real Flutter framework
3. Build Dart WebSocket server — `WatchFrameStreamer` transmits a frame on each produced Flutter frame
4. Build watchOS Xcode project — SwiftUI Canvas with WebSocket listener and frame decoder
5. Wire tap event round-trip — watch sends `TAP` `InputEvent` back to Dart, `WatchInputInjector` triggers `setState`
6. Verify hot reload — save Dart file, watch updates; record measured latency (target under 300ms on local WiFi)
7. Record demo video — screen recording of Mac + watch side by side, hot reload visible

> ✅ Steps 1–6 can be built and CI-verified against the watchOS Simulator (host 1a) with no hardware. Step 7's real-watch recording is a separate hardware milestone (host 1b).

### MVP Timeline Estimate

Not estimated until Open Question 1 is answered. The estimate depends on whether headless frame capture works at an acceptable rate, so any number before step 1 completes would be a guess.

### How to Present the MVP to the Flutter Team

- **GitHub repository** — clean README, architecture diagram, MIT license, demo video linked
- **Flutter GitHub issue** — filed against `flutter/flutter`, demo linked as evidence, architecture document attached, framed as "here is a working experiment, here are the measurements, here is what a full implementation would look like"
- **Flutter Discord + r/FlutterDev** — demo video with honest framing of what is proved and what remains open
- **Medium or dev.to article** — "Flutter on watchOS: a working proof of concept and what it would take to go further"

> ✅ The goal of the MVP is not to ship a framework. It is to make the argument concrete and visual — and to publish honest measurements, including the unfavourable ones.

---

## Resolved Design Decisions

| Question | Decision | Rationale |
|---|---|---|
| Layout | Full Flutter layout runs Dart-side (dev machine in development, on the watch in production); in development only rendered output crosses the wire | Keeps watch dumb, Dart authoritative |
| Animations | Run inside Flutter (frames streamed in development, engine on device in production); local SwiftUI interpolation applies only to the display-list research path | Prevents 60fps frame floods over the wire |
| Fonts | Development and production: Flutter rasterizes its own text — no cross-renderer parity needed. Display-list research path: bundled font-metrics tables, SF Compact rendered on the watch | Parity is unproven for the research path (Open Question 4) |
| Images | Pre-bundled in `.watchapp` at build time | Respects memory limits; no runtime fetch latency |
| State management | Any Dart state manager runs entirely Dart-side | No changes needed to existing state tooling |
| Frame rate | 30fps target (33ms budget end-to-end) — hypothesis, revisit after measurement | Realistic given capture + WiFi; to be validated |
| Navigation | `WatchPageScaffold` + `WatchListScaffold` only | Scope decision — page/list fits the watch best; hierarchical push/pop excluded from v0 |
| Dart ↔ Swift interop | Dart FFI with `@_cdecl` Swift bridge (display-list research path) | swiftgen removed — unstable, ~33 downloads, adds unnecessary abstraction |
| Production runtime | Real Flutter engine on device via embedder API | Framework requires `dart:ui`, which the engine implements; a no-engine build can't run Flutter widgets |
| Rendering architecture | Engine rasterizes (Path A). Display-list opcodes (Path B) are a separate research architecture in Appendix A | Mixing them leaves two renderers and unused protocols — see Architecture Decision |
| Dev loop host | watchOS Simulator over loopback first; physical watch second | No hardware needed to start; Simulator results do not cover memory, speed, or parity |
| Frame transport encoding (dev mode) | Full-frame raw-deflate (zlib) by default; XOR-delta rejected for now | Measured ≈ 180–195× smaller than raw, and delta saved only ≈ 11–12% more while decoding ≈ 20–40× slower (debug build). Provisional until worst-case content is measured |
| Late-joining client | Call `WatchFrameStreamer.captureNow()` on connect / resync | An idle app produces no frames — found by check S1, verified by S7 and E1 |
| Input coordinates | The watch sends taps in logical points of its own screen; the host adds the app's screen origin before injecting | Verified end to end at `pixelRatio` 1.0 (E1). At 2.0 the watch must divide frame-pixel coordinates by the ratio — untested |

---

## Validation Strategy — Compile Before You Specify

> These checks run in CI on GitHub-hosted macOS runners with the watchOS Simulator — no Mac or Apple Watch needed (free for public repositories at the time of writing — verify current terms and limits). v7.1 records their first results. The runnable proofs live in `watchos-proofs/`; the spec's own code blocks are extracted from this file and tested automatically. The spike IDs S0–S4 below are planning milestones; the individual check IDs (F0, P0–P9, A1–A4, X1–X2, S0–S7) are the steps of `proofs.yml` and are listed under Validation Results.

**Rule:** a code section counts as specified only once its snippet compiles in CI. Any revision that changes code must update the status table below.

### Validation Spikes

| ID | Spike | Pass criteria | Status |
|---|---|---|---|
| S0 | Swift compile + unit tests of the watch-side renderer code | Builds for watchOS Simulator; tests pass; Canvas redraws once per published frame with no `TimelineView` | ✅ Done — checks P0, P4, P5, S0, S2–S6 |
| S1 | Dart: `WatchFrameStreamer` + `WatchInputInjector` under `flutter test` with no window | Non-empty RGBA captured from a `RepaintBoundary`; tap changes the next frame | ✅ Done — checks P2, P3, S1 (found the idle-app gap → `captureNow()`, check S7) |
| S2 | Loopback WebSocket: Dart server → watchOS Simulator client | Simulator connects; frames decode and draw; bytes/frame and fps logged (Open Questions 10, 11) | ✅ Done — checks P6, P9, E1 |
| S3 | Appendix A only: wire format, mailbox, symbol lookup | Golden bytes identical; alignment and padding cases pass; text at `.topLeading` | ✅ Done with a stand-in writer — checks A1–A4; the real `ZeroCopyCanvas` class is not yet tested |
| S4 | Engine on watchOS feasibility (Open Question 9) | Engine compiles for a watchOS target; a hello-world frame reaches the present callback | ⬜ Not started — probably needs a local or self-hosted machine |

The real workflow is `.github/workflows/proofs.yml` (it picks the newest available watch simulator at run time and prints one result sheet). The original planning sketch is kept for reference:

```yaml
# .github/workflows/watchos-spikes.yml
name: watchos-spikes
on: [push, pull_request]
jobs:
  swift-watchos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: xcrun simctl list runtimes   # confirm a watchOS runtime exists on this image
      - run: |
          xcodebuild test \
            -scheme WatchViewer \
            -destination 'platform=watchOS Simulator,name=<device from simctl list>'
  dart-frame-capture:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter test test/frame_capture_test.dart
```

### Code Verification Status

| Snippet | Location | Status | Checks |
|---|---|---|---|
| `WatchFrameStreamer` | The Frame Streamer | Tested — captures frames; idle-app gap found | P2, S1 |
| `WatchFrameStreamer.captureNow()` | The Frame Streamer | Tested — an idle app sends nothing by itself; `captureNow()` pushes exactly the current frame, and a connecting watch received it | S7, E1 |
| `WatchInputInjector` | The Frame Streamer | Tested — tap reaches a `GestureDetector`, next frame changes (no `viewId` needed in the test environment); a tap sent by the watch client was replayed through it | P3, S1, E1 |
| `WatchFrameStore`, `WatchFrameView` | The SwiftUI Renderer | Tested — draws stretched to fill; redraws on publish (off-screen renderer) | S0, S3, S4 |
| Whole dev loop: real streamer + injector ↔ WebSocket ↔ real `WatchFrameStore` / `WatchFrameView` | Mode 1 (Frame Streamer + SwiftUI Renderer) | Tested in the Simulator — host side ran inside `flutter test`, not a real desktop app | E1 |
| `Color(argb:)` | A.0 | Tested — channels and alpha | S2 |
| `WatchRenderStore`, `@_cdecl` slab API, `WatchCanvasView` (DRAW_RECT path) | A.2 | Tested — Dart-style bytes drawn; redraws on `frameTick` with no `TimelineView` (off-screen renderer) | S0, S5, S6 |
| `WatchCanvasView` DRAW_TEXT / DRAW_RRECT parsing | A.2 | Unverified | — |
| `ZeroCopyCanvas` (Dart writer) | A.2 | Unverified — the wire layout was checked with a stand-in writer, not this class | A3 |
| Mailbox state machine | A.2 | Tested (stand-in and the real store) | A2, S5 |
| `@_cdecl` symbol lookup | A.1 | Tested — found by `dlsym`; a Dart FFI call on watchOS is unverified | A4 |
| `WatchCanvas` interceptor | A.4 | Unverified — hook unresolved (Open Question 7) | — |

Status values progress Unverified → Compiles → Tested → Measured. "Tested" here means tested in the Simulator on a macOS runner, not on a watch.

### Validation Results

Latest CI run — macOS 26.7 runner, Xcode 26.6, watchOS 26.5 Simulator, Flutter 3.47, Dart 3.13. **25 of 25 checks passed.**

| Checks | What they showed |
|---|---|
| F0, P1, P0 | A hosted runner has a watchOS Simulator that boots; the Swift package builds for watchOS and runs XCTest there with no host app |
| P2 | Headless capture works: `RepaintBoundary.toImage` → raw RGBA, byte counts exactly as computed (191,664 B at 1.0; 766,656 B at 2.0) |
| P3, S1 | A tap injected through `GestureBinding` reaches a `GestureDetector` and the next frame changes; the real streamer captured frames, but only once a frame was scheduled |
| P4, P5 | RGBA → `CGImage` → SwiftUI `Canvas` draws the right pixels |
| P6 | Dart WebSocket server → watchOS client: a 192 KB frame down, a tap up, over loopback (first frame including the handshake: 166–232 ms) |
| S0, S2–S6 | The spec's own Swift compiles for watchOS; `Color(argb:)` is correct including alpha; the store and view draw, stretch to fill, and redraw on publish; the real slab API and `WatchCanvasView` draw Dart-written bytes and redraw on `frameTick` with no `TimelineView` |
| A1 | Text drawn at `(0,0)`: 47 lit pixels with `.topLeading` versus 10 with the default `.center` |
| A2–A4 | Mailbox logic; Dart-written bytes parsed correctly by Swift; a `@_cdecl` symbol is found by `dlsym` |
| S7 | An idle app produces no frames by itself (0 received); `captureNow()` pushes exactly the current one |
| E1 | **The whole dev loop, no stand-ins.** The real `WatchFrameStreamer` and `WatchInputInjector` (inside `flutter test`, playing the Mac) behind a real WebSocket, talking to a watchOS client that uses the real `WatchFrameStore` and `WatchFrameView`. On connect, `captureNow()` sent frame 0 and the view showed red; a tap at the watch-screen centre (99,121) was mapped into app coordinates and replayed; frame 1 arrived and the same live view showed green. Two frames in total, one tap |

**Sustained transport (check P9)** — 100 frames per configuration, ranges across six CI runs, over loopback in a debug build:

| Pixel ratio | Encoding | Bytes per frame | ms per frame | Decode ms per frame |
|---|---|---|---|---|
| 1.0 | raw | 191,668 | 0.5–1.2 | 0.0–0.1 |
| 1.0 | zlib | 1,047 | 0.9–1.9 | 0.8–1.7 |
| 1.0 | XOR-delta + zlib | 922 | 24.8–42.8 | 24.6–42.5 |
| 2.0 | raw | 766,660 | 1.5–7.0 | 0.1–0.2 |
| 2.0 | zlib | 3,935 | 3.2–8.2 | 3.1–7.9 |
| 2.0 | XOR-delta + zlib | 3,495 | 90.9–169.8 | 90.7–169.5 |

- Full-frame zlib made the test frames ≈ 180–195× smaller: ≈ 31 KB/s at 1.0 and ≈ 118 KB/s at 2.0 for 30 fps, against 5.7 and 23 MB/s raw.
- XOR-delta saved only ≈ 11–12% more than plain zlib and decoded ≈ 20–40× slower, so full-frame zlib is the default for now.
- **These numbers are best-case.** The frames are mostly static black, the transport is loopback, the Simulator runs on a Mac CPU (a real watch will decode more slowly), and the Swift code ran as a debug build.

**Still not validated:**
- the Flutter engine on watchOS (Open Question 9), and everything that depends on it
- memory, CPU and battery on a real watch
- real Wi-Fi behaviour (latency, suspension, reconnect)
- worst-case compressibility with busy full-screen content
- real GPU readback cost — the capture timings above come from the test renderer
- the real `ZeroCopyCanvas`, DRAW_TEXT / DRAW_RRECT parsing, the Dart FFI calls, and the paint hook
- on-screen redraw behaviour — the redraw checks used an off-screen renderer
- the dev loop with a real macOS app as the host — E1's Flutter side ran inside `flutter test` (no window) as a stand-in for the dev machine
- hot reload, sustained streaming through the whole loop (E1 sent two frames), and taps at `pixelRatio` 2.0

---

## Open Questions

1. **Headless frame capture** — can a stock Flutter app produce frames on the dev machine without a visible window (hidden desktop window or `flutter-tester`), and can `RepaintBoundary.toImage` be captured at an acceptable rate? **Answered for `flutter test` on a macOS runner (checks P2, S1): yes.** Still open: a real hidden desktop window or `flutter-tester` process, and real GPU readback timing.
2. **WebSocket reconnection** — watchOS suspends foreground sessions in always-on display mode. Define reconnect strategy + a full-frame resync after a drop.
3. **`save` / `restore` canvas state** *(display-list path)* — SwiftUI Canvas has no direct `saveGState` equivalent. Needs a workaround via nested `Canvas` calls or manual transform tracking.
4. **Text measurement parity** *(display-list path)* — bundled font-metrics tables must match on-device rendering exactly or layouts will shift. Needs validation testing across font sizes and weights. Not applicable to modes where Flutter rasterizes its own text.
5. **Asset bundling pipeline** — how does `flutter build watchos` know which images to bake into the `.watchapp`? Needs a manifest or asset declaration convention.
6. **Xcode project structure** — where does the Swift watchOS runtime layer live relative to the Flutter project tree? Needs a defined monorepo layout.
7. **Paint hook** *(display-list path)* — `PaintingContext` constructs its own canvases and recorded `Picture`s are opaque, so subclassing `Canvas` does not intercept painting. A viable hook needs a custom `PaintingContext` / `PipelineOwner` / `RenderView` stack, or `watchos_ui` primitives that paint through their own API instead of `dart:ui` `Canvas`.
8. **Device floor and ABI** — some older watches are believed to use the `arm64_32` (ILP32) ABI. Does Dart AOT (and the engine) support it? The answer may raise the minimum device above Series 4.
9. **Engine on watchOS** — can the Flutter engine be built for watchOS, which renderer backend is usable through the embedder API, and do binary size, memory, and App Store review all work out?
10. **Simulator networking and CI availability** — can the watchOS Simulator reach the host's loopback interface, and do hosted macOS runners ship a usable watchOS runtime and device? **Answered (checks P1, P6): yes — the Simulator reached the host's loopback, and the hosted runner had a watchOS 26.5 runtime.**
11. **Frame-transport budget** — which combination of lower pixel ratio, dirty-rect diffs, zlib, and a capture-rate cap fits the 33 ms budget, first over loopback and then over real Wi-Fi? **Partly answered (check P9):** full-frame zlib is ≈ 1 KB / 3.9 KB per frame on mostly-static test frames, far inside any budget. Still open: worst-case (busy) content, real Wi-Fi, and decode time on a real watch.

---

## Build Phases

### Phase 0 — `watchos_ui` Specification
- [ ] Define full widget catalog (visual + layout primitives)
- [ ] Define `WatchConstraintProfile` for all three screen sizes
- [ ] Verify HIG numbers (touch target, font range) against the current HIG and cite sources
- [ ] Decide the device floor (Open Question 8)
- [ ] Define navigation model (page + list scaffolds only)
- [ ] Document Digital Crown scroll physics contract

### Phase 0.5 — CI Validation Spikes (can run alongside Phase 0)
- [x] Stand up a GitHub Actions macOS workflow with a watchOS Simulator destination
- [x] S0 — compile and unit-test the watch-side Swift renderer
- [x] S1 — headless frame capture under `flutter test` (timings come from the test renderer; real GPU readback still unmeasured)
- [x] S2 — loopback WebSocket between a Dart server and the Simulator client
- [x] S3 — Appendix A wire-format fixtures (stand-in writer; real `ZeroCopyCanvas` still to test)
- [ ] S4 — engine-on-watchOS feasibility (likely local or self-hosted)
- [x] Update the Code Verification Status table after each spike (done for v7.1)

### Phase 1 — Proof of Concept / MVP (Dev Mode)
- [ ] Answer Open Question 1 — headless frame capture
- [ ] Build `WatchHost` + `WatchFrameStreamer` (Dart)
- [ ] Build Dart WebSocket server scaffold
- [ ] Build SwiftUI Canvas frame view (Swift)
- [ ] WebSocket listener on watchOS (Swift, foreground session)
- [ ] Basic event round-trip: tap → `WatchInputInjector` → `setState` → new frame
- [ ] **Milestone 1a: `WatchText` + `WatchButton` renders in the watchOS Simulator with hot reload (no hardware, CI-verified)** — the loop itself is verified (check E1, with `flutter test` as the host); hot reload and a real desktop-app host are not yet covered
- [ ] **Milestone 1b: the same on a real watch over Wi-Fi ← MVP demo milestone**
- [ ] Measure and publish frame time, bandwidth, and tap-to-photon latency

### Phase 2 — Debug Tooling
- [ ] Build `ConstraintValidator` (render tree → `ViolationType[]`)
- [ ] Build debug overlay renderer (overflow stripes, bounding boxes)
- [ ] Build preview viewport UI (watch bezel + violations panel + metrics)
- [ ] Wire send gate — block critical violations from transmission

### Phase 3 — Production: Engine on Device
- [ ] Feasibility study — Flutter engine on watchOS (Open Question 9)
- [ ] Swift embedder host — `FlutterEngineRun`, present callback, input forwarding
- [ ] Patch Dart AOT build targets to add watchOS as a platform
- [ ] Replace iOS framework linkage with watchOS equivalents
- [ ] Validate binary size within watchOS bundle limits
- [ ] Validate memory footprint and frame times per watch SKU with Instruments (Series 4, Series 9, Ultra)
- [ ] End-to-end: `flutter build watchos` produces `.watchapp`

### Phase 4 — Display-List / Zero-Copy Research (Optional — Appendix A)
- [ ] Solve the paint hook (Open Question 7)
- [ ] Replace WebSocket with Dart FFI + `@_cdecl` Swift bridge
- [ ] Implement `ZeroCopyCanvas` triple-buffer mailbox — Swift-owned slabs, typed-view writer
- [ ] Implement `WatchRenderStore` slab state machine + bounds-checked `Canvas` reader
- [ ] Wire haptic + event callbacks via FFI
- [ ] Measure allocation, frame drops, and FFI cost against the hypotheses in this document

### Phase 5 — App Store Pipeline
- [ ] Xcode project integration + monorepo layout definition
- [ ] Code signing + provisioning profile for watchOS
- [ ] App Store submission validation
- [ ] Example app + documentation site

---

## Antigravity 2.0 Agent Strategy

Leverage Antigravity 2.0's parallel subagent execution to tackle independent implementation pieces simultaneously. The architect defines specs; agents implement against them.

> ⚠️ **Gate:** no agent starts against a spec section until the matching Phase 0.5 spike compiles in CI, and every agent's definition of done includes a green CI job. Fanning out eight agents against code that has never compiled multiplies unverified code.

| Agent | Responsibility |
|---|---|
| Agent 1 | `watchos_ui` primitive widget library + Digital Crown scroll physics |
| Agent 2 | `WatchHost` + `WatchFrameStreamer` + `WatchInputInjector` (Dart) |
| Agent 3 | Frame transport protocol + codegen (Dart + Swift targets) |
| Agent 4 | SwiftUI Canvas frame view (Swift) |
| Agent 5 | WebSocket protocol + event / haptic round-trip |
| Agent 6 | Swift embedder host — engine on device (Phase 3) |
| Agent 7 | Constraint validator + debug preview viewport UI (Phase 2) |
| Agent 8 | Display-list research: `ZeroCopyCanvas` triple-buffer + `WatchRenderStore` Swift receiver (Phase 4) |

**Architect responsibilities — non-delegatable:**
- Answer the headless frame-capture question (Open Question 1) before Phase 1 begins
- Keep the Code Verification Status table honest — nothing is "done" until CI says so
- Define specs clearly before each agent run
- Review all agent outputs against this architecture document
- Make high-level tradeoff decisions agents cannot make
- Validate that the end-to-end system actually works

---

## Tooling Stack

| Tool | Role |
|---|---|
| Dart VM | Layout engine, state management, hot reload (development only) |
| `RepaintBoundary.toImage` | Frame capture in development mode |
| Flutter embedder API | Production host — real engine on device (Phase 3) |
| Dart FFI | Dart ↔ Swift bridge — `@_cdecl` native calls (display-list research, Phase 4) |
| Zero-Copy Shared Memory Buffer | Display-list research render path — triple-buffered Swift-owned slabs, typed-view writes, low allocation (Phase 4) |
| SwiftUI Canvas | watchOS drawing surface — redraws on frame arrival |
| Protobuf | Display list wire format for the display-list research path |
| WebSocket (dev) | Communication layer for frame streaming |
| Antigravity 2.0 | AI agent orchestration for parallel implementation |
| VSCode + Flutter extension | Developer IDE — unchanged from standard Flutter workflow |
| GitHub Actions macOS runners + watchOS Simulator | Compile and test Swift and Dart with no owned hardware (Phase 0.5) |

---

## What This Project Is (Big Picture)

```
Existing Flutter platform embedders:
  flutter/android
  flutter/ios
  flutter/web
  flutter/macos
  flutter/linux
  flutter/windows

This project:
  flutter/watchos  ← publishable, App Store viable (to be validated)
```

Comparable in scope to `flutter_pi` — the community embedder for Raspberry Pi — which proved Flutter could run on a constrained non-phone target and changed how the Flutter team thought about embedded platforms.

A working MVP (`WatchText` + `WatchButton` running on a real Apple Watch with hot reload) is sufficient to open a credible conversation with the Flutter core team.

### Related Work

**flutter-watchos** is an independent, non-official toolchain that, according to its author's public article (August 2026), runs the real Flutter engine and framework on Apple Watch, with Simulator hot reload, AOT device builds, Digital Crown support, plugins, and an App Store game built with it. It was in closed beta at the time of that article. This document describes it only from that article and has not inspected its code. Its design is closest to this document's production mode.

| | This design | flutter-watchos (per its author's article) |
|---|---|---|
| Runtime on watch | Development: frame viewer · Production: engine on device (unverified) | Real engine, AOT |
| Widgets | Real framework + `watchos_ui` constraint layer | Standard Flutter widgets (Cupertino works) |
| Dev loop | Mac-hosted VM, hot reload driving a physical watch (hypothesis) | Simulator hot reload; device builds AOT |
| Constraint enforcement | Built-in validator (proposed) | Developer's responsibility |
| Status | Draft design | Closed beta, shipped app |

---

## Appendix A — Display-List Research Path (Separate Architecture)

> ⚠️ **Not part of the primary design.** Everything in this appendix describes a different architecture from the one in the main document. Under the primary design (Mode 1 / Mode 2) the Flutter engine rasterizes every frame, so none of this is needed: no custom wire protocol, no draw-primitive subset, no shared-memory buffer.
>
> The display-list path only makes sense if SwiftUI `Canvas` is meant to *execute* drawing opcodes itself instead of showing engine-rendered pixels. The engine's rasterizer is then out of the loop and something else must produce the opcodes — a custom `RenderObject` tree or a lightweight custom framework (Open Questions 3, 4, 7). That is a different UI framework borrowing Flutter's Dart layer, not "Flutter on watchOS". Treat it as a fallback to consider only if Phase 3 (engine on device) proves infeasible or too heavy.
>
> All code in this appendix is an unexecuted design sketch — see Code Verification Status.

### A.0 Shared Swift Helper — `Color(argb:)`

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

### A.1 Dart FFI — Replacing swiftgen

#### Why swiftgen Is Not Used

The original brainstorm referenced `swiftgen` (`pub.dev/packages/swiftgen`) as the Dart-to-Swift interop layer. After evaluation, it has been removed from the architecture for the following reasons:

- **Critically low adoption** — approximately 33 downloads at time of evaluation, not production viable
- **Unstable API** — published approximately 2 months before evaluation with no stability guarantees
- **Unnecessary abstraction** — adds a generated glue layer between Dart and Swift that Dart FFI handles natively
- **Maintenance risk** — a package with this adoption level can be abandoned without notice
- **No performance benefit** — swiftgen adds indirection that Dart FFI eliminates entirely

> ⚠️ **Note:** swiftgen is not ruled out permanently. If it reaches stability and meaningful adoption in a future version, it may be reconsidered for ergonomic binding generation. Dart FFI is the correct choice for now.

#### Dart FFI vs swiftgen — Comparison

| | swiftgen | Dart FFI |
|---|---|---|
| Stability | Experimental / unstable | Production stable (core Dart SDK) |
| Adoption | ~33 downloads | Core SDK — universally adopted |
| Abstraction | Dart → glue → Swift | Dart → C bridge → Swift |
| Call latency | Microseconds + glue overhead | Microseconds — direct native call |
| Maintenance risk | High — may be abandoned | None — part of Dart SDK |
| Production ready | ❌ POC only | ✅ App Store compliant |

#### Why Dart FFI Is the Right Choice

Dart FFI provides a direct, industry-standard path from Dart to native C-ABI functions. Swift exposes functions to C via the `@_cdecl` annotation, which Dart FFI can call directly — no third-party package, no generated glue, no instability.

#### Dart FFI Bridge Pattern

Swift exposes canvas drawing functions via the C ABI. Dart looks them up by symbol name and calls them as native function pointers — no serialization, no network hop.

```swift
// Swift side — expose to C ABI
@_cdecl("watch_draw_rect")
public func drawRect(x: Float, y: Float, w: Float, h: Float, color: UInt32) {
    // Forward to SwiftUI Canvas renderer
}

@_cdecl("watch_draw_text")
public func drawText(x: Float, y: Float,
                     text: UnsafePointer<CChar>,
                     fontSize: Float, color: UInt32) {
    // Forward to SwiftUI Canvas renderer
}
```

```dart
// Dart side — look up Swift symbols via Dart FFI
final dylib = DynamicLibrary.process();

final _drawRect = dylib.lookupFunction<
  Void Function(Float, Float, Float, Float, Uint32),
  void Function(double, double, double, double, int)
>('watch_draw_rect');

// Called from WatchCanvas — microsecond latency, zero serialization
_drawRect(x, y, width, height, color);
```

> ✅ In development mode (Phase 1), WebSocket is used instead of FFI — simpler to set up and sufficient for hot reload. Dart FFI applies to the display-list research path (Phase 4); the production reference path (Flutter engine on device) does not need it for rendering.

---

### A.2 Zero-Copy Shared Memory Buffer (Display-List Render Path)

> **Applies to the display-list research path only (Phase 4).** Development mode streams rendered frames and production mode runs the Flutter engine on device — neither uses this buffer. This section describes the low-allocation FFI render loop that would replace per-frame serialization if the display-list approach is pursued. All code in this section is an unexecuted design sketch.

In a naive FFI implementation, every frame still pays a serialization tax: Dart allocates objects, packs them into a byte array on the managed heap, hands the array across the FFI boundary, and Swift deserializes it into new objects. At 30 fps on a constrained watch, this GC churn spikes CPU and risks an OOM kill.

The zero-copy buffer aims to remove most of that tax. Dart and Swift share persistent blocks of raw native memory. Dart writes primitive values directly into typed views over it; Swift reads them back out with very few allocations.

#### The Problem with Per-Frame Serialization

Each serialized frame cycle:
1. Dart creates framework objects (`DrawRect`, `DrawText`).
2. A serialization library allocates a temporary byte array **on the Dart GC heap**.
3. The byte array is copied across the FFI boundary into native memory.
4. Swift deserializes it, allocating a corresponding set of Swift objects.
5. Both runtimes GC/dealloc hundreds of short-lived objects before the next frame.

At 30 fps this cycle instantly spikes the watch CPU.

#### The Binary Command Layout (Wire Protocol)

Every drawing operation maps to a fixed-size binary structure. No dynamic allocation, no parsing — just sequential reads.

| Offset (Bytes) | Data Type | Field        | Description                                         |
|----------------|-----------|--------------|-----------------------------------------------------|
| **0 – 3**      | `Uint32`  | `Command ID` | Identifies the operation (e.g. `1` = `DRAW_RECT`)  |
| **4 – 7**      | `Float32` | `X`          | Left coordinate                                     |
| **8 – 11**     | `Float32` | `Y`          | Top coordinate                                      |
| **12 – 15**    | `Float32` | `Width`      | Width of the rectangle                              |
| **16 – 19**    | `Float32` | `Height`     | Height of the rectangle                             |
| **20 – 23**    | `Uint32`  | `Color`      | Packed 32-bit ARGB color                            |

Command sizes are **per op**, not global:

| Op | ID | Layout (after the 4-byte ID) | Bytes |
|---|---|---|---|
| `DRAW_RECT` | 1 | `Float32 x, y, w, h` · `Uint32 color` | 24 |
| `DRAW_CIRCLE` | 2 | `Float32 cx, cy, r` · `Uint32 color` | 20 |
| `DRAW_TEXT` | 3 | see Variable-Length Commands | 28 + N + padding |
| `DRAW_RRECT` | 4 | `Float32 x, y, w, h, radius` · `Uint32 color` | 28 |

#### Thread Safety — Triple-Buffer Mailbox

> ⚠️ A single shared buffer is unsafe. Dart can overwrite it mid-frame while Swift is reading — undefined behaviour and crashes. Two slabs with a blocking latch are also not enough: the latch proves Swift *picked up* the pointer, not that it *finished reading* before Dart reuses the slab, and blocking an FFI call on the main thread can deadlock if the Dart isolate ever runs there.

Three persistent slabs are allocated at startup. Each is in exactly one of four states, owned by a single lock-protected state machine on the Swift side — classic GPU triple-buffering ("mailbox" presentation): the producer never waits, and the consumer always shows the newest complete frame.

```
FREE ──acquireWrite──▶ WRITING ──submit──▶ READY ──acquireRead──▶ READING ──(newer frame arrives)──▶ FREE
                                             │
                                             └── superseded by a newer submit ──▶ FREE
```

Invariants:
- At most one slab is `WRITING` (Dart), one `READY`, one `READING` (Swift)
- Dart **never blocks** — if no slab is `FREE`, Dart drops the frame
- Swift redraws the current `READING` slab only when SwiftUI asks for a redraw (invalidation, size change) and switches to a newer `READY` slab when one exists — there is no free-running timer
- The Dart UI isolate runs on its own thread; FFI calls never wait on the main thread, which only reads

#### Dart Implementation

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
    _write.setFloat32(o + 16, height, Endian.host);  // offset 16, not 14
    _write.setUint32(o + 20, color,   Endian.host);

    _byteOffset += 24;
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

#### Swift Implementation — Low-Allocation

`GraphicsContext` is a SwiftUI value type and cannot be passed across FFI. Instead, the store owns the slabs and the `@_cdecl` functions only move slab indices and byte counts — **no parsing, no intermediate array**. The `Canvas` closure reads straight from the raw bytes during its native draw pass.

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
        // No TimelineView: a free-running .animation timeline would redraw at display rate
        // even when nothing changed (battery). Each submitted slab bumps frameTick, which
        // invalidates this view, so the Canvas redraws once per new frame.
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
                    context.fill(Path(rect), with: .color(Color(argb: color))) // Color(argb:) is defined in A.0
                    offset += 24

                case 2: // DRAW_CIRCLE — placeholder, 20 bytes
                    guard need(20) else { return }
                    offset += 20

                case 3: // DRAW_TEXT — variable length, see below
                    guard need(28) else { return }
                    let x          = buffer.loadUnaligned(fromByteOffset: offset + 4,  as: Float.self)
                    let y          = buffer.loadUnaligned(fromByteOffset: offset + 8,  as: Float.self)
                    let color      = buffer.loadUnaligned(fromByteOffset: offset + 12, as: UInt32.self)
                    let fontSize   = buffer.loadUnaligned(fromByteOffset: offset + 16, as: Float.self)
                    // flags at offset + 20: weight / alignment (bit layout defined in Phase 0)
                    let textLength = Int(buffer.loadUnaligned(fromByteOffset: offset + 24, as: UInt32.self))
                    guard need(28 + textLength) else { return }

                    // Decode the raw UTF-8 bytes. Strings up to 15 bytes stay inline in Swift
                    // (no heap allocation); longer strings allocate.
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

> **Redraw note (unverified):** confirm in spike S0 that the `Canvas` redraws on every `frameTick` change. If SwiftUI skips the redraw because the closure compares equal, add `.id(tick)` to the `Canvas`; do not fall back to `TimelineView(.animation)`.

> **Linking note:** `DynamicLibrary.process()` only finds these symbols if they are exported and not dead-stripped. Verify with the real Xcode build settings.

---

#### Variable-Length Commands — Length-Prefixed Wire Protocol

Fixed-size commands like `DRAW_RECT` are trivial because the pointer step is constant. Text and vector paths have variable lengths and require a length-prefixed layout with **4-byte alignment padding** so every subsequent command lands on a naturally aligned boundary.

> ⚠️ **Why alignment still matters on watchOS:** Swift's `load(as:)` requires the address to be suitably aligned for the type — violating that is undefined behaviour — and unaligned accesses can cost performance. ARM64 hardware itself tolerates many unaligned accesses, so treat misalignment as a correctness hazard in Swift rather than a guaranteed hardware fault. Every variable-length command pads to the next 4-byte boundary, and the reader uses `loadUnaligned` as a safety net.

##### `DRAW_TEXT` Layout

| Offset (Bytes)      | Data Type  | Field                | Description                                    |
|---------------------|------------|----------------------|------------------------------------------------|
| **0 – 3**           | `Uint32`   | `Command ID`         | `3` for `DRAW_TEXT`                            |
| **4 – 7**           | `Float32`  | `X`                  | Destination X                                  |
| **8 – 11**          | `Float32`  | `Y`                  | Destination Y                                  |
| **12 – 15**         | `Uint32`   | `Color`              | Packed ARGB color                              |
| **16 – 19**         | `Float32`  | `Font Size`          | Point size                                     |
| **20 – 23**         | `Uint32`   | `Flags`              | Weight / alignment bits (layout set in Phase 0)|
| **24 – 27**         | `Uint32`   | `String Byte Length` | Exact byte count of the UTF-8 string           |
| **28 to (28+N−1)**  | `Uint8[]`  | `Raw UTF-8 Bytes`    | The string characters                          |
| **Variable**        | `Uint8[]`  | `Padding`            | 0–3 zero bytes to align the next command to 4  |

> ⚠️ Flutter paints text as an already laid-out `Paragraph` (`drawParagraph`), which cannot be turned back into a string. On this path `WatchText` must therefore be a custom `RenderObject` that measures with bundled font metrics and emits `DRAW_TEXT` itself (Open Question 4).

##### Dart — Packing Variable-Length Text

A method of `ZeroCopyCanvas`:

```dart
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
```

#### Why This Beats Per-Frame Serialization

| Property | Protobuf / JSON path | Zero-Copy Buffer |
|---|---|---|
| Dart GC pressure | High — byte arrays allocated every frame | Low — slabs live outside the GC heap, writes go through typed views, text encoding is cached |
| Swift allocations | High — intermediate array + objects per command | Low — raw bytes read in place; text still creates a `String` (inline when ≤ 15 UTF-8 bytes) plus `Text` / `Color` values |
| FFI handoff cost | Copy entire serialized payload | Slab index + byte count — no payload copy |
| Thread safety | N/A | Triple-buffer mailbox — Dart never blocks |
| Alignment | N/A | 4-byte padding on all variable commands + `loadUnaligned` safety net |

> All entries are design expectations, not measurements. Candidate measurements: Dart DevTools allocation profile, Instruments → Allocations, frame-drop count from failed `acquireWrite`, and FFI call time versus the 33 ms frame budget.

#### Trade-offs

1. **Dropped frames instead of blocking:** if no slab is free — or a frame overflows its slab — Dart drops the frame rather than waiting. Measure the drop rate under load.
2. **Memory safety:** the Swift reader bounds-checks every read against `byteCount` and bails on unknown ops. Keep the `DEBUG` assert that `offset == byteCount` after each frame to catch misalignments in development.
3. **Memory budget:** three slabs instead of two. The ~30 MB target varies by watch generation (Series 4 through Ultra). Validate actual headroom with Instruments on each target SKU — do not treat it as a universal hard ceiling.
4. **Idle redraw cost:** none by design — the view redraws only when `frameTick` changes. Re-adding a `TimelineView` (for example for local animation) reintroduces continuous redraw; gate it on a visible animation.
5. **Symbol export:** `@_cdecl` symbols must survive dead-stripping to be found by `DynamicLibrary.process()`.

---

### A.3 The Display List Protocol

A serialized list of low-level drawing operations produced by Flutter's paint cycle and consumed by the SwiftUI Canvas renderer.

> ⚠️ **Research path only.** Development mode streams rendered frames and production mode runs the Flutter engine on device. This protocol is used only if the paint hook (Open Question 7) is solved.

#### Draw Command Set (v0)

```
drawRect       x, y, width, height, color, radius?
drawCircle     cx, cy, radius, color
drawLine       x1, y1, x2, y2, color, strokeWidth
drawPath       points[], color, strokeWidth, filled
drawText       x, y, text, fontSize, color, fontWeight, align
drawImage      x, y, width, height, imageRef
drawShadow     x, y, width, height, blur, color
clipRect       x, y, width, height
save           (push canvas state)
restore        (pop canvas state)
```

#### Wire Format — Development Mode Only

| Format | Decision |
|---|---|
| **Protobuf** | ✅ Default — expected ~3–5× smaller than JSON (unmeasured), typed schema, auto-generates Dart + Swift types |
| JSON | Available as a debug flag for inspecting frames during development |
| FlatBuffers | Not used in v0 — marginal benefit at this payload size, complex schema language |

#### Protobuf Schema

```protobuf
message DisplayList {
  uint32 frameId             = 1;
  uint64 timestamp           = 2;
  repeated DrawCommand commands = 3;
}

message DrawCommand {
  enum Op {
    DRAW_RECT   = 0; DRAW_CIRCLE = 1; DRAW_LINE   = 2;
    DRAW_PATH   = 3; DRAW_TEXT   = 4; DRAW_IMAGE  = 5;
    DRAW_SHADOW = 6; CLIP_RECT   = 7; SAVE        = 8; RESTORE = 9;
  }
  Op     op          = 1;
  float  x           = 2;
  float  y           = 3;
  float  width       = 4;
  float  height      = 5;
  float  radius      = 6;
  uint32 color       = 7;  // ARGB packed
  string text        = 8;
  float  fontSize    = 9;
  string imageRef    = 10;
  float  strokeWidth = 11;
  repeated float points = 12;
}

message InputEvent {
  enum Type { TAP = 0; SWIPE = 1; CROWN = 2; HAPTIC_TRIGGER = 3; }
  Type  type  = 1;
  float x     = 2;
  float y     = 3;
  float delta = 4;  // crown rotational delta
}
```

---

### A.4 The Canvas Interceptor — Dart Side

> ⚠️ **Research path — hook unresolved.** `PaintingContext` constructs its own canvases and recorded `Picture`s are opaque to Dart, so a `Canvas` subclass alone does not intercept Flutter's pipeline (Open Question 7). Flutter also paints text as a laid-out `Paragraph` via `drawParagraph`, not as a string, so `drawText` below only applies to `watchos_ui` primitives that paint through their own API (Open Question 4).

Wraps Flutter's `dart:ui Canvas` to capture every paint call and serialize it into the display list format. Only `watchos_ui` visual primitives trigger these calls, keeping the command surface predictable.

```dart
class WatchCanvas implements Canvas {
  final List<DrawCommand> _commands = [];

  @override
  void drawRect(Rect rect, Paint paint) {
    _commands.add(DrawCommand.rect(
      x: rect.left, y: rect.top,
      width: rect.width, height: rect.height,
      color: paint.color.toARGB32(),
    ));
  }

  @override
  void drawCircle(Offset center, double radius, Paint paint) {
    _commands.add(DrawCommand.circle(
      cx: center.dx, cy: center.dy,
      radius: radius,
      color: paint.color.toARGB32(),
    ));
  }

  // ... all remaining Canvas methods

  DisplayList flush(int frameId) {
    final list = DisplayList(frameId: frameId, commands: List.from(_commands));
    _commands.clear();
    return list;
  }
}
```

A viable injection point would need a custom `PaintingContext` / `PipelineOwner` / `RenderView` stack, or `watchos_ui` primitives that bypass `dart:ui` `Canvas` entirely. Neither is validated.

---

### A.5 Display-List Renderer — Watch Side (Swift)

Receives draw commands via WebSocket or Dart FFI direct calls. Maps each command to its SwiftUI Canvas equivalent.

```swift
func render(commands: [DrawCommand], context: inout GraphicsContext, size: CGSize) {
    for cmd in commands {
        switch cmd.op {

        case .drawRect:
            let rect = CGRect(x: cmd.x, y: cmd.y, width: cmd.width, height: cmd.height)
            let path = cmd.radius > 0
                ? Path(roundedRect: rect, cornerRadius: CGFloat(cmd.radius))
                : Path(rect)
            context.fill(path, with: .color(Color(argb: cmd.color)))

        case .drawCircle:
            let bounds = CGRect(
                x: CGFloat(cmd.cx) - CGFloat(cmd.radius),
                y: CGFloat(cmd.cy) - CGFloat(cmd.radius),
                width: CGFloat(cmd.radius) * 2,
                height: CGFloat(cmd.radius) * 2
            )
            context.fill(Path(ellipseIn: bounds), with: .color(Color(argb: cmd.color)))

        case .drawText:
            context.draw(
                Text(cmd.text)
                    .font(.system(size: CGFloat(cmd.fontSize)))
                    .foregroundColor(Color(argb: cmd.color)),
                at: CGPoint(x: CGFloat(cmd.x), y: CGFloat(cmd.y)),
                anchor: .topLeading   // Flutter paints from the top-left; SwiftUI defaults to .center
            )

        case .drawImage:
            if let img = assetCache[cmd.imageRef] {
                context.draw(img, in: CGRect(
                    x: cmd.x, y: cmd.y,
                    width: cmd.width, height: cmd.height
                ))
            }

        default: break
        }
    }
}
```

---

## References

- Flutter custom engine embedders: https://github.com/flutter/flutter/wiki/Custom-Flutter-Engine-Embedders
- Flutter embedder API (engine now lives in the `flutter/flutter` monorepo — verify path): https://github.com/flutter/flutter/blob/main/engine/src/flutter/shell/platform/embedder/embedder.h
- `flutter_pi` (reference community embedder): https://github.com/ardera/flutter-pi
- Dart FFI documentation: https://dart.dev/interop/c-interop
- flutter-watchos: https://flutterwatch.dev · https://github.com/flutterwatch/flutter-watchos
- Article describing flutter-watchos: https://itnext.io/yes-you-can-build-apple-watch-apps-with-flutter-now-909c3dc84804
- Antigravity 2.0: https://antigravity.google/product/antigravity-2
- GitHub-hosted runners (macOS): https://docs.github.com/en/actions/using-github-hosted-runners/using-github-hosted-runners/about-github-hosted-runners
- Apple watchOS HIG: https://developer.apple.com/design/human-interface-guidelines/watchos
- Apple watchOS 10 design changes: https://developer.apple.com/news/releases/watchos-10
- SwiftUI Canvas docs: https://developer.apple.com/documentation/swiftui/canvas
- SwiftUI GraphicsContext docs: https://developer.apple.com/documentation/swiftui/graphicscontext

---

## Changelog

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
