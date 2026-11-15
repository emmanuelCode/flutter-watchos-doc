import CProbeShims
import Foundation
import WatchKit

public struct CapturedContext: Sendable {
    public let probeSpecVersion: String
    public let timestampUTC: String
    public let deviceModel: String
    public let watchOSVersion: String
    public let arch: String
    public let screenWidthPt: Int
    public let screenHeightPt: Int
    public let screenScale: Double
    public let launchMode: String
    public let atsProfile: String
    public let lowPowerMode: Bool
    public let thermalState: String
    public let luminanceReduced: Bool

    public var screenPtString: String { "\(screenWidthPt)x\(screenHeightPt)" }
    public var screenScaleString: String { String(format: "%.1f", screenScale) }
    public var nativeWidthPx: Int { max(1, Int((Double(screenWidthPt) * screenScale).rounded())) }
    public var nativeHeightPx: Int { max(1, Int((Double(screenHeightPt) * screenScale).rounded())) }
}

public enum ProbeContext {
    @MainActor
    public static func capture(luminanceReduced: Bool = false) -> CapturedContext {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let ts = iso.string(from: Date())

        var buf = [CChar](repeating: 0, count: 128)
        let modelRaw: String
        if probe_sysctl_machine(&buf, buf.count) == 0 {
            modelRaw = String(cString: buf)
        } else {
            modelRaw = "unknown"
        }
        let sanitizedModel = modelRaw
            .replacingOccurrences(of: ",", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let deviceModel = sanitizedModel.isEmpty ? "unknown" : sanitizedModel

        let v = ProcessInfo.processInfo.operatingSystemVersion
        let osVer = v.patchVersion > 0
            ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            : "\(v.majorVersion).\(v.minorVersion)"

        #if arch(arm64_32)
        let arch = "arm64_32"
        #elseif arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "arm64"
        #endif

        let dev = WKInterfaceDevice.current()
        let bounds = dev.screenBounds
        let wPt = max(1, Int(bounds.width.rounded()))
        let hPt = max(1, Int(bounds.height.rounded()))
        let scale = dev.screenScale > 0 ? Double(dev.screenScale) : 2.0

        let traced = probe_is_debugger_attached()
        let launchMode: String
        if traced == 1 {
            launchMode = "xcode_debugger"
        } else if traced == 0 {
            launchMode = "standalone_watch"
        } else {
            launchMode = "unknown"
        }

        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "nominal"
        }

        return CapturedContext(
            probeSpecVersion: "1",
            timestampUTC: ts,
            deviceModel: deviceModel,
            watchOSVersion: osVer,
            arch: arch,
            screenWidthPt: wPt,
            screenHeightPt: hPt,
            screenScale: scale,
            launchMode: launchMode,
            atsProfile: detectATSProfile(),
            lowPowerMode: lowPower,
            thermalState: thermal,
            luminanceReduced: luminanceReduced
        )
    }

    /// Reads the app's own Info.plist. Returns "unknown" when run inside a test bundle
    /// (no WKApplication key), so CI never reports a profile it did not observe.
    public static func detectATSProfile() -> String {
        guard let info = Bundle.main.infoDictionary else { return "unknown" }
        guard (info["WKApplication"] as? Bool) == true else { return "unknown" }
        if let ats = info["NSAppTransportSecurity"] as? [String: Any] {
            let arbitrary = (ats["NSAllowsArbitraryLoads"] as? Bool) == true
            let localNet = (ats["NSAllowsLocalNetworking"] as? Bool) == true
            if arbitrary || localNet {
                return "relaxed"
            }
        }
        return "strict"
    }
}
