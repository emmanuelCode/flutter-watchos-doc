import XCTest
import SwiftUI
@testable import SpecCode

/// S3 — the spec's WatchFrameStore + WatchFrameView draw a frame, stretched to fill the view.
/// v7.0 had a `store.scale` that this check proved useless (identical output for scale 1 and 2); it was removed.
/// What matters now: the SAME picture captured at different pixel sizes (i.e. different pixelRatio)
/// must fill the view identically.
final class S3_FrameStoreViewTests: XCTestCase {

    /// n x n px image: left half red, right half blue.
    private func twoColour(_ n: Int) -> CGImage {
        var px = [UInt8]()
        for _ in 0..<n {
            for x in 0..<n { px += (x < n / 2) ? [255, 0, 0, 255] : [0, 0, 255, 255] }
        }
        return makeCGImage(rgba: px, width: n, height: n)
    }

    @MainActor
    private func render(imagePixels n: Int) throws -> (px: [UInt8], width: Int) {
        let store = WatchFrameStore()
        store.latest = twoColour(n)
        return try pixels(makeRenderer(WatchFrameView(store: store).frame(width: 8, height: 8)))
    }

    @MainActor
    func test_view_draws_the_stored_frame_stretched_to_fill() throws {
        let p = try render(imagePixels: 4)
        assertNear(pixel(p, 1, 4), [255, 0, 0, 255])   // left half red
        assertNear(pixel(p, 6, 4), [0, 0, 255, 255])   // right half blue
    }

    @MainActor
    func test_capture_size_does_not_change_what_fills_the_view() throws {
        // 2px, 4px and 16px captures of the same picture (think pixelRatio 0.5 / 1 / 4)
        for n in [2, 4, 16] {
            let p = try render(imagePixels: n)
            assertNear(pixel(p, 1, 4), [255, 0, 0, 255])
            assertNear(pixel(p, 6, 4), [0, 0, 255, 255])
        }
        proofLog("S3: 2px, 4px and 16px captures of one picture all fill the view the same way")
    }

    @MainActor
    func test_empty_store_draws_nothing_and_does_not_crash() throws {
        let p = try pixels(makeRenderer(WatchFrameView(store: WatchFrameStore()).frame(width: 4, height: 4)))
        XCTAssertEqual(pixel(p, 2, 2)[3], 0, "no frame => transparent")
    }
}
