import XCTest
import WatchProofs

/// A3 — [Appendix A] Bytes written by Dart (dart_tools/gen_wire_fixture.dart) parse correctly in Swift:
/// same offsets, UTF-8 text, 4-byte padding — even when the buffer base address is misaligned.
final class A3_WireFormatTests: XCTestCase {

    private let expected: [DrawCmd] = [
        .rect(x: 1, y: 2, w: 3, h: 4, color: 0xFFFF0000),
        .text(x: 10, y: 20, color: 0xFF00FF00, fontSize: 14, flags: 0, text: "Hé"),
        .rect(x: 5, y: 6, w: 7, h: 8, color: 0xFF0000FF),
    ]

    private func fixture() throws -> Data {
        let url = URL(fileURLWithPath: "/tmp/watch_fixture/frame.bin")
        return try XCTUnwrap(try? Data(contentsOf: url), "run `dart run dart_tools/gen_wire_fixture.dart` first")
    }

    func test_swift_parses_what_dart_wrote() throws {
        let data = try fixture()
        XCTAssertEqual(data.count, 80)
        let cmds = data.withUnsafeBytes { parseFrame($0.baseAddress!, byteCount: data.count) }
        XCTAssertEqual(cmds, expected)
    }

    func test_parses_from_a_misaligned_base_address() throws {
        let data = try fixture()
        let raw = UnsafeMutableRawPointer.allocate(byteCount: data.count + 1, alignment: 16)
        defer { raw.deallocate() }
        data.withUnsafeBytes { raw.advanced(by: 1).copyMemory(from: $0.baseAddress!, byteCount: data.count) }

        XCTAssertEqual(parseFrame(raw.advanced(by: 1), byteCount: data.count), expected)
    }

    func test_truncated_frame_is_rejected_not_read_past_the_end() throws {
        let data = try fixture()
        let cut = data.count - 5
        let cmds = data.withUnsafeBytes { parseFrame($0.baseAddress!, byteCount: cut) }
        XCTAssertNil(cmds)
    }
}
