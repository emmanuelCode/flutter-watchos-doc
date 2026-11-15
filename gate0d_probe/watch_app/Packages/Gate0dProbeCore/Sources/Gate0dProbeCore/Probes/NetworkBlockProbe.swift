import CProbeShims
import Darwin
import Foundation
import Network

/// Captures a coarse, heuristic path hint from URLSessionTaskMetrics. It never emits addresses.
/// `isCellular` is the only signal that proves anything; everything else stays "unknown".
/// The RTT difference between Run 1 and Run 2 is the real evidence of a companion relay.
public final class MetricsCaptureDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var capturedPathHint = "unknown"
    private var capturedProtocol = "na"
    private let lock = NSLock()

    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let tx = metrics.transactionMetrics.last else { return }
        let hint: String
        if tx.isCellular {
            hint = "cellular"
        } else if tx.isProxyConnection {
            hint = "companion_proxy"
        } else {
            hint = "unknown"
        }

        let protoRaw = (tx.networkProtocolName ?? "").lowercased()
        let proto: String
        switch protoRaw {
        case "h2": proto = "h2"
        case "h3": proto = "h3"
        case "http/1.1", "http/1.0": proto = "http/1.1"
        case "": proto = "na"
        default: proto = "other"
        }

        lock.lock()
        capturedPathHint = hint
        capturedProtocol = proto
        lock.unlock()
    }

    public func snapshot() -> (pathHint: String, protocolName: String) {
        lock.lock()
        defer { lock.unlock() }
        return (capturedPathHint, capturedProtocol)
    }
}

private final class NWWaitingHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var lastWaitingError: NWError?
    func set(_ err: NWError) { lock.lock(); lastWaitingError = err; lock.unlock() }
    func get() -> NWError? { lock.lock(); defer { lock.unlock() }; return lastWaitingError }
}

public struct ControlAndLowLevelResult: Sendable {
    public let netPathHint: String
    public let netActualProtocol: String

    public let httpPingStatus: ProbeStatus
    public let httpPingRttMs: Double?
    public let httpPingDetail: String

    public let httpsPingStatus: ProbeStatus
    public let httpsPingRttMs: Double?
    public let httpsPingDetail: String

    public let bsdTcpStatus: ProbeStatus
    public let bsdTcpRttMs: Double?
    public let bsdTcpDetail: String

    public let nwTcpStatus: ProbeStatus
    public let nwTcpRttMs: Double?
    public let nwTcpDetail: String

    public let wsStatus: ProbeStatus
    public let wsRttMs: Double?
    public let wsDetail: String
}

public enum NetworkBlockProbe {
    private static func isPolicyBlock(posix code: Int32) -> Bool {
        code == EPERM || code == EACCES || code == ENETDOWN
    }

