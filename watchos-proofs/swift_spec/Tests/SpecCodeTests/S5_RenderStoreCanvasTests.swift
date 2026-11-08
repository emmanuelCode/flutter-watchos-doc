import XCTest
import SwiftUI
@testable import SpecCode

/// S5 — the spec's WatchRenderStore, its @_cdecl slab API and WatchCanvasView, driven the way Dart
/// would drive them: acquire a slab, write DRAW_RECT bytes into the raw memory, submit, then render.
final class S5_RenderStoreCanvasTests: XCTestCase {

    /// Writes one DRAW_RECT (24 bytes) at (0,0) size 8x8 into a free slab and submits it.
    static func submitRect(argb: UInt32) {
        let slab = watchAcquireWriteSlab()
        precondition(slab >= 0, "no free slab")
        let b = watchSlabBase(slab)
        b.storeBytes(of: UInt32(1), toByteOffset: 0, as: UInt32.self)     // DRAW_RECT
        b.storeBytes(of: Float(0),  toByteOffset: 4, as: Float.self)      // x
        b.storeBytes(of: Float(0),  toByteOffset: 8, as: Float.self)      // y
        b.storeBytes(of: Float(8),  toByteOffset: 12, as: Float.self)     // w
        b.storeBytes(of: Float(8),  toByteOffset: 16, as: Float.self)     // h
        b.storeBytes(of: argb,      toByteOffset: 20, as: UInt32.self)    // colour
        watchSubmitSlab(slab, 24)
    }

    @MainActor
    func test_bytes_written_like_dart_are_drawn_by_the_canvas() throws {
        Self.submitRect(argb: 0xFFFF0000)
        let r = makeRenderer(WatchCanvasView().frame(width: 8, height: 8))
        assertNear(pixel(try pixels(r), 4, 4), [255, 0, 0, 255])
    }

    func test_writer_never_blocks_when_slabs_run_out() {
        var got: [Int32] = []
        for _ in 0..<4 { got.append(watchAcquireWriteSlab()) }
        XCTAssertTrue(got.contains(-1), "only 3 slabs exist, so a 4th acquire must return -1 immediately")
        for s in got where s >= 0 { watchAbandonSlab(s) }   // clean up
    }

    @MainActor
    func test_abandoned_slab_is_not_drawn() throws {
        Self.submitRect(argb: 0xFF00FF00)                    // green is the visible frame
        let slab = watchAcquireWriteSlab()
        XCTAssertGreaterThanOrEqual(slab, 0)
        watchSlabBase(slab).storeBytes(of: UInt32(1), toByteOffset: 0, as: UInt32.self)
        watchAbandonSlab(slab)                               // overflowed frame: never submitted
        let r = makeRenderer(WatchCanvasView().frame(width: 8, height: 8))
        assertNear(pixel(try pixels(r), 4, 4), [0, 255, 0, 255])
    }
}
