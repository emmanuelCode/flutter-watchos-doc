import XCTest
import SwiftUI
@testable import SpecCode

/// S6 — EXPERIMENTAL. The fix for the TimelineView finding: WatchCanvasView has NO timeline; it relies on
/// `frameTick` (bumped on the main queue by watchSubmitSlab) to re-run the Canvas.
/// One ImageRenderer stays alive; we submit a second frame through the C ABI and re-read the SAME renderer.
/// If this stays on the old frame, the spec's own fallback applies: add `.id(tick)` to the Canvas.
final class S6_CanvasTickRedrawTests: XCTestCase {

    @MainActor
    func test_canvas_redraws_when_a_frame_is_submitted() async throws {
        S5_RenderStoreCanvasTests.submitRect(argb: 0xFFFF0000)
        let renderer = makeRenderer(WatchCanvasView().frame(width: 8, height: 8))
        assertNear(pixel(try pixels(renderer), 4, 4), [255, 0, 0, 255])

        var invalidated = false
        let sub = renderer.objectWillChange.sink { invalidated = true }
        S5_RenderStoreCanvasTests.submitRect(argb: 0xFF0000FF)   // frame 2 (blue); tick bump happens async on main
        try await Task.sleep(nanoseconds: 500_000_000)
        sub.cancel()

        proofLog("S6: renderer reported invalidation after submit = \(invalidated)")
        assertNear(pixel(try pixels(renderer), 4, 4), [0, 0, 255, 255],
                   tol: 4)
    }
}
