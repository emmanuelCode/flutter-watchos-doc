import XCTest
import SwiftUI
import WatchProofs

/// P5 — The primary path's last step: SwiftUI Canvas draws the CGImage it is handed.
/// We render the Canvas off-screen with ImageRenderer and look at the pixels.
final class P5_CanvasDrawsPixelsTests: XCTestCase {

    @MainActor
    func test_canvas_draws_the_frame_it_was_given() throws {
        var rgba = Data()
        for _ in 0..<(8 * 8) { rgba.append(contentsOf: [255, 0, 0, 255]) } // solid red 8x8
        let frame = try XCTUnwrap(makeCGImage(rgba: rgba, width: 8, height: 8))

        let view = Canvas { context, size in
            context.draw(Image(decorative: frame, scale: 1), in: CGRect(origin: .zero, size: size))
        }
        .frame(width: 8, height: 8)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let out = try XCTUnwrap(renderer.cgImage, "ImageRenderer produced no image")

        let px = readRGBA(out)
        let centre = (4 * out.width + 4) * 4
        XCTAssertEqual(Array(px[centre..<centre + 4]), [255, 0, 0, 255])
    }
}
