import XCTest
import WatchProofs

/// P9 — Sustained transport: 100 frames at pixel ratio 1.0 and 2.0, in three encodings.
///   raw = full RGBA   zlib = full frame, deflated   delta = XOR with previous frame, deflated
/// Needs dart_tools/ws_stream_server.dart (CI starts it). Asserts only that every frame decodes
/// correctly; the speed numbers are LOGGED (debug build, loopback, optimistic frame content).
final class P9_TransportThroughputTests: XCTestCase {

    private func stream(ratio: Int, mode: String, frames: Int = 100) async throws {
        let w = 198 * ratio, h = 242 * ratio
        let url = URL(string: "ws://127.0.0.1:8766/?ratio=\(ratio)&mode=\(mode)&frames=\(frames)")!
        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = 8 * 1024 * 1024
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        var current = [UInt8](repeating: 0, count: w * h * 4)
        var measuredWire = 0
        var decodeNs: UInt64 = 0
        var startNs: UInt64 = 0

        for expected in 0..<frames {
            guard case .data(let msg) = try await task.receive() else {
                return XCTFail("frame \(expected): expected a binary message")
            }
            let t0 = DispatchTime.now().uptimeNanoseconds

            let index = UInt32(littleEndian: msg.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) })
            guard Int(index) == expected else { return XCTFail("frame order broken: got \(index), expected \(expected)") }
            let payload = msg.subdata(in: 4..<msg.count)

            switch mode {
            case "raw":
                current = [UInt8](payload)
            case "zlib":
                current = [UInt8](try (payload as NSData).decompressed(using: .zlib) as Data)
            case "delta":
                let diff = [UInt8](try (payload as NSData).decompressed(using: .zlib) as Data)
                current.withUnsafeMutableBufferPointer { cur in
                    diff.withUnsafeBufferPointer { d in
                        for i in 0..<cur.count { cur[i] ^= d[i] }
                    }
                }
            default:
                return XCTFail("unknown mode \(mode)")
            }

            let t1 = DispatchTime.now().uptimeNanoseconds
            if expected == 0 { startNs = t1 } else { measuredWire += msg.count; decodeNs += t1 - t0 }

            // the white square must be exactly where the server drew it for this frame
            let s = w / 20, x = (expected * 3) % (w - s), y = h / 2
            let i = ((y + s / 2) * w + (x + s / 2)) * 4
            guard current.count == w * h * 4, current[i] == 255, current[i + 1] == 255, current[i + 2] == 255 else {
                return XCTFail("frame \(expected): decoded pixels are wrong")
            }
        }

        let n = Double(frames - 1)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - startNs) / 1e6 / n
        let dec = Double(decodeNs) / 1e6 / n
        proofLog("P9: ratio=\(ratio).0 mode=\(mode) wire=\(Int(Double(measuredWire) / n)) B/frame, "
                 + String(format: "%.1f ms/frame (%d fps max), decode %.1f ms/frame", ms, Int(1000 / ms), dec))
    }

    func test_ratio1_raw()    async throws { try await stream(ratio: 1, mode: "raw") }
    func test_ratio1_zlib()   async throws { try await stream(ratio: 1, mode: "zlib") }
    func test_ratio1_delta()  async throws { try await stream(ratio: 1, mode: "delta") }
    func test_ratio2_raw()    async throws { try await stream(ratio: 2, mode: "raw") }
    func test_ratio2_zlib()   async throws { try await stream(ratio: 2, mode: "zlib") }
    func test_ratio2_delta()  async throws { try await stream(ratio: 2, mode: "delta") }
}
