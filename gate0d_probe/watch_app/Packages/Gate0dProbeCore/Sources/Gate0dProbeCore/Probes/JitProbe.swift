import CProbeShims
import Darwin
import Foundation

public struct JitProbeResult: Sendable {
    public let mmapStatus: ProbeStatus
    public let mmapDetail: String
    public let mprotectStatus: ProbeStatus
    public let mprotectDetail: String
}

/// Only checks allocation / protection return values. Never executes the mapped memory.
public enum JitProbe {
    private static func classify(_ err: Int32) -> ProbeStatus {
        (err == EPERM || err == EACCES || err == ENOTSUP) ? .blockedByOS : .fail
    }

    public static func run() -> JitProbeResult {
        var mmapErr: Int32 = 0
        let mmapRc = probe_jit_mmap(&mmapErr)
        let mmapStatus: ProbeStatus
        let mmapDetail: String
        if mmapRc == 1 {
            mmapStatus = .allowed
            mmapDetail = ProbeDetail.none
        } else if mmapRc == -1 {
            mmapStatus = .skipped
            mmapDetail = ProbeDetail.unsupported
        } else {
            mmapStatus = classify(mmapErr)
            mmapDetail = ProbeDetail.posix(mmapErr)
        }

        var protErr: Int32 = 0
        let protRc = probe_jit_mprotect(&protErr)
        let protStatus: ProbeStatus
        let protDetail: String
        if protRc == 1 {
            protStatus = .allowed
            protDetail = ProbeDetail.none
        } else {
            protStatus = classify(protErr)
            protDetail = ProbeDetail.posix(protErr)
        }

        return JitProbeResult(
            mmapStatus: mmapStatus,
            mmapDetail: mmapDetail,
            mprotectStatus: protStatus,
            mprotectDetail: protDetail
        )
    }
}
