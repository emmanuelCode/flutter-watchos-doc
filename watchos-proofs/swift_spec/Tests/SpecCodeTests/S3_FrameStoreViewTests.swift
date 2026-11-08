import XCTest
import SwiftUI
@testable import SpecCode

/// S3 — the spec's WatchFrameStore + WatchFrameView draw a frame, and what `scale` really does.
/// FINDING TO WATCH FOR: the view draws with `context.draw(image, in: <whole view>)`, which stretches
/// the image to fill the view — so `store.scale` may have no effect at all. This test measures that.
final class S3_FrameStoreViewTests: XCTestCase {

    /// 4x4 px image: left half red, right half blue.
    private func twoColour() -> CGImage {
        var px = [UInt8]()
        for _ in 0..<4 { px += [255, 0, 0, 255, 255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255] }
        return makeCGImage(rgba: px, width: 4, height: 4)
    }

    @MainActor
    private func render(scale: CGFloat) throws -> (px: [UInt8], width: Int) {
        let store = WatchFrameStore()
        store.scale = scale          // spec: set scale BEFORE latest
        store.latest = twoColour()
        return try pixels(makeRenderer(WatchFrameView(store: store).frame(width: 8, height: 8)))
    }

    @MainActor
    func test_view_draws_the_stored_frame_stretched_to_fill() throws {
        let p = try render(scale: 1)
        assertNear(pixel(p, 1, 4), [255, 0, 0, 255])   // left half red
        assertNear(pixel(p, 6, 4), [0, 0, 255, 255])   // right half blue
    }

    @MainActor
    func test_what_does_scale_change() throws {
        let a = try render(scale: 1), b = try render(scale: 2)
        proofLog("S3: output identical for scale 1 vs 2 = \(a.px == b.px)  (true => store.scale has no visible effect)")
    }

    @MainActor
    func test_empty_store_draws_nothing_and_does_not_crash() throws {
        let p = try pixels(makeRenderer(WatchFrameView(store: WatchFrameStore()).frame(width: 4, height: 4)))
        XCTAssertEqual(pixel(p, 2, 2)[3], 0, "no frame => transparent")
    }
}
