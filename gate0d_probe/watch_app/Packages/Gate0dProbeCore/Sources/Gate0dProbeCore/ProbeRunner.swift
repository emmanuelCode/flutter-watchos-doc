import Combine
import Foundation
import os

/// Orchestrates the probes. Every run goes through `execute`, which wraps the work in a Task that
/// `abortDueToSceneExit()` can cancel, so network probes really stop when the scene leaves active.
@MainActor
public final class ProbeRunner: ObservableObject {
    @Published public var isRunning = false
    @Published public var statusMessage = "Ready"
    @Published public var latestReportText = ""
    @Published public var currentContext: CapturedContext

    private var activeTask: Task<Void, Never>?
    private let sceneLeftLock = OSAllocatedUnfairLock(initialState: false)
    private var report = Gate0dReportData()
    private var prevRamp: MemoryRampSummary
    private var peakResident = 0.0
    private var peakFootprint = 0.0
    private var peakAvailable: Double?

    public init() {
        self.currentContext = ProbeContext.capture(luminanceReduced: false)
        self.prevRamp = MemoryRampProbe.inspectPreviousLaunch()
        seedContextAndRamp(config: ProbeRunConfig())
        self.latestReportText = ResultFormatter.format(report: report)
    }

    public func refreshContext(luminanceReduced: Bool) {
        currentContext = ProbeContext.capture(luminanceReduced: luminanceReduced)
    }

    public func abortDueToSceneExit() {
        guard isRunning else { return }
        sceneLeftLock.withLock { $0 = true }
        activeTask?.cancel()
    }

    private func wasSceneInterrupted() -> Bool {
        sceneLeftLock.withLock { $0 }
    }

    // MARK: run lifecycle

    private func begin(config: ProbeRunConfig, luminanceReduced: Bool, resetReport: Bool, status: String) -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        sceneLeftLock.withLock { $0 = false }
        currentContext = ProbeContext.capture(luminanceReduced: luminanceReduced)
        if resetReport { report = Gate0dReportData() }
        seedContextAndRamp(config: config)

