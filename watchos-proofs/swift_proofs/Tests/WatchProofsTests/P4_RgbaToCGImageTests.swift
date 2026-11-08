import XCTest
import WatchProofs

/// P4 — Raw RGBA bytes (what Flutter's toByteData gives us) become a CGImage with correct pixels.
final class P4_RgbaToCGImageTests: XCTestCase {

    func test_rgba_bytes_become_a_cgimage_with_correct_pixels() throws {
        // 2x1 image: a red pixel then a blue pixel (straight RGBA)
        let rgba = Data([255, 0, 0, 255,   0, 0, 255, 255])
        let image = try XCTUnwrap(makeCGImage(rgba: rgba, width: 2, height: 1))

        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 1)
        let px = readRGBA(image)
        XCTAssertEqual(Array(px[0..<4]), [255, 0, 0, 255])
        XCTAssertEqual(Array(px[4..<8]), [0, 0, 255, 255])
    }

    func test_a_full_45mm_frame_converts() throws {
        let rgba = Data(count: 198 * 242 * 4) // 191,664 bytes
        XCTAssertNotNil(makeCGImage(rgba: rgba, width: 198, height: 242))
    }

    func test_wrong_byte_count_is_rejected() {
        XCTAssertNil(makeCGImage(rgba: Data([1, 2, 3]), width: 2, height: 1))
    }
}
