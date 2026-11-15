import Foundation
import Network

public struct PathMonitorResult: Sendable {
    public let status: String
    public let unsatisfiedReason: String
}

/// Documented-behavior check: per TN3135 an NWPathMonitor stays unsatisfied on a physical watch
/// for normal apps, so this cannot tell which path URLSession used.
public enum PathMonitorProbe {
    public static func run(timeoutSeconds: TimeInterval = 2.0) async -> PathMonitorResult {
        await withCheckedContinuation { cont in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "gate0d.nwpathmonitor")
            let once = OnceFlag()

            monitor.pathUpdateHandler = { path in
                guard once.claim() else { return }
                monitor.cancel()
                let status: String
                switch path.status {
                case .satisfied: status = "satisfied"
                case .unsatisfied: status = "unsatisfied"
                case .requiresConnection: status = "requiresConnection"
                @unknown default: status = "unknown"
                }

                let reason: String
                if path.status == .satisfied {
                    reason = "none"
                } else {
                    switch path.unsatisfiedReason {
                    case .notAvailable: reason = "not_available"
                    case .cellularDenied: reason = "cellular_denied"
                    case .wifiDenied: reason = "wifi_denied"
                    case .localNetworkDenied: reason = "local_network_denied"
                    @unknown default: reason = "unknown"
                    }
                }
                cont.resume(returning: PathMonitorResult(status: status, unsatisfiedReason: reason))
            }

            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                guard once.claim() else { return }
                monitor.cancel()
                cont.resume(returning: PathMonitorResult(status: "unknown", unsatisfiedReason: "unknown"))
            }
        }
    }
}
