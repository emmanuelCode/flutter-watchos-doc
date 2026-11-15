import CProbeShims
import Foundation

public struct LanTransportResult: Sendable {
    public let getaddrinfoStatus: ProbeStatus
    public let getaddrinfoMs: Double?
    public let getaddrinfoAddrCount: Int
    public let getaddrinfoDetail: String

    public let httpPingLocalStatus: ProbeStatus
    public let httpPingLocalRttMs: Double?
    public let httpPingLocalDetail: String

    public let pingStatus: ProbeStatus
    public let pingStats: (min: Double, p50: Double, p95: Double, max: Double)?

    public let stream4kbStatus: ProbeStatus
    public let stream4kbTtfbMs: Double?
    public let stream4kbKbps: Double?

    public let stream1xStatus: ProbeStatus
    public let stream1xBytes: Int
    public let stream1xTtfbMs: Double?
    public let stream1xKbps: Double?

    public let streamNativeStatus: ProbeStatus
    public let streamNativeBytes: Int
    public let streamNativeTtfbMs: Double?
    public let streamNativeKbps: Double?

    public let postInputStatus: ProbeStatus
    public let postInputStats: (min: Double, p50: Double, p95: Double, max: Double)?
}

public enum LanTransportProbe {
    public static func run(config: ProbeRunConfig, context: CapturedContext) async -> LanTransportResult {
        let oneXChunkBytes = context.screenWidthPt * context.screenHeightPt * 4
        let nativeChunkBytes = context.nativeWidthPx * context.nativeHeightPx * 4

        // .local (mDNS) checks
        var gaiStatus: ProbeStatus = .skipped
        var gaiMs: Double? = nil
        var gaiCount = 0
        var gaiDetail = ProbeDetail.none

        var localPingStatus: ProbeStatus = .skipped
        var localPingMs: Double? = nil
        var localPingDetail = ProbeDetail.none

        let localHost = config.localHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if !localHost.isEmpty {
            var count: Int32 = 0
            var elapsed: Double = 0
            var gErr: Int32 = 0
            let ok = probe_getaddrinfo_local(localHost, &count, &elapsed, &gErr)
            if ok == 1 {
                gaiStatus = .allowed
                gaiMs = elapsed
                gaiCount = Int(count)
            } else {
                gaiStatus = .fail
                gaiDetail = ProbeDetail.posix(gErr)
            }
            if let localURL = URL(string: "http://\(localHost):\(config.httpPort)/ping") {
                let res = await NetworkBlockProbe.httpPing(url: localURL, timeoutSeconds: config.timeoutSeconds)
                localPingStatus = res.0
                localPingMs = res.1
                localPingDetail = res.2
            }
        }

        let hostIP = config.hostIP.trimmingCharacters(in: .whitespacesAndNewlines)
        if hostIP.isEmpty {
            return LanTransportResult(
                getaddrinfoStatus: gaiStatus, getaddrinfoMs: gaiMs, getaddrinfoAddrCount: gaiCount, getaddrinfoDetail: gaiDetail,
                httpPingLocalStatus: localPingStatus, httpPingLocalRttMs: localPingMs, httpPingLocalDetail: localPingDetail,
                pingStatus: .skipped, pingStats: nil,
                stream4kbStatus: .skipped, stream4kbTtfbMs: nil, stream4kbKbps: nil,
                stream1xStatus: .skipped, stream1xBytes: oneXChunkBytes, stream1xTtfbMs: nil, stream1xKbps: nil,
                streamNativeStatus: .skipped, streamNativeBytes: nativeChunkBytes, streamNativeTtfbMs: nil, streamNativeKbps: nil,
                postInputStatus: .skipped, postInputStats: nil
            )
        }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = max(config.timeoutSeconds, 10.0)
        // A native-size stream is ~25 MB; give slow watch Wi-Fi room before our own timeout trips.
        cfg.timeoutIntervalForResource = 90.0
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }

