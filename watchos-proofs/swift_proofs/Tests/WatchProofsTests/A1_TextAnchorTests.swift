import XCTest
import SwiftUI
import WatchProofs

/// A1 — [Appendix A] Flutter paints text from the top-left; SwiftUI's draw(Text, at:) defaults to
/// .center. Draw "Hi" at (0,0) both ways and count lit pixels: .center puts 3/4 of it off-canvas.
final class A1_TextAnchorTests: XCTestCase {

    @MainActor
    private func litPixels(anchor: UnitPoint) throws -> Int {
        let view = Canvas { context, _ in
            context.draw(Text("Hi").font(.system(size: 14)).foregroundColor(.white),
                         at: .zero, anchor: anchor)
        }
        .frame(width: 40, height: 20)
        .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let img = try XCTUnwrap(renderer.cgImage)
        let px = readRGBA(img)
        return stride(from: 0, to: px.count, by: 4).filter { px[$0] > 128 }.count // red channel lit
    }

    @MainActor
    func test_topLeading_keeps_text_in_the_corner_and_center_clips_it() throws {
        let topLeading = try litPixels(anchor: .topLeading)
        let center = try litPixels(anchor: .center)
        proofLog("A1: lit pixels topLeading=\(topLeading) center=\(center)")

        XCTAssertGreaterThan(topLeading, 0, "no text pixels at all - text did not render")
        XCTAssertGreaterThan(topLeading, center * 2, ".center should clip most of the text at (0,0)")
    }
}
