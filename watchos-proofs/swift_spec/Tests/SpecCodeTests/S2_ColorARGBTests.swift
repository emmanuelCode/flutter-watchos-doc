import XCTest
import SwiftUI
@testable import SpecCode

/// S2 — the spec's own Color(argb:) renders the channels it should (checked through real pixels).
final class S2_ColorARGBTests: XCTestCase {

    @MainActor
    func test_opaque_argb_renders_the_right_rgb() throws {
        let r = makeRenderer(Rectangle().fill(Color(argb: 0xFF336699)).frame(width: 4, height: 4))
        assertNear(pixel(try pixels(r), 2, 2), [0x33, 0x66, 0x99, 255])
    }

    @MainActor
    func test_alpha_is_honoured() throws {
        // 50% red over black -> red channel about 128, green/blue about 0
        let view = Rectangle().fill(Color(argb: 0x80FF0000)).frame(width: 4, height: 4).background(Color.black)
        assertNear(pixel(try pixels(makeRenderer(view)), 2, 2), [128, 0, 0, 255], tol: 6)
    }
}
