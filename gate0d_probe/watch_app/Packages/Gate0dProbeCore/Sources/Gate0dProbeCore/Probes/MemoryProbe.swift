import CProbeShims
import Foundation

public struct MemorySnapshot: Sendable {
    public let residentMB: Double
    public let physFootprintMB: Double
    public let availableMB: Double?

    public var availableString: String {
        if let avail = availableMB {
            return ProbeStats.fmt(avail)
        }
        return "UNSUPPORTED"
    }
}

public enum MemoryProbe {
    public static func snapshot() -> MemorySnapshot {
        var res: Double = 0
        var fp: Double = 0
        var avail: Double = -1
        _ = probe_memory_snapshot(&res, &fp, &avail)
        return MemorySnapshot(
            residentMB: res,
            physFootprintMB: fp,
            availableMB: avail >= 0 ? avail : nil
        )
    }
}