        // 1. N=20 sequential ping RTT (after one warmup)
        let pingURL = URL(string: "http://\(hostIP):\(config.httpPort)/ping")!
        var pingSamples: [Double] = []
        var pingStatus: ProbeStatus = .allowed
        _ = try? await session.data(from: pingURL)
        for _ in 0..<20 {
            if Task.isCancelled { pingStatus = .interrupted; break }
            let t0 = DispatchTime.now().uptimeNanoseconds
            do {
                let (_, resp) = try await session.data(from: pingURL)
                let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                    pingStatus = .fail
                    break
                }
                pingSamples.append(ms)
            } catch {
                pingStatus = Task.isCancelled ? .interrupted : .fail
                break
            }
        }
        let pingStats: (min: Double, p50: Double, p95: Double, max: Double)? =
            (pingStatus == .allowed && pingSamples.count == 20) ? ProbeStats.percentilesMs(pingSamples) : nil

        // 2. URLSession.bytes streams. NOTE: AsyncBytes yields one byte at a time, so the reported
        // kbps is a LOWER BOUND that includes per-byte iteration overhead on the watch CPU.
        let s4k = await measureStream(session: session, host: hostIP, port: config.httpPort, frames: 30, chunkBytes: 4096)
        let s1x = await measureStream(session: session, host: hostIP, port: config.httpPort, frames: 30, chunkBytes: oneXChunkBytes)
        let snat = await measureStream(session: session, host: hostIP, port: config.httpPort, frames: 30, chunkBytes: nativeChunkBytes)

        // 3. N=20 sequential POST /input
        let inputURL = URL(string: "http://\(hostIP):\(config.httpPort)/input")!
        let tapPayload = Data(repeating: 0x42, count: 32)
        var postSamples: [Double] = []
        var postStatus: ProbeStatus = .allowed
        for _ in 0..<20 {
            if Task.isCancelled { postStatus = .interrupted; break }
            var req = URLRequest(url: inputURL)
            req.httpMethod = "POST"
            req.httpBody = tapPayload
            let t0 = DispatchTime.now().uptimeNanoseconds
            do {
                let (_, resp) = try await session.data(for: req)
                let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                    postStatus = .fail
                    break
                }
                postSamples.append(ms)
            } catch {
                postStatus = Task.isCancelled ? .interrupted : .fail
                break
            }
        }
        let postStats: (min: Double, p50: Double, p95: Double, max: Double)? =
            (postStatus == .allowed && postSamples.count == 20) ? ProbeStats.percentilesMs(postSamples) : nil

        return LanTransportResult(
            getaddrinfoStatus: gaiStatus, getaddrinfoMs: gaiMs, getaddrinfoAddrCount: gaiCount, getaddrinfoDetail: gaiDetail,
            httpPingLocalStatus: localPingStatus, httpPingLocalRttMs: localPingMs, httpPingLocalDetail: localPingDetail,
            pingStatus: pingStatus, pingStats: pingStats,
            stream4kbStatus: s4k.0, stream4kbTtfbMs: s4k.1, stream4kbKbps: s4k.2,
            stream1xStatus: s1x.0, stream1xBytes: oneXChunkBytes, stream1xTtfbMs: s1x.1, stream1xKbps: s1x.2,
            streamNativeStatus: snat.0, streamNativeBytes: nativeChunkBytes, streamNativeTtfbMs: snat.1, streamNativeKbps: snat.2,
            postInputStatus: postStatus, postInputStats: postStats
        )
    }

    private static func measureStream(
        session: URLSession,
        host: String,
        port: UInt16,
        frames: Int,
        chunkBytes: Int
    ) async -> (ProbeStatus, Double?, Double?) {
        guard !Task.isCancelled else { return (.interrupted, nil, nil) }
        guard let url = URL(string: "http://\(host):\(port)/stream?frames=\(frames)&bytes=\(chunkBytes)") else {
            return (.fail, nil, nil)
        }
        let expected = frames * chunkBytes
        let t0 = DispatchTime.now().uptimeNanoseconds
        var ttfbMs: Double? = nil
        var count = 0
        var sinceCheck = 0
        do {
            let (bytes, resp) = try await session.bytes(from: url)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                return (.fail, nil, nil)
            }
            for try await _ in bytes {
                if ttfbMs == nil {
                    ttfbMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
                }
                count += 1
                sinceCheck += 1
                if sinceCheck >= 4096 {
                    sinceCheck = 0
                    if Task.isCancelled { return (.interrupted, nil, nil) }
                }
            }
            let elapsedSec = max(1e-6, Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9)
            if count != expected {
                return (.fail, nil, nil)
            }
            let kbps = (Double(count) * 8.0 / 1000.0) / elapsedSec
            return (.allowed, ttfbMs ?? 0.0, kbps)
        } catch {
            return (Task.isCancelled ? .interrupted : .fail, nil, nil)
        }
    }
}
