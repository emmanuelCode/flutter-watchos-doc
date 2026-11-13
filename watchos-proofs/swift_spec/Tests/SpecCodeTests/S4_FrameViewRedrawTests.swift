import XCTest
import SwiftUI
@testable import SpecCode

/// S4 — "No TimelineView needed — each published frame triggers a redraw."
/// One ImageRenderer stays alive; we publish a NEW frame to the store and check the same renderer
/// now shows it. (EXPERIMENTAL: relies on ImageRenderer re-rendering after an invalidation.)
final class S4_FrameViewRedrawTests: XCTestCase {

    @MainActor
    func test_view_redraws_when_a_new_frame_is_published() async throws {
        let store = WatchFrameStore()
        store.latest = solid(255, 0, 0, width: 4, height: 4)

        let renderer = makeRenderer(WatchFrameView(store: store).frame(width: 4, height: 4))
        assertNear(pixel(try pixels(renderer), 2, 2), [255, 0, 0, 255])

        var invalidated = false
        let sub = renderer.objectWillChange.sink { invalidated = true }
        store.latest = solid(0, 255, 0, width: 4, height: 4)       // publish frame 2
        for _ in 0..<40 where !invalidated {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        sub.cancel()

        proofLog("S4: renderer reported invalidation = \(invalidated)")
        XCTAssertTrue(invalidated, "ImageRenderer did not report invalidation after publishing a new frame")
        assertNear(pixel(try pixels(renderer), 2, 2), [0, 255, 0, 255])
    }
}
