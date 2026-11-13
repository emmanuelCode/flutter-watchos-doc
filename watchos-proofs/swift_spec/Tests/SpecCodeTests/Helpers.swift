import SwiftUI
import XCTest

func makeCGImage(rgba: [UInt8], width: Int, height: Int) -> CGImage {
    makeCGImage(rgbaData: Data(rgba), width: width, height: height)
}

func makeCGImage(rgbaData: Data, width: Int, height: Int) -> CGImage {
    let provider = CGDataProvider(data: rgbaData as CFData)!
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, width: Int, height: Int) -> CGImage {
    var px = [UInt8]()
    for _ in 0..<(width * height) { px += [r, g, b, 255] }
    return makeCGImage(rgba: px, width: width, height: height)
}

func readRGBA(_ image: CGImage) -> [UInt8] {
    let w = image.width, h = image.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    buf.withUnsafeMutableBytes { p in
        let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return buf
}

@MainActor
func makeRenderer<V: View>(_ view: V) -> ImageRenderer<V> {
    let r = ImageRenderer(content: view)
    r.scale = 1
    return r
}

@MainActor
func pixels<V: View>(_ r: ImageRenderer<V>) throws -> (px: [UInt8], width: Int) {
    let img = try XCTUnwrap(r.cgImage, "ImageRenderer produced no image")
    return (readRGBA(img), img.width)
}

func pixel(_ p: (px: [UInt8], width: Int), _ x: Int, _ y: Int) -> [UInt8] {
    let i = (y * p.width + x) * 4
    return Array(p.px[i..<i + 4])
}

func assertNear(_ got: [UInt8], _ want: [Int], tol: Int = 4, file: StaticString = #filePath, line: UInt = #line) {
    for (g, w) in zip(got, want) {
        XCTAssertLessThanOrEqual(abs(Int(g) - w), tol, "got \(got) want \(want) (+-\(tol))", file: file, line: line)
    }
}

/// Appends a line to /tmp/watch_proofs/results.log (printed in the CI result sheet).
func proofLog(_ line: String) {
    let dir = "/tmp/watch_proofs"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let path = dir + "/results.log"
    let data = Data((line + "\n").utf8)
    if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(data); try? h.close() }
    else { FileManager.default.createFile(atPath: path, contents: data) }
}
