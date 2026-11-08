import CoreGraphics
import Foundation

/// Raw RGBA (straight alpha, like Flutter's ImageByteFormat.rawRgba) -> CGImage.
public func makeCGImage(rgba: Data, width: Int, height: Int) -> CGImage? {
    guard rgba.count == width * height * 4,
          let provider = CGDataProvider(data: rgba as CFData) else { return nil }
    return CGImage(
        width: width, height: height,
        bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}

/// Reads a CGImage back as RGBA bytes (used by tests to check pixels).
public func readRGBA(_ image: CGImage) -> [UInt8] {
    let w = image.width, h = image.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    buf.withUnsafeMutableBytes { p in
        let ctx = CGContext(
            data: p.baseAddress, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return buf
}
