import XCTest
import WatchProofs

/// P6 — The dev-mode transport: a Dart server pushes one frame, the watchOS client receives it,
/// sends a tap back, and gets the reply. Needs dart_tools/ws_server.dart running (CI does this).
final class P6_WebSocketLoopbackTests: XCTestCase {

    func test_frame_comes_down_and_tap_goes_up() async throws {
        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:8765")!)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        let start = Date()
        guard case .data(let frame) = try await task.receive() else {
            return XCTFail("expected a binary frame")
        }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        proofLog("P6: received \(frame.count) bytes over loopback in \(ms) ms")
        XCTAssertEqual(frame.count, 198 * 242 * 4)
        XCTAssertEqual(Array(frame.prefix(4)), [255, 0, 0, 255]) // first pixel is red

        try await task.send(.string("tap:45,120"))
        guard case .string(let reply) = try await task.receive() else {
            return XCTFail("expected a text reply")
        }
        XCTAssertEqual(reply, "tapped:45,120")
    }
}