    /// Returns (status, rttMs, detail, pathHint, protocol). Any HTTP 200 counts as a successful control.
    public static func httpPing(url: URL, timeoutSeconds: TimeInterval) async -> (ProbeStatus, Double?, String, String, String) {
        let delegate = MetricsCaptureDelegate()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeoutSeconds
        cfg.timeoutIntervalForResource = timeoutSeconds
        let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let t0 = DispatchTime.now().uptimeNanoseconds
        do {
            let (_, resp) = try await session.data(from: url)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
            let m = delegate.snapshot()
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                return (.fail, nil, "NSURLErrorDomain:-1011", m.pathHint, m.protocolName)
            }
            return (.allowed, ms, ProbeDetail.none, m.pathHint, m.protocolName)
        } catch {
            let nsErr = error as NSError
            let isTimeout = nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorTimedOut
            return (isTimeout ? .timeout : .fail, nil, ProbeDetail.sanitize(error: error), "unknown", "na")
        }
    }

    private static func skippedAll(detail: String) -> ControlAndLowLevelResult {
        ControlAndLowLevelResult(
            netPathHint: "unknown", netActualProtocol: "na",
            httpPingStatus: .skipped, httpPingRttMs: nil, httpPingDetail: ProbeDetail.none,
            httpsPingStatus: .skipped, httpsPingRttMs: nil, httpsPingDetail: ProbeDetail.none,
            bsdTcpStatus: .skipped, bsdTcpRttMs: nil, bsdTcpDetail: detail,
            nwTcpStatus: .skipped, nwTcpRttMs: nil, nwTcpDetail: detail,
            wsStatus: .skipped, wsRttMs: nil, wsDetail: detail
        )
    }

    public static func run(config: ProbeRunConfig) async -> ControlAndLowLevelResult {
        if config.hostIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return skippedAll(detail: ProbeDetail.none)
        }

        let httpURL = URL(string: "http://\(config.hostIP):\(config.httpPort)/ping")!
        let (httpSt, httpMs, httpDet, pathHint, actualProto) = await httpPing(url: httpURL, timeoutSeconds: config.timeoutSeconds)

        var httpsSt: ProbeStatus = .skipped
        var httpsMs: Double? = nil
        var httpsDet = ProbeDetail.none
        if let hp = config.httpsPort, let httpsURL = URL(string: "https://\(config.hostIP):\(hp)/ping") {
            let res = await httpPing(url: httpsURL, timeoutSeconds: config.timeoutSeconds)
            httpsSt = res.0; httpsMs = res.1; httpsDet = res.2
        }

        // The LAN host must be proven reachable by a high-level request. An ATS refusal proves nothing
        // about reachability, so it does NOT count; low-level results would be unattributable.
        let controlReachable = (httpSt == .allowed || httpsSt == .allowed)
        if !controlReachable {
            return ControlAndLowLevelResult(
                netPathHint: pathHint, netActualProtocol: actualProto,
                httpPingStatus: httpSt, httpPingRttMs: httpMs, httpPingDetail: httpDet,
                httpsPingStatus: httpsSt, httpsPingRttMs: httpsMs, httpsPingDetail: httpsDet,
                bsdTcpStatus: .skipped, bsdTcpRttMs: nil, bsdTcpDetail: ProbeDetail.skippedControlFailed,
                nwTcpStatus: .skipped, nwTcpRttMs: nil, nwTcpDetail: ProbeDetail.skippedControlFailed,
                wsStatus: .skipped, wsRttMs: nil, wsDetail: ProbeDetail.skippedControlFailed
            )
        }

        async let bsd = testBsdSocket(host: config.hostIP, port: config.tcpPort, timeoutSeconds: config.timeoutSeconds)
        async let nw = testNWConnection(host: config.hostIP, port: config.tcpPort, timeoutSeconds: config.timeoutSeconds)
        async let ws = testWebSocket(host: config.hostIP, port: config.httpPort, timeoutSeconds: config.timeoutSeconds)
        let (bsdRes, nwRes, wsRes) = await (bsd, nw, ws)

        return ControlAndLowLevelResult(
            netPathHint: pathHint, netActualProtocol: actualProto,
            httpPingStatus: httpSt, httpPingRttMs: httpMs, httpPingDetail: httpDet,
            httpsPingStatus: httpsSt, httpsPingRttMs: httpsMs, httpsPingDetail: httpsDet,
            bsdTcpStatus: bsdRes.0, bsdTcpRttMs: bsdRes.1, bsdTcpDetail: bsdRes.2,
            nwTcpStatus: nwRes.0, nwTcpRttMs: nwRes.1, nwTcpDetail: nwRes.2,
            wsStatus: wsRes.0, wsRttMs: wsRes.1, wsDetail: wsRes.2
        )
    }

    private static func testBsdSocket(host: String, port: UInt16, timeoutSeconds: TimeInterval) async -> (ProbeStatus, Double?, String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var rtt: Double = 0
                var err: Int32 = 0
                let rc = probe_bsd_tcp_connect(host, port, Int32(timeoutSeconds * 1000.0), &rtt, &err)
                if rc == 1 {
                    cont.resume(returning: (.allowed, rtt, ProbeDetail.none))
                } else if rc == -1 {
                    cont.resume(returning: (.timeout, nil, ProbeDetail.timeout))
                } else {
                    let st: ProbeStatus = isPolicyBlock(posix: err) ? .blockedByOS : .fail
                    cont.resume(returning: (st, nil, ProbeDetail.posix(err)))
                }
            }
        }
    }

    private static func testNWConnection(host: String, port: UInt16, timeoutSeconds: TimeInterval) async -> (ProbeStatus, Double?, String) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            return (.fail, nil, ProbeDetail.posix(EINVAL))
        }
        return await withCheckedContinuation { cont in
            let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let queue = DispatchQueue(label: "gate0d.nwconn")
            let once = OnceFlag()
            let holder = NWWaitingHolder()
            let t0 = DispatchTime.now().uptimeNanoseconds

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard once.claim() else { return }
                    let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
                    conn.cancel()
                    cont.resume(returning: (.allowed, ms, ProbeDetail.none))
                case .waiting(let err):
                    holder.set(err)
                case .failed(let err):
                    guard once.claim() else { return }
                    conn.cancel()
                    var blocked = false
                    if case .posix(let code) = err, code == .ENETDOWN || code == .EPERM || code == .EACCES {
                        blocked = true
                    }
                    cont.resume(returning: (blocked ? .blockedByOS : .fail, nil, ProbeDetail.sanitize(error: err)))
                default:
                    break
                }
            }

            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                guard once.claim() else { return }
                conn.cancel()
                if let waitErr = holder.get() {
                    // Only the documented signature (.waiting + ENETDOWN) counts as an OS block.
                    // Any other waiting reason (e.g. host unreachable) is a plain failure.
                    if case .posix(let code) = waitErr, code == .ENETDOWN {
                        cont.resume(returning: (.blockedByOS, nil, ProbeDetail.waitingEnetdown))
                    } else {
                        cont.resume(returning: (.fail, nil, ProbeDetail.sanitize(error: waitErr)))
                    }
                    return
                }
                cont.resume(returning: (.timeout, nil, ProbeDetail.timeout))
            }
        }
    }

    private static func testWebSocket(host: String, port: UInt16, timeoutSeconds: TimeInterval) async -> (ProbeStatus, Double?, String) {
        guard let wsURL = URL(string: "ws://\(host):\(port)/ws") else {
            return (.fail, nil, ProbeDetail.posix(EINVAL))
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeoutSeconds
        cfg.timeoutIntervalForResource = timeoutSeconds
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }

        let task = session.webSocketTask(with: wsURL)
        task.resume()
        let t0 = DispatchTime.now().uptimeNanoseconds

        return await withCheckedContinuation { cont in
            let once = OnceFlag()
            let queue = DispatchQueue(label: "gate0d.ws")

            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                guard once.claim() else { return }
                task.cancel(with: .goingAway, reason: nil)
                cont.resume(returning: (.timeout, nil, ProbeDetail.timeout))
            }

            Task {
                do {
                    try await task.send(.string("gate0d-ws"))
                    let msg = try await task.receive()
                    let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
                    task.cancel(with: .normalClosure, reason: nil)
                    guard once.claim() else { return }
                    if case .string(let s) = msg, s == "gate0d-ws" {
                        cont.resume(returning: (.allowed, ms, ProbeDetail.none))
                    } else {
                        cont.resume(returning: (.fail, nil, "NSURLErrorDomain:-1011"))
                    }
                } catch {
                    task.cancel(with: .abnormalClosure, reason: nil)
                    guard once.claim() else { return }
                    let nsErr = error as NSError
                    let st: ProbeStatus
                    if nsErr.domain == NSPOSIXErrorDomain && isPolicyBlock(posix: Int32(truncatingIfNeeded: nsErr.code)) {
                        st = .blockedByOS
                    } else if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorTimedOut {
                        st = .timeout
                    } else {
                        st = .fail
                    }
                    cont.resume(returning: (st, nil, ProbeDetail.sanitize(error: error)))
                }
            }
        }
    }
}
