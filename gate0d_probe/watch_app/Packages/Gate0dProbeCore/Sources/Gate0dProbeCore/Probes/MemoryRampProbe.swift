import Foundation

public struct RampBreadcrumb: Codable, Sendable {
    public var rampInProgress: Bool
    public var lastOkMB: Double
    public var lastResidentMB: Double
    public var lastFootprintMB: Double
    public var lastAvailableMB: Double?
}

public struct MemoryRampSummary: Sendable {
    public let status: ProbeStatus
    public let prevUncleanExit: Bool
    public let prevLastOkMB: Double?
    public let prevLastResidentMB: Double?
    public let prevLastFootprintMB: Double?
    public let prevLastAvailableMB: Double?

    public static let skipped = MemoryRampSummary(
        status: .skipped,
        prevUncleanExit: false,
        prevLastOkMB: nil,
        prevLastResidentMB: nil,
        prevLastFootprintMB: nil,
        prevLastAvailableMB: nil
    )
}

/// Opt-in. Allocates incompressible memory in steps until the OS terminates the app, persisting a
/// breadcrumb after every step. An unclean exit is NOT proof of a jetsam kill (a swipe-away looks the same).
public enum MemoryRampProbe {
    public static func defaultStateURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("gate0d_ramp_state.json")
    }

    public static func inspectPreviousLaunch(stateURL: URL = defaultStateURL()) -> MemoryRampSummary {
        guard let data = try? Data(contentsOf: stateURL),
              let crumb = try? JSONDecoder().decode(RampBreadcrumb.self, from: data),
              crumb.rampInProgress else {
            return .skipped
        }
        clearState(stateURL: stateURL)
        return MemoryRampSummary(
            status: .skipped,
            prevUncleanExit: true,
            prevLastOkMB: crumb.lastOkMB,
            prevLastResidentMB: crumb.lastResidentMB,
            prevLastFootprintMB: crumb.lastFootprintMB,
            prevLastAvailableMB: crumb.lastAvailableMB
        )
    }

    public static func writeState(_ crumb: RampBreadcrumb, stateURL: URL = defaultStateURL()) {
        if let data = try? JSONEncoder().encode(crumb) {
            try? data.write(to: stateURL, options: [.atomic])
        }
    }

    public static func clearState(stateURL: URL = defaultStateURL()) {
        writeState(
            RampBreadcrumb(rampInProgress: false, lastOkMB: 0, lastResidentMB: 0, lastFootprintMB: 0, lastAvailableMB: nil),
            stateURL: stateURL
        )
    }

    public static func runRamp(
        stepMB: Int = 4,
        maxSteps: Int = 256,
        stateURL: URL = defaultStateURL(),
        shouldAbort: @Sendable () -> Bool
    ) -> MemoryRampSummary {
        var chunks: [Data] = []
        let chunkBytes = stepMB * 1024 * 1024
        var totalAllocatedMB = 0.0
        var rng: UInt64 = 0xD1B54A32D192ED03

        for _ in 0..<maxSteps {
            if shouldAbort() {
                clearState(stateURL: stateURL)
                return MemoryRampSummary(
                    status: .interrupted,
                    prevUncleanExit: false,
                    prevLastOkMB: nil,
                    prevLastResidentMB: nil,
                    prevLastFootprintMB: nil,
                    prevLastAvailableMB: nil
                )
            }

            var buf = Data(count: chunkBytes)
            buf.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return }
                let ptr = base.assumingMemoryBound(to: UInt64.self)
                let words = chunkBytes / MemoryLayout<UInt64>.stride
                // Fill EVERY word with pseudo-random data so the pages are dirty and incompressible
                // (touching one word per page would leave the rest zero and compressible).
                for i in 0..<words {
                    rng ^= rng >> 12
                    rng ^= rng << 25
                    rng ^= rng >> 27
                    ptr[i] = rng &* 0x2545F4914F6CDD1D
                }
            }
            chunks.append(buf)
            totalAllocatedMB += Double(stepMB)

            let snap = MemoryProbe.snapshot()
            writeState(
                RampBreadcrumb(
                    rampInProgress: true,
                    lastOkMB: totalAllocatedMB,
                    lastResidentMB: snap.residentMB,
                    lastFootprintMB: snap.physFootprintMB,
                    lastAvailableMB: snap.availableMB
                ),
                stateURL: stateURL
            )
        }

        let final = MemoryProbe.snapshot()
        clearState(stateURL: stateURL)
        _ = chunks.count
        return MemoryRampSummary(
            status: .allowed,
            prevUncleanExit: false,
            prevLastOkMB: totalAllocatedMB,
            prevLastResidentMB: final.residentMB,
            prevLastFootprintMB: final.physFootprintMB,
            prevLastAvailableMB: final.availableMB
        )
    }
}
