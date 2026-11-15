import XCTest
@testable import Gate0dProbeCore

/// Simulator negative control. The watchOS Simulator is a Mac process, so every low-level network API
/// is EXPECTED to be allowed here. This proves the probe and result format work end to end;
/// it says nothing about a physical watch.
final class Gate0dProbeSimulatorTests: XCTestCase {
    @MainActor
    func test_simulator_negative_control_and_validator_output() async throws {
        let env = ProcessInfo.processInfo.environment
        let tcpPort = UInt16(env["GATE0D_TCP_PORT"] ?? "") ?? 8774
        let httpPort = UInt16(env["GATE0D_HTTP_PORT"] ?? "") ?? 8775

        let runner = ProbeRunner()
        let config = ProbeRunConfig(
            hostIP: "127.0.0.1",
            localHost: "",
            tcpPort: tcpPort,
            httpPort: httpPort,
            httpsPort: nil,
            iphoneLink: .available,
            lanRouterInternet: .yes,
            timeoutSeconds: 5.0
        )

        await runner.runRequiredSuite(config: config, luminanceReduced: false)
        let text = runner.latestReportText

        try Data(text.utf8).write(to: URL(fileURLWithPath: "/tmp/gate0d_sim_result.txt"), options: [.atomic])

        XCTAssertTrue(text.contains("http_ping_ip_status=ALLOWED"), text)
        XCTAssertTrue(text.contains("bsd_socket_tcp_status=ALLOWED"), text)
        XCTAssertTrue(text.contains("nw_connection_tcp_status=ALLOWED"), text)
        XCTAssertTrue(text.contains("urlsession_websocket_status=ALLOWED"), text)
        XCTAssertTrue(text.contains("lan_ping_n20_status=ALLOWED"), text)
        XCTAssertTrue(text.contains("lan_stream_4kb_n30_status=ALLOWED"), text)
        XCTAssertTrue(text.contains("lan_stream_1x_n30_status=ALLOWED"), text)
        XCTAssertTrue(text.contains("lan_stream_native_n30_status=ALLOWED"), text)
        XCTAssertTrue(text.contains("lan_post_input_n20_status=ALLOWED"), text)
        XCTAssertTrue(text.contains("wcsession_status=SKIPPED"), text)
        XCTAssertTrue(text.contains("mem_ramp_status=SKIPPED"), text)
        XCTAssertFalse(text.contains("127.0.0.1"), "result block must never contain the host address")
    }

    func test_detail_sanitization_never_leaks_text() throws {
        let err = NSError(domain: "com.apple.custom.unknown", code: -99, userInfo: [
            NSLocalizedDescriptionKey: "My-MacBook.local 192.168.1.50 leaked text",
        ])
        let sanitized = ProbeDetail.sanitize(error: err)
        XCTAssertFalse(sanitized.contains("192.168"))
        XCTAssertFalse(sanitized.contains(".local"))
        XCTAssertFalse(sanitized.contains("MacBook"))
        XCTAssertEqual(sanitized, "OtherDomain:-99")
        let matchesGrammar = sanitized.range(of: #"^[A-Za-z0-9_]+:-?[0-9]+$"#, options: .regularExpression) != nil
        XCTAssertTrue(matchesGrammar, sanitized)
    }

    func test_ramp_clean_abort_clears_breadcrumb() throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_ramp_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let cancelled = MemoryRampProbe.runRamp(stepMB: 1, maxSteps: 5, stateURL: tmpURL, shouldAbort: { true })
        XCTAssertEqual(cancelled.status, .interrupted)

        let inspect = MemoryRampProbe.inspectPreviousLaunch(stateURL: tmpURL)
        XCTAssertFalse(inspect.prevUncleanExit, "clean abort must not look like an unclean exit")
    }

    func test_ramp_unclean_breadcrumb_is_detected_once() throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_ramp_unclean_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        MemoryRampProbe.writeState(
            RampBreadcrumb(rampInProgress: true, lastOkMB: 24, lastResidentMB: 30, lastFootprintMB: 28, lastAvailableMB: nil),
            stateURL: tmpURL
        )
        let first = MemoryRampProbe.inspectPreviousLaunch(stateURL: tmpURL)
        XCTAssertTrue(first.prevUncleanExit)
        XCTAssertEqual(first.prevLastOkMB, 24)

        let second = MemoryRampProbe.inspectPreviousLaunch(stateURL: tmpURL)
        XCTAssertFalse(second.prevUncleanExit, "breadcrumb must be reset after being reported")
    }
}
