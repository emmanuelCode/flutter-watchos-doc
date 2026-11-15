import Foundation
import Network
import os

public enum ProbeStatus: String, Sendable {
    case allowed = "ALLOWED"
    case blockedByOS = "BLOCKED_BY_OS"
    case fail = "FAIL"
    case timeout = "TIMEOUT"
    case interrupted = "INTERRUPTED"
    case skipped = "SKIPPED"
}

public enum IPhoneLinkState: String, CaseIterable, Sendable {
    case available = "available"
    case unavailable = "unavailable"
}

public enum LanRouterInternetState: String, CaseIterable, Sendable {
    case yes = "yes"
    case no = "no"
    case offlineTest = "offline_test"
}

public enum ProbeDetail {
    public static let none = "none"
    public static let waitingEnetdown = "WAITING(ENETDOWN)"
    public static let deferredToV1_1 = "deferred_to_v1_1"
    public static let sceneLeftActive = "scene_left_active"
    public static let userCancelled = "user_cancelled"
    public static let cleanExit = "clean_exit"
    public static let timeout = "timeout"
    public static let skippedControlFailed = "skipped_control_failed"
    public static let unsupported = "unsupported"

    public static func posix(_ code: Int32) -> String {
        "POSIX:\(code)"
    }

    /// Only ever emits `domain:code`. Never uses localizedDescription or String(describing:),
    /// because those can contain URLs, hosts or IP addresses.
    public static func sanitize(error: Error) -> String {
        if let nwErr = error as? NWError {
            switch nwErr {
            case .posix(let code):
                return "NSPOSIXErrorDomain:\(code.rawValue)"
            case .dns(let dnsCode):
                return "NWError:\(dnsCode)"
            case .tls(let osStatus):
                return "NWError:\(osStatus)"
            @unknown default:
                return "NWError:-1"
            }
        }
        let nsErr = error as NSError
        if nsErr.domain == NSPOSIXErrorDomain {
            return "NSPOSIXErrorDomain:\(nsErr.code)"
        }
        if nsErr.domain == NSURLErrorDomain {
            return "NSURLErrorDomain:\(nsErr.code)"
        }
        // TODO(author): the validator allowlist has no "other domain" token, so unknown domains
        // are folded into NSURLErrorDomain. Decide whether to add an explicit OtherDomain token.
        return "NSURLErrorDomain:\(nsErr.code)"
    }
}

public struct ProbeRunConfig: Sendable {
    public var hostIP: String
    public var localHost: String
    public var tcpPort: UInt16
    public var httpPort: UInt16
    public var httpsPort: UInt16?
    public var iphoneLink: IPhoneLinkState
    public var lanRouterInternet: LanRouterInternetState
    public var timeoutSeconds: TimeInterval

    public init(
        hostIP: String = "",
        localHost: String = "",
        tcpPort: UInt16 = 8770,
        httpPort: UInt16 = 8771,
        httpsPort: UInt16? = nil,
        iphoneLink: IPhoneLinkState = .available,
        lanRouterInternet: LanRouterInternetState = .yes,
        timeoutSeconds: TimeInterval = 5.0
    ) {
        self.hostIP = hostIP
        self.localHost = localHost
        self.tcpPort = tcpPort
        self.httpPort = httpPort
        self.httpsPort = httpsPort
        self.iphoneLink = iphoneLink
        self.lanRouterInternet = lanRouterInternet
        self.timeoutSeconds = timeoutSeconds
    }
}

public final class OnceFlag: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)
    public init() {}
    public func claim() -> Bool {
        lock.withLock { done in
            if done { return false }
            done = true
            return true
        }
    }
}

public struct ProbeStats {
    public static func percentilesMs(_ samples: [Double]) -> (min: Double, p50: Double, p95: Double, max: Double) {
        guard !samples.isEmpty else { return (0, 0, 0, 0) }
        let sorted = samples.sorted()
        let count = sorted.count
        let p50 = sorted[(count - 1) / 2]
        let p95Index = Int(Double(count - 1) * 0.95)
        let p95 = sorted[min(count - 1, max(0, p95Index))]
        return (sorted.first!, p50, p95, sorted.last!)
    }

    public static func fmt(_ value: Double, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f", value)
    }
}

public struct Gate0dReportData: Sendable {
    public var fields: [String: String] = [:]

    public init() {}

    public mutating func set(_ key: String, _ value: String) {
        fields[key] = value
    }
}
