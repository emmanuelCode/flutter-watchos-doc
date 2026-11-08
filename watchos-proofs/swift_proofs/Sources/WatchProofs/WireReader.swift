import Foundation

public enum DrawCmd: Equatable {
    case rect(x: Float, y: Float, w: Float, h: Float, color: UInt32)
    case text(x: Float, y: Float, color: UInt32, fontSize: Float, flags: UInt32, text: String)
}

/// Appendix A reader: bounds-checked, loadUnaligned, unknown-op bail-out.
/// Returns nil for a corrupt / truncated stream.
public func parseFrame(_ buffer: UnsafeRawPointer, byteCount: Int) -> [DrawCmd]? {
    var offset = 0
    var out: [DrawCmd] = []
    func need(_ n: Int) -> Bool { offset + n <= byteCount }
    func u32(_ at: Int) -> UInt32 { buffer.loadUnaligned(fromByteOffset: offset + at, as: UInt32.self) }
    func f32(_ at: Int) -> Float { buffer.loadUnaligned(fromByteOffset: offset + at, as: Float.self) }

    while need(4) {
        switch u32(0) {
        case 1: // DRAW_RECT
            guard need(24) else { return nil }
            out.append(.rect(x: f32(4), y: f32(8), w: f32(12), h: f32(16), color: u32(20)))
            offset += 24
        case 3: // DRAW_TEXT
            guard need(28) else { return nil }
            let len = Int(u32(24))
            guard need(28 + len) else { return nil }
            let p = buffer.advanced(by: offset + 28).assumingMemoryBound(to: UInt8.self)
            let s = String(decoding: UnsafeBufferPointer(start: p, count: len), as: UTF8.self)
            out.append(.text(x: f32(4), y: f32(8), color: u32(12), fontSize: f32(16), flags: u32(20), text: s))
            let raw = 28 + len
            let pad = (4 - raw % 4) % 4
            guard need(raw + pad) else { return nil }
            offset += raw + pad
        default:
            return nil
        }
    }
    return offset == byteCount ? out : nil
}
