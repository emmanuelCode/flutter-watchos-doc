import Foundation

public enum ResultFormatter {
    public static func format(report: Gate0dReportData) -> String {
        var lines: [String] = []
        var jsonMap: [String: String] = [:]

        func emit(_ key: String, _ defaultVal: String = "na") {
            let v = report.fields[key] ?? defaultVal
            lines.append("\(key)=\(v)")
            jsonMap[key] = v
        }

        lines.append("======== GATE 0D HARDWARE PROBE v1 ========")
        emit("PROBE_SPEC_VERSION", "1")
        emit("TIMESTAMP_UTC")
        emit("DEVICE_MODEL")
        emit("WATCHOS_VERSION")
        emit("ARCH")
        emit("SCREEN_PT")
        emit("SCREEN_SCALE")
        emit("LAUNCH_MODE")
        emit("ATS_PROFILE")
        emit("IPHONE_LINK")
        emit("LAN_ROUTER_INTERNET")
        emit("LOW_POWER_MODE")
        emit("THERMAL_STATE")
        emit("LUMINANCE_REDUCED")

        lines.append("")
        lines.append("[MEM_BASELINE]")
        emit("mem_baseline_resident_mb")
        emit("mem_baseline_phys_footprint_mb")
        emit("mem_baseline_available_mb", "UNSUPPORTED")

        lines.append("")
        lines.append("[JIT]")
        emit("jit_mmap_status", "SKIPPED")
        emit("jit_mmap_detail", "none")
        emit("jit_mprotect_status", "SKIPPED")
        emit("jit_mprotect_detail", "none")

        lines.append("")
        lines.append("[NW_PATH_MONITOR]")
        emit("nw_path_status", "unknown")
        emit("nw_path_unsatisfied_reason", "unknown")

        lines.append("")
        lines.append("[NET_ACTUAL_PATH]")
        emit("net_path_hint", "unknown")
        emit("net_actual_protocol", "na")

        lines.append("")
        lines.append("[NET_CONTROL]")
        emit("http_ping_ip_status", "SKIPPED")
        emit("http_ping_ip_rtt_ms")
        emit("http_ping_ip_detail", "none")
        emit("https_ping_ip_status", "SKIPPED")
        emit("https_ping_ip_rtt_ms")
        emit("https_ping_ip_detail", "none")

        lines.append("")
        lines.append("[NET_LOWLEVEL]")
        emit("bsd_socket_tcp_status", "SKIPPED")
        emit("bsd_socket_tcp_rtt_ms")
        emit("bsd_socket_tcp_detail", "none")
        emit("nw_connection_tcp_status", "SKIPPED")
        emit("nw_connection_tcp_rtt_ms")
        emit("nw_connection_tcp_detail", "none")
        emit("urlsession_websocket_status", "SKIPPED")
        emit("urlsession_websocket_rtt_ms")
        emit("urlsession_websocket_detail", "none")

        lines.append("")
        lines.append("[MDNS_LOCAL]")
        emit("getaddrinfo_local_status", "SKIPPED")
        emit("getaddrinfo_local_ms")
        emit("getaddrinfo_local_addr_count", "0")
        emit("getaddrinfo_local_detail", "none")
        emit("http_ping_local_status", "SKIPPED")
        emit("http_ping_local_rtt_ms")
        emit("http_ping_local_detail", "none")

        lines.append("")
        lines.append("[LAN_URLSESSION_BYTES]")
        emit("lan_ping_n20_status", "SKIPPED")
        emit("lan_ping_n20_min_ms")
        emit("lan_ping_n20_p50_ms")
        emit("lan_ping_n20_p95_ms")
        emit("lan_ping_n20_max_ms")
        emit("lan_stream_4kb_n30_status", "SKIPPED")
        emit("lan_stream_4kb_ttfb_ms")
        emit("lan_stream_4kb_kbps")
        emit("lan_stream_1x_n30_status", "SKIPPED")
        emit("lan_stream_1x_bytes", "0")
        emit("lan_stream_1x_ttfb_ms")
        emit("lan_stream_1x_kbps")
        emit("lan_stream_native_n30_status", "SKIPPED")
        emit("lan_stream_native_bytes", "0")
        emit("lan_stream_native_ttfb_ms")
        emit("lan_stream_native_kbps")
        emit("lan_post_input_n20_status", "SKIPPED")
        emit("lan_post_input_n20_min_ms")
        emit("lan_post_input_n20_p50_ms")
        emit("lan_post_input_n20_p95_ms")
        emit("lan_post_input_n20_max_ms")

        lines.append("")
        lines.append("[WCSESSION]")
        emit("wcsession_status", "SKIPPED")
        emit("wcsession_detail", "deferred_to_v1_1")
        emit("wcsession_rtt_p50_ms")
        emit("wcsession_throughput_kbps")

        lines.append("")
        lines.append("[DECODE_CPU]")
        emit("decode_1x_px")
        emit("decode_native_px")
        emit("zlib_1x_static_bytes", "0")
        emit("zlib_1x_static_p50_ms")
        emit("zlib_1x_static_max_ms")
        emit("zlib_1x_noisy_bytes", "0")
        emit("zlib_1x_noisy_p50_ms")
        emit("zlib_1x_noisy_max_ms")
        emit("zlib_native_static_bytes", "0")
        emit("zlib_native_static_p50_ms")
        emit("zlib_native_static_max_ms")
        emit("zlib_native_noisy_bytes", "0")
        emit("zlib_native_noisy_p50_ms")
        emit("zlib_native_noisy_max_ms")
        emit("cgimage_draw_rgba_native_p50_ms")
        emit("cgimage_draw_rgba_native_max_ms")
        emit("cgimage_draw_premul_native_p50_ms")
        emit("cgimage_draw_premul_native_max_ms")

        lines.append("")
        lines.append("[MEM_PEAK_AND_POST]")
        emit("mem_peak_resident_mb")
        emit("mem_peak_phys_footprint_mb")
        emit("mem_peak_available_mb", "UNSUPPORTED")
        emit("mem_post_resident_mb")
        emit("mem_post_phys_footprint_mb")
        emit("mem_post_available_mb", "UNSUPPORTED")

        lines.append("")
        lines.append("[MEM_RAMP]")
        emit("mem_ramp_status", "SKIPPED")
        emit("mem_ramp_prev_unclean_exit", "false")
        emit("mem_ramp_prev_last_ok_mb")
        emit("mem_ramp_prev_last_resident_mb")
        emit("mem_ramp_prev_last_phys_footprint_mb")
        emit("mem_ramp_prev_last_available_mb")

        lines.append("")
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonMap, options: [.sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            lines.append("RESULT_JSON=\(jsonString)")
        } else {
            lines.append("RESULT_JSON={}")
        }
        lines.append("======== END GATE 0D ========")
        return lines.joined(separator: "\n") + "\n"
    }
}