        let base = MemoryProbe.snapshot()
        if resetReport || report.fields["mem_baseline_resident_mb"] == nil {
            report.set("mem_baseline_resident_mb", ProbeStats.fmt(base.residentMB))
            report.set("mem_baseline_phys_footprint_mb", ProbeStats.fmt(base.physFootprintMB))
            report.set("mem_baseline_available_mb", base.availableString)
        }
        peakResident = base.residentMB
        peakFootprint = base.physFootprintMB
        peakAvailable = base.availableMB
        statusMessage = status
        return true
    }

    private func execute(_ work: @escaping @MainActor () async -> Void) async {
        let task = Task { @MainActor in await work() }
        activeTask = task
        await task.value
        activeTask = nil
    }

    private func trackPeak() {
        let s = MemoryProbe.snapshot()
        peakResident = max(peakResident, s.residentMB)
        peakFootprint = max(peakFootprint, s.physFootprintMB)
        if let a = s.availableMB {
            peakAvailable = peakAvailable.map { min($0, a) } ?? a
        }
    }

    private func finish() {
        trackPeak()
        let post = MemoryProbe.snapshot()
        report.set("mem_peak_resident_mb", ProbeStats.fmt(peakResident))
        report.set("mem_peak_phys_footprint_mb", ProbeStats.fmt(peakFootprint))
        report.set("mem_peak_available_mb", peakAvailable.map { ProbeStats.fmt($0) } ?? "UNSUPPORTED")
        report.set("mem_post_resident_mb", ProbeStats.fmt(post.residentMB))
        report.set("mem_post_phys_footprint_mb", ProbeStats.fmt(post.physFootprintMB))
        report.set("mem_post_available_mb", post.availableString)

        let text = ResultFormatter.format(report: report)
        latestReportText = text
        persistLatestText(text)
        print(text)
        statusMessage = wasSceneInterrupted() ? "Interrupted (scene left active)" : "Done"
        isRunning = false
    }

    // MARK: public runs

    public func runRequiredSuite(config: ProbeRunConfig, luminanceReduced: Bool = false) async {
        guard begin(config: config, luminanceReduced: luminanceReduced, resetReport: true, status: "Running JIT probe...") else { return }
        await execute { [self] in
            self.applyJit(JitProbe.run())
            self.trackPeak()
            if self.checkAbort("network") { return }

            self.statusMessage = "Checking NWPathMonitor..."
            self.applyPath(await PathMonitorProbe.run())
            if self.checkAbort("network") { return }

            self.statusMessage = "Probing control + low-level networking..."
            self.applyNetBlock(await NetworkBlockProbe.run(config: config))
            self.trackPeak()
            if self.checkAbort("lan") { return }

            self.statusMessage = "Benchmarking URLSession.bytes..."
            self.applyLan(await LanTransportProbe.run(config: config, context: self.currentContext))
            self.trackPeak()
            if self.checkAbort("decode") { return }

            self.statusMessage = "Benchmarking zlib + CGImage..."
            let ctx = self.currentContext
            let dec = await Task.detached(priority: .userInitiated) { FrameDecodeProbe.run(context: ctx) }.value
            self.applyDecode(dec)
            self.trackPeak()
        }
        finish()
    }

    public func rerunJit(config: ProbeRunConfig, luminanceReduced: Bool = false) async {
        guard begin(config: config, luminanceReduced: luminanceReduced, resetReport: false, status: "Re-running JIT probe...") else { return }
        await execute { [self] in
            self.applyJit(JitProbe.run())
        }
        finish()
    }

    public func rerunNetwork(config: ProbeRunConfig, luminanceReduced: Bool = false) async {
        guard begin(config: config, luminanceReduced: luminanceReduced, resetReport: false, status: "Re-running network probes...") else { return }
        await execute { [self] in
            self.applyPath(await PathMonitorProbe.run())
            if self.checkAbort("network") { return }
            self.applyNetBlock(await NetworkBlockProbe.run(config: config))
            if self.checkAbort("lan") { return }
            self.applyLan(await LanTransportProbe.run(config: config, context: self.currentContext))
        }
        finish()
    }

    public func rerunDecode(config: ProbeRunConfig, luminanceReduced: Bool = false) async {
        guard begin(config: config, luminanceReduced: luminanceReduced, resetReport: false, status: "Re-running decode probe...") else { return }
        await execute { [self] in
            let ctx = self.currentContext
            let dec = await Task.detached(priority: .userInitiated) { FrameDecodeProbe.run(context: ctx) }.value
            self.applyDecode(dec)
            self.trackPeak()
        }
        finish()
    }

    public func runOptInMemoryRamp(config: ProbeRunConfig, luminanceReduced: Bool = false) async {
        guard begin(config: config, luminanceReduced: luminanceReduced, resetReport: false, status: "Running memory ramp (may terminate)...") else { return }
        let flag = sceneLeftLock
        await execute { [self] in
            let summary = await Task.detached(priority: .userInitiated) {
                MemoryRampProbe.runRamp(shouldAbort: { flag.withLock { $0 } })
            }.value
            self.prevRamp = summary
            self.applyRampSummary(summary)
        }
        finish()
    }

    // MARK: report plumbing

    private func seedContextAndRamp(config: ProbeRunConfig) {
        report.set("PROBE_SPEC_VERSION", currentContext.probeSpecVersion)
        report.set("TIMESTAMP_UTC", currentContext.timestampUTC)
        report.set("DEVICE_MODEL", currentContext.deviceModel)
        report.set("WATCHOS_VERSION", currentContext.watchOSVersion)
        report.set("ARCH", currentContext.arch)
        report.set("SCREEN_PT", currentContext.screenPtString)
        report.set("SCREEN_SCALE", currentContext.screenScaleString)
        report.set("LAUNCH_MODE", currentContext.launchMode)
        report.set("ATS_PROFILE", currentContext.atsProfile)
        report.set("IPHONE_LINK", config.iphoneLink.rawValue)
        report.set("LAN_ROUTER_INTERNET", config.lanRouterInternet.rawValue)
        report.set("LOW_POWER_MODE", currentContext.lowPowerMode ? "true" : "false")
        report.set("THERMAL_STATE", currentContext.thermalState)
        report.set("LUMINANCE_REDUCED", currentContext.luminanceReduced ? "true" : "false")

        report.set("wcsession_status", ProbeStatus.skipped.rawValue)
        report.set("wcsession_detail", ProbeDetail.deferredToV1_1)
        report.set("wcsession_rtt_p50_ms", "na")
        report.set("wcsession_throughput_kbps", "na")

        applyRampSummary(prevRamp)
    }

    private func applyRampSummary(_ ramp: MemoryRampSummary) {
        report.set("mem_ramp_status", ramp.status.rawValue)
        report.set("mem_ramp_prev_unclean_exit", ramp.prevUncleanExit ? "true" : "false")
        report.set("mem_ramp_prev_last_ok_mb", ramp.prevLastOkMB.map { ProbeStats.fmt($0) } ?? "na")
        report.set("mem_ramp_prev_last_resident_mb", ramp.prevLastResidentMB.map { ProbeStats.fmt($0) } ?? "na")
        report.set("mem_ramp_prev_last_phys_footprint_mb", ramp.prevLastFootprintMB.map { ProbeStats.fmt($0) } ?? "na")
        report.set(
            "mem_ramp_prev_last_available_mb",
            ramp.prevLastAvailableMB.map { ProbeStats.fmt($0) } ?? (ramp.prevUncleanExit ? "UNSUPPORTED" : "na")
        )
    }

    /// Returns true (and marks the remaining probes INTERRUPTED) if the run was cancelled
    /// or the scene left active.
    private func checkAbort(_ stage: String) -> Bool {
        guard Task.isCancelled || wasSceneInterrupted() else { return false }
        let det = wasSceneInterrupted() ? ProbeDetail.sceneLeftActive : ProbeDetail.userCancelled
        let interrupted = ProbeStatus.interrupted.rawValue
        if stage == "network" {
            for k in ["http_ping_ip", "https_ping_ip", "bsd_socket_tcp", "nw_connection_tcp", "urlsession_websocket"] {
                report.set("\(k)_status", interrupted)
                report.set("\(k)_detail", det)
            }
        }
        if stage == "network" || stage == "lan" {
            for k in ["getaddrinfo_local", "http_ping_local"] {
                report.set("\(k)_status", interrupted)
                report.set("\(k)_detail", det)
            }
            for k in ["lan_ping_n20", "lan_stream_4kb_n30", "lan_stream_1x_n30", "lan_stream_native_n30", "lan_post_input_n20"] {
                report.set("\(k)_status", interrupted)
            }
        }
        return true
    }

    private func applyJit(_ r: JitProbeResult) {
        report.set("jit_mmap_status", r.mmapStatus.rawValue)
        report.set("jit_mmap_detail", r.mmapDetail)
        report.set("jit_mprotect_status", r.mprotectStatus.rawValue)
        report.set("jit_mprotect_detail", r.mprotectDetail)
    }

    private func applyPath(_ r: PathMonitorResult) {
        report.set("nw_path_status", r.status)
        report.set("nw_path_unsatisfied_reason", r.unsatisfiedReason)
    }

    private func applyNetBlock(_ r: ControlAndLowLevelResult) {
        report.set("net_path_hint", r.netPathHint)
        report.set("net_actual_protocol", r.netActualProtocol)
        report.set("http_ping_ip_status", r.httpPingStatus.rawValue)
        report.set("http_ping_ip_rtt_ms", r.httpPingRttMs.map { ProbeStats.fmt($0) } ?? "na")
        report.set("http_ping_ip_detail", r.httpPingDetail)
        report.set("https_ping_ip_status", r.httpsPingStatus.rawValue)
        report.set("https_ping_ip_rtt_ms", r.httpsPingRttMs.map { ProbeStats.fmt($0) } ?? "na")
        report.set("https_ping_ip_detail", r.httpsPingDetail)
        report.set("bsd_socket_tcp_status", r.bsdTcpStatus.rawValue)
        report.set("bsd_socket_tcp_rtt_ms", r.bsdTcpRttMs.map { ProbeStats.fmt($0) } ?? "na")
        report.set("bsd_socket_tcp_detail", r.bsdTcpDetail)
        report.set("nw_connection_tcp_status", r.nwTcpStatus.rawValue)
        report.set("nw_connection_tcp_rtt_ms", r.nwTcpRttMs.map { ProbeStats.fmt($0) } ?? "na")
        report.set("nw_connection_tcp_detail", r.nwTcpDetail)
        report.set("urlsession_websocket_status", r.wsStatus.rawValue)
        report.set("urlsession_websocket_rtt_ms", r.wsRttMs.map { ProbeStats.fmt($0) } ?? "na")
        report.set("urlsession_websocket_detail", r.wsDetail)
    }

    private func applyLan(_ r: LanTransportResult) {
        report.set("getaddrinfo_local_status", r.getaddrinfoStatus.rawValue)
        report.set("getaddrinfo_local_ms", r.getaddrinfoMs.map { ProbeStats.fmt($0) } ?? "na")
        report.set("getaddrinfo_local_addr_count", "\(r.getaddrinfoAddrCount)")
        report.set("getaddrinfo_local_detail", r.getaddrinfoDetail)
        report.set("http_ping_local_status", r.httpPingLocalStatus.rawValue)
        report.set("http_ping_local_rtt_ms", r.httpPingLocalRttMs.map { ProbeStats.fmt($0) } ?? "na")
        report.set("http_ping_local_detail", r.httpPingLocalDetail)

        report.set("lan_ping_n20_status", r.pingStatus.rawValue)
        if let p = r.pingStats {
            report.set("lan_ping_n20_min_ms", ProbeStats.fmt(p.min))
            report.set("lan_ping_n20_p50_ms", ProbeStats.fmt(p.p50))
            report.set("lan_ping_n20_p95_ms", ProbeStats.fmt(p.p95))
            report.set("lan_ping_n20_max_ms", ProbeStats.fmt(p.max))
        }

        report.set("lan_stream_4kb_n30_status", r.stream4kbStatus.rawValue)
        report.set("lan_stream_4kb_ttfb_ms", r.stream4kbTtfbMs.map { ProbeStats.fmt($0) } ?? "na")
        report.set("lan_stream_4kb_kbps", r.stream4kbKbps.map { ProbeStats.fmt($0, decimals: 1) } ?? "na")

        report.set("lan_stream_1x_n30_status", r.stream1xStatus.rawValue)
        report.set("lan_stream_1x_bytes", "\(r.stream1xBytes)")
        report.set("lan_stream_1x_ttfb_ms", r.stream1xTtfbMs.map { ProbeStats.fmt($0) } ?? "na")
        report.set("lan_stream_1x_kbps", r.stream1xKbps.map { ProbeStats.fmt($0, decimals: 1) } ?? "na")

        report.set("lan_stream_native_n30_status", r.streamNativeStatus.rawValue)
        report.set("lan_stream_native_bytes", "\(r.streamNativeBytes)")
        report.set("lan_stream_native_ttfb_ms", r.streamNativeTtfbMs.map { ProbeStats.fmt($0) } ?? "na")
        report.set("lan_stream_native_kbps", r.streamNativeKbps.map { ProbeStats.fmt($0, decimals: 1) } ?? "na")

        report.set("lan_post_input_n20_status", r.postInputStatus.rawValue)
        if let po = r.postInputStats {
            report.set("lan_post_input_n20_min_ms", ProbeStats.fmt(po.min))
            report.set("lan_post_input_n20_p50_ms", ProbeStats.fmt(po.p50))
            report.set("lan_post_input_n20_p95_ms", ProbeStats.fmt(po.p95))
            report.set("lan_post_input_n20_max_ms", ProbeStats.fmt(po.max))
        }
    }

    private func applyDecode(_ r: FrameDecodeResult) {
        report.set("decode_1x_px", r.px1x)
        report.set("decode_native_px", r.pxNative)
        report.set("zlib_1x_static_bytes", "\(r.zlib1xStaticBytes)")
        report.set("zlib_1x_static_p50_ms", ProbeStats.fmt(r.zlib1xStaticP50Ms))
        report.set("zlib_1x_static_max_ms", ProbeStats.fmt(r.zlib1xStaticMaxMs))
        report.set("zlib_1x_noisy_bytes", "\(r.zlib1xNoisyBytes)")
        report.set("zlib_1x_noisy_p50_ms", ProbeStats.fmt(r.zlib1xNoisyP50Ms))
        report.set("zlib_1x_noisy_max_ms", ProbeStats.fmt(r.zlib1xNoisyMaxMs))
        report.set("zlib_native_static_bytes", "\(r.zlibNativeStaticBytes)")
        report.set("zlib_native_static_p50_ms", ProbeStats.fmt(r.zlibNativeStaticP50Ms))
        report.set("zlib_native_static_max_ms", ProbeStats.fmt(r.zlibNativeStaticMaxMs))
        report.set("zlib_native_noisy_bytes", "\(r.zlibNativeNoisyBytes)")
        report.set("zlib_native_noisy_p50_ms", ProbeStats.fmt(r.zlibNativeNoisyP50Ms))
        report.set("zlib_native_noisy_max_ms", ProbeStats.fmt(r.zlibNativeNoisyMaxMs))
        report.set("cgimage_draw_rgba_native_p50_ms", ProbeStats.fmt(r.drawRgbaP50Ms))
        report.set("cgimage_draw_rgba_native_max_ms", ProbeStats.fmt(r.drawRgbaMaxMs))
        report.set("cgimage_draw_premul_native_p50_ms", ProbeStats.fmt(r.drawPremulP50Ms))
        report.set("cgimage_draw_premul_native_max_ms", ProbeStats.fmt(r.drawPremulMaxMs))
    }

    private func persistLatestText(_ text: String) {
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = docs.appendingPathComponent("latest_gate0d_result.txt")
            try? Data(text.utf8).write(to: fileURL, options: [.atomic])
        }
    }
}
