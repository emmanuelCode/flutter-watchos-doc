import CoreGraphics
import Foundation

public struct FrameDecodeResult: Sendable {
    public let px1x: String
    public let pxNative: String
    public let zlib1xStaticBytes: Int
    public let zlib1xStaticP50Ms: Double
    public let zlib1xStaticMaxMs: Double
    public let zlib1xNoisyBytes: Int
    public let zlib1xNoisyP50Ms: Double
    public let zlib1xNoisyMaxMs: Double
    public let zlibNativeStaticBytes: Int
    public let zlibNativeStaticP50Ms: Double
    public let zlibNativeStaticMaxMs: Double
    public let zlibNativeNoisyBytes: Int
    public let zlibNativeNoisyP50Ms: Double
    public let zlibNativeNoisyMaxMs: Double
    public let drawRgbaP50Ms: Double
    public let drawRgbaMaxMs: Double
    public let drawPremulP50Ms: Double
    public let drawPremulMaxMs: Double
}

/// Offline CPU benchmark. Apple's `.zlib` is raw deflate, matching the repo's wire format
/// (`ZLibCodec(raw: true)` in ws_stream_server.dart, decoded in CI check P9).
public enum FrameDecodeProbe {
    private static func makeStaticRGBA(width: Int, height: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let yStart = height / 2 - 4
        let yEnd = min(height, yStart + 8)
        if yStart >= 0 {
            for y in yStart..<yEnd {
                for x in (width / 4)..<(3 * width / 4) {
                    let i = (y * width + x) * 4
                    bytes[i] = 255
                    bytes[i + 1] = 255
                    bytes[i + 2] = 255
                    bytes[i + 3] = 255
                }
            }
        }
        return Data(bytes)
    }

    private static func makeNoisyRGBA(width: Int, height: Int) -> Data {
        let count = width * height * 4
        var bytes = [UInt8](repeating: 0, count: count)
        var rng: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<count {
            rng ^= rng >> 12
            rng ^= rng << 25
            rng ^= rng >> 27
            bytes[i] = UInt8(truncatingIfNeeded: rng &* 0x2545F4914F6CDD1D)
        }
        return Data(bytes)
    }

    private static func benchZlib(raw: Data, iterations: Int = 100) -> (Int, Double, Double) {
        guard let compressed = try? (raw as NSData).compressed(using: .zlib) as Data else {
            return (0, 0, 0)
        }
        _ = try? (compressed as NSData).decompressed(using: .zlib) // warmup

        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = try? (compressed as NSData).decompressed(using: .zlib)
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
        }
        let s = ProbeStats.percentilesMs(samples)
        return (compressed.count, s.p50, s.max)
    }

    private static func benchCGDraw(rgba: Data, width: Int, height: Int, premultiplied: Bool, iterations: Int = 100) -> (Double, Double) {
        var outBuf = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let srcAlpha: CGImageAlphaInfo = premultiplied ? .premultipliedLast : .last

        return outBuf.withUnsafeMutableBytes { ptr -> (Double, Double) in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return (0, 0)
            }

            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            var samples: [Double] = []
            samples.reserveCapacity(iterations)

            for _ in 0..<iterations {
                let t0 = DispatchTime.now().uptimeNanoseconds
                if let provider = CGDataProvider(data: rgba as CFData),
                   let img = CGImage(
                       width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: srcAlpha.rawValue),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent
                   ) {
                    ctx.draw(img, in: rect)
                }
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
            }
            let s = ProbeStats.percentilesMs(samples)
            return (s.p50, s.max)
        }
    }

    public static func run(context: CapturedContext) -> FrameDecodeResult {
        let w1 = context.screenWidthPt
        let h1 = context.screenHeightPt
        let wn = context.nativeWidthPx
        let hn = context.nativeHeightPx

        let z1Static = benchZlib(raw: makeStaticRGBA(width: w1, height: h1))
        let z1Noisy = benchZlib(raw: makeNoisyRGBA(width: w1, height: h1))

        let rawNStatic = makeStaticRGBA(width: wn, height: hn)
        let zNStatic = benchZlib(raw: rawNStatic)
        let zNNoisy = benchZlib(raw: makeNoisyRGBA(width: wn, height: hn))

        let drawRgba = benchCGDraw(rgba: rawNStatic, width: wn, height: hn, premultiplied: false)
        let drawPremul = benchCGDraw(rgba: rawNStatic, width: wn, height: hn, premultiplied: true)

        return FrameDecodeResult(
            px1x: "\(w1)x\(h1)",
            pxNative: "\(wn)x\(hn)",
            zlib1xStaticBytes: z1Static.0, zlib1xStaticP50Ms: z1Static.1, zlib1xStaticMaxMs: z1Static.2,
            zlib1xNoisyBytes: z1Noisy.0, zlib1xNoisyP50Ms: z1Noisy.1, zlib1xNoisyMaxMs: z1Noisy.2,
            zlibNativeStaticBytes: zNStatic.0, zlibNativeStaticP50Ms: zNStatic.1, zlibNativeStaticMaxMs: zNStatic.2,
            zlibNativeNoisyBytes: zNNoisy.0, zlibNativeNoisyP50Ms: zNNoisy.1, zlibNativeNoisyMaxMs: zNNoisy.2,
            drawRgbaP50Ms: drawRgba.0, drawRgbaMaxMs: drawRgba.1,
            drawPremulP50Ms: drawPremul.0, drawPremulMaxMs: drawPremul.1
        )
    }
}
