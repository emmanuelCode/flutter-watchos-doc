import XCTest
import SwiftUI
@testable import SpecCode

/// E1 (watch side) — the whole dev loop with no stand-ins:
///   real Flutter WatchFrameStreamer (via flutter test, started by scripts/run_e2e.sh)
///     -> WebSocket -> decode -> the spec's WatchFrameStore + WatchFrameView -> pixels checked
///   tap sent back -> real WatchInputInjector -> app changes -> next frame -> view shows the change.
/// Frame message = [uint32 LE width][uint32 LE height][uint32 LE frameId][raw RGBA]
final class E1_EndToEndTests: XCTestCase {

    private func decode(_ msg: URLSessionWebSocketTask.Message) throws -> (id: UInt32, image: CGImage) {
        guard case .data(let d) = msg, d.count > 12 else {
            throw NSError(domain: "E1", code: 1, userInfo: [NSLocalizedDescriptionKey: "expected a binary frame"])
        }
        func u32(_ o: Int) -> UInt32 {
            UInt32(littleEndian: d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) })
        }
        let w = Int(u32(0)), h = Int(u32(4)), id = u32(8)
        let rgba = [UInt8](d.subdata(in: 12..<d.count))
        guard rgba.count == w * h * 4 else {
            throw NSError(domain: "E1", code: 2, userInfo: [NSLocalizedDescriptionKey: "frame size mismatch: \(rgba.count) bytes for \(w)x\(h)"])
        }
        return (id, makeCGImage(rgba: rgba, width: w, height: h))
    }

    private func centreIsGreen(_ image: CGImage) -> Bool {
        let px = readRGBA(image)
        let i = ((image.height / 2) * image.width + image.width / 2) * 4
        return px[i] < 20 && px[i + 1] > 235 && px[i + 2] < 20
    }

    @MainActor
    private func scenario(_ task: URLSessionWebSocketTask) async throws {
        let store = WatchFrameStore()
        let renderer = makeRenderer(WatchFrameView(store: store).frame(width: 198, height: 242))

        // 1) The server calls captureNow() when we connect, so a frame arrives although the app is idle.
        let first = try decode(try await task.receive())
        XCTAssertEqual(first.image.width, 198)
        XCTAssertEqual(first.image.height, 242)
        store.latest = first.image
        assertNear(pixel(try pixels(renderer), 99, 121), [255, 0, 0, 255])        // the view shows RED

        // 2) Tap the middle of the watch screen. The server maps it into app coordinates and replays it.
        try await task.send(.string("tap:99,121"))
        var second: (id: UInt32, image: CGImage)?
        for _ in 0..<10 {
            let f = try decode(try await task.receive())
            if f.id > first.id && centreIsGreen(f.image) { second = f; break }
        }
        let next = try XCTUnwrap(second, "no green frame arrived after the tap")

        // 3) Publish it; the same live view must now show GREEN.
        store.latest = next.image
        try await Task.sleep(nanoseconds: 400_000_000)
        assertNear(pixel(try pixels(renderer), 99, 121), [0, 255, 0, 255])

        proofLog("E1: frame \(first.id) (red) -> tap(99,121) -> frame \(next.id) (green); view showed both")
    }

    @MainActor
    func test_real_streamer_to_real_view_and_tap_back() async throws {
        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:8767")!)
        task.maximumMessageSize = 8 * 1024 * 1024
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        do {
            try await scenario(task)
        } catch {
            try? await task.send(.string("done"))   // let the Flutter side stop waiting
            throw error
        }
        try await task.send(.string("done"))
        try await Task.sleep(nanoseconds: 200_000_000)
    }
}
