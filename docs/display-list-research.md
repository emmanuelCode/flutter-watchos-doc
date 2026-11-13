> ⚠️ **Not part of the primary design — and not "Flutter on watchOS".** This file describes a separate display-list research path where SwiftUI `Canvas` *executes* drawing opcodes instead of displaying Flutter-engine pixels. Under Path A in [flutter_watchos_architecture.md](../flutter_watchos_architecture.md), none of this is needed.

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
