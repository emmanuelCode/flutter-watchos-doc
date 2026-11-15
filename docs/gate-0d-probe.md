# Gate 0d Hardware Probe App — Design Specification

> **Status:** Design only (unbuilt, unverified on physical hardware). **Do not write app code until Stage 6c.**
> **Purpose:** Collect physical-watch measurements for Open Questions 10, 11, and 13 in [flutter_watchos_architecture.md](../flutter_watchos_architecture.md) without bundling the Flutter engine or shipping to the App Store.

## 1. Goals, Constraints & Foreground Protocol

- **Why CI cannot answer Gate 0d:** All current CI checks run in the watchOS Simulator (a Mac process). Per Apple [TN3135](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos), the Simulator allows low-level networking (`URLSessionWebSocketTask`, `URLSessionStreamTask`, `NWConnection`, `NWBrowser`, `NSNetService`, and BSD sockets) that physical watches (watchOS 9+) constrain outside active audio/VoIP sessions. Simulator runs also use Mac CPU, Mac memory, and JIT.
- **Dev-only artifact:** Contributor-built and sideloaded locally via Xcode (`#if DEBUG` / personal or team dev signing). It never ships to the App Store.
- **Self-contained & non-hanging:** Every network probe uses an explicit timeout (default `5 s`), runs asynchronously off the main thread, and separates **OS/API blocked** (`BLOCKED_BY_OS`) from **LAN host unreachable** (`FAIL` / `TIMEOUT`).
- **Public APIs only:** Uses standard WatchKit / SwiftUI / Foundation / Network / Compression / Mach `task_info` APIs.

### Foreground Execution & Scene-Abort Guard
- **Abort on scene exit:** The probe runner observes SwiftUI `scenePhase` and `@Environment(\.isLuminanceReduced)`. If `scenePhase` leaves `.active` (`.inactive` or `.background`, e.g., wrist drop, Always-On dimming, or screen lock) while probes are running, all active tasks/connections are cancelled immediately and the current plus remaining probes record **`INTERRUPTED`** with detail `scene_left_active`.
- **Contributor setup steps to stay foreground during a run:**
  1. On Apple Watch **Settings → Display & Brightness → Wake Duration**: select **Wake for 70 Seconds** (`TODO(author): verify` exact menu wording on target watchOS).
  2. On Apple Watch **Settings → General → Return to Clock**: scroll to **Gate 0d Probe**, select **Custom**, and choose **After 1 Hour** (`TODO(author): verify` exact label on target watchOS).
  3. Keep the watch unlocked on-wrist and awake throughout testing; avoid covering the display or dropping the wrist.
- **Power & thermal context:** Record `LOW_POWER_MODE` (`ProcessInfo.processInfo.isLowPowerModeEnabled`), `THERMAL_STATE` (`ProcessInfo.processInfo.thermalState`), and `LUMINANCE_REDUCED` (`isLuminanceReduced`) in the header because throttling affects CPU and network timings.

### Two-Run Required Matrix (`IPHONE_LINK`)
To separate iPhone-relayed networking from standalone Watch Wi-Fi, contributors must run a **required minimum matrix of 2 runs**:
1. **Run 1 (`IPHONE_LINK=available`):** Paired iPhone nearby with Wi-Fi and Bluetooth ON in iPhone Settings (`ATS_PROFILE=relaxed`, `LAN_ROUTER_INTERNET=yes`).
2. **Run 2 (`IPHONE_LINK=unavailable`):** Turn **both Wi-Fi and Bluetooth OFF inside the iPhone Settings app** (do **not** use Control Center, which only disconnects temporarily without disabling companion relay; `TODO(author): verify` exact behavior on contributor iOS version) so the Watch uses its direct Wi-Fi path (`ATS_PROFILE=relaxed`, `LAN_ROUTER_INTERNET=yes`).
- **Supplemental runs (optional):** Strict ATS (`ATS_PROFILE=strict`) and/or isolated router with no internet (`LAN_ROUTER_INTERNET=no`).

---

## 2. Proposed Project Structure & Build Decisions

Watch-only v1 probe target + single-file Dart echo server + CI block validator:

```text
gate0d_probe/
  watch_app/                      # Minimal standalone watchOS SwiftUI app (.watchOS(.v10))
    Configurations/               # Xcode build configurations
      Debug-RelaxedATS.xcconfig   # Selects Info-RelaxedATS.plist
      Debug-StrictATS.xcconfig    # Selects Info-StrictATS.plist
    Info-RelaxedATS.plist         # Variant A: relaxed ATS (NSAllowsArbitraryLoads / NSAllowsLocalNetworking)
    Info-StrictATS.plist          # Variant B: strict/default ATS for dedicated ATS probe
    ProbeApp.swift                # Single-screen SwiftUI UI + per-probe re-run buttons + scenePhase guard
    ProbeContext.swift            # Device/screen/power/thermal/launch metadata (no PII or IPs)
    Probes/
      JitProbe.swift              # Hypothesis test: mmap(MAP_JIT) & mprotect(PROT_EXEC)
      PathMonitorProbe.swift      # Documented-behavior check: NWPathMonitor status
      NetworkBlockProbe.swift     # Control HTTP + BSD socket + NWConnection + URLSessionWebSocketTask
      LanTransportProbe.swift     # URLSession.bytes RTT, chunked stream, POST, .local resolution
      AtsProbe.swift              # Dedicated ATS profile comparison
      FrameDecodeProbe.swift      # CPU zlib decompress + CGImage/CGContext draw (sized from SCREEN_PT/SCALE)
      MemoryProbe.swift           # Mach task_info (resident_size, phys_footprint) + os_proc_available_memory()
      MemoryRampProbe.swift       # Opt-in crash-ramp probe + atomic file persistent state
    ResultFormatter.swift         # Emits single-key-per-line block + RESULT_JSON= (enforces detail allowlist)
  mac_echo_server/
    probe_server.dart             # Single-file Dart echo/stream server using dart:io only
  ci_validator/
    validate_gate0d.py            # Validates output schema, enum values, RESULT_JSON, and PII/IP exclusion
```

### Locked Decisions & Configuration Protocol

- **Deployment target (locked):** `.watchOS(.v10)` (matches `watchos-proofs/swift_spec/Package.swift` and maximizes contributor hardware coverage).
- **`ios_companion_stub/` / `WCSession` (deferred to v1.1):** Excluded from v1 so contributors need zero iOS companion setup; v1 logs `wcsession_status=SKIPPED` (`wcsession_detail=deferred_to_v1_1`).
- **Mac echo server (locked):** Single-file Dart script using **`dart:io` only** (zero package dependencies, reuses Flutter/Dart SDK).
- **Two `Info.plist` variants (ATS separation):** Plists are selected via Xcode build configurations (`Debug-RelaxedATS` vs `Debug-StrictATS`), not `#if DEBUG`. Apple's [`NSAllowsLocalNetworking`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking) documentation does not list watchOS. Variant A keeps ATS from masking low-level transport behavior; Variant B isolates ATS `-1022` policy behavior (`TODO(author): verify` exact behavior on physical watchOS).
- **Standalone launch procedure & runtime detection:**
  - Procedure: to run standalone, stop the Xcode debugging session, disconnect/quit Xcode, and tap the probe app icon from the watch home screen.
  - `LAUNCH_MODE` is read at runtime by inspecting `P_TRACED` via `sysctl` (`kern.proc.pid`, `TODO(author): verify` sysctl structure on watchOS), emitting `xcode_debugger` or `standalone_watch`.
  - `ATS_PROFILE` is read at runtime from `Bundle.main.infoDictionary?["NSAppTransportSecurity"]`, emitting `relaxed` or `strict`. Both are displayed as read-only badges in the UI.
- **Local network privacy:** Per Apple [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), watchOS does not enforce a Local Network Privacy prompt.
- **Host configuration:** Configure target IP / `<host>.local` via `.xcconfig` or an on-watch text field for testing only (never emitted into the result block; avoids `NWBrowser` / Bonjour which TN3135 blocks).

---

## 3. Probe Definitions

### Probe 1: Executable Memory / JIT Hypothesis (`JitProbe`)
- **Hypothesis (not a conclusion):** Physical watchOS devices are expected to deny dynamic `mmap(MAP_JIT)` / `mprotect(PROT_EXEC)` pages when launched standalone without an attached debugger (and potentially under Xcode too), whereas the Simulator allows them. This probe tests that hypothesis on hardware without assuming the outcome.
- **Method:**
  1. Attempt `mmap(NULL, pageSize, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0)` -> record `ALLOWED` or `BLOCKED_BY_OS` / `FAIL` (`errno`).
  2. Attempt anonymous `mmap(..., PROT_READ | PROT_WRITE, ...)` followed by `mprotect(..., PROT_READ | PROT_EXEC)` -> record `ALLOWED` or `BLOCKED_BY_OS` / `FAIL` (`errno`).
  3. Execute under both `LAUNCH_MODE=xcode_debugger` and `LAUNCH_MODE=standalone_watch`.
- **Safety:** Never execute into the test page; only record return values / `errno` and `munmap` cleanly.

### Probe 2: `NWPathMonitor` Check & Control Baseline (`PathMonitorProbe`, `NetworkBlockProbe`)
- **`NWPathMonitor` documented-behavior check (`[NW_PATH_MONITOR]`):** Per Apple TN3135, `NWPathMonitor` stays `.unsatisfied` on a physical watch for normal apps, so it cannot show which path `URLSession` used. Record `currentPath.status` and `unsatisfiedReason` to confirm this documented limitation.
- **Path heuristic (`[NET_ACTUAL_PATH]`):** Derived from `URLSessionTaskMetrics` of the control ping request (`transactionMetrics.first?.networkProtocolName` and connection interface type). Emits only `net_path_hint=<wifi | cellular | companion_proxy | unknown>` (default `unknown`). Note: `net_path_hint` is an observational heuristic; the measured RTT difference between Run 1 (companion on) and Run 2 (companion off) is the primary empirical evidence (`TODO(author): verify` which task metrics properties are non-nil on watchOS).
- **Control baseline (`[NET_CONTROL]`):** Run `URLSession.shared` `GET /ping` over HTTP (Variant A) and optional local HTTPS against the configured LAN IP before testing low-level APIs. If the control request fails, low-level failures cannot be attributed solely to TN3135.

### Probe 3: Low-Level Networking Per TN3135 (`[NET_LOWLEVEL]`)
Per Apple [TN3135](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos), `URLSessionWebSocketTask`, `NWConnection`, and BSD sockets are all low-level networking APIs:
1. **BSD socket (`bsd_socket_tcp`):** Documented in TN3135 as never working on physical watchOS (`TODO(author): verify` exact POSIX `errno` observed on hardware). Attempt `socket(AF_INET, SOCK_STREAM, 0)` + non-blocking `connect()` to `<tcp_port>`; record `ALLOWED`, `BLOCKED_BY_OS` (`errno`), `FAIL`, or `TIMEOUT`.
2. **`NWConnection` (`nw_connection_tcp`):** Blocked `NWConnection` instances on watchOS do not fail immediately—they remain in `.waiting` with `ENETDOWN`. Attach `stateUpdateHandler` with a `5 s` timeout; if it ends while still in `.waiting` with `ENETDOWN`, record `status=BLOCKED_BY_OS` and `detail=WAITING(ENETDOWN)`.
3. **`URLSessionWebSocketTask` (`urlsession_websocket`):** Counts as low-level per TN3135. Connect to `ws://.../ws`, send one small ping message, and await echo within `5 s` -> record `ALLOWED`, `BLOCKED_BY_OS`, `FAIL`, or `TIMEOUT` with `domain:code`.

### Probe 4: `.local` Resolution & `URLSession.bytes` LAN Transport (`LanTransportProbe`, `AtsProbe`)
- **`.local` resolution (`[MDNS_LOCAL]`):** Run POSIX `getaddrinfo("<host>.local", ...)` (recording resolved count, time in ms, or error code—never printing the IP or hostname) and `URLSession` `GET http://<host>.local:<http_port>/ping`, comparing against the direct IP control baseline.
- **Latency & throughput (`[LAN_URLSESSION_BYTES]`):**
  1. `20` sequential `GET /ping` requests after warmup (`min` / `p50` / `p95` / `max` ms).
  2. `URLSession.bytes` streaming (`GET /stream?frames=30&bytes=<N>`): test `4 KB` (representative compressed frame), native `@1x` byte size (`SCREEN_PT` `W * H * 4`), and native `@SCREEN_SCALE` byte size (`(W * S) * (H * S) * 4`). Measure TTFB and effective KB/s.
  3. `20` sequential `POST /input` calls (`32` bytes each) measuring upstream tap latency.
  4. Run under both internet-connected LAN and isolated no-internet router (`LAN_ROUTER_INTERNET=no`).
- **ATS check (`AtsProbe`):** Run Variant A (`Info-RelaxedATS.plist`) for the transport benchmarks above, and run Variant B (`Info-StrictATS.plist`) separately to observe `-1022` ATS behavior on plain HTTP vs local HTTPS (`TODO(author): verify` exact plist key behavior on physical watchOS).

### Probe 5: `WCSession` (`WatchConnectivityProbe` — Deferred to v1.1)
- Because `ios_companion_stub/` is deferred to **v1.1** so v1 stays watch-only, v1 records `wcsession_status=SKIPPED` and `wcsession_detail=deferred_to_v1_1`.

### Probe 6: Screen-Sized RGBA / zlib Decode & Image Draw (`FrameDecodeProbe`)
- **Sized from `SCREEN_PT` and `SCREEN_SCALE`:** Compute native `@1x` (`W * H * 4` bytes) and native `@SCREEN_SCALE` (`Int(W * S) * Int(H * S) * 4` bytes) buffers dynamically from the device's `SCREEN_PT` and `SCREEN_SCALE`.
- **zlib framing resolved:** As verified in CI check `P9` (`watchos-proofs/swift_proofs/Tests/WatchProofsTests/P9_TransportThroughputTests.swift`), `watchos-proofs/dart_tools/ws_stream_server.dart` uses `ZLibCodec(raw: true, level: 1)` and Apple's Compression framework `.zlib` (`(payload as NSData).decompressed(using: .zlib)`) decodes it cleanly. Both `probe_server.dart` and `FrameDecodeProbe` will use raw RFC 1951 deflate framing matching `P9`.
- **Method (offline, `100` iterations after warmup):** Benchmark both **mostly-black static** and **high-entropy noisy** frames for zlib decompression (`p50` / `max` ms + compressed bytes) and `CGDataProvider` -> `CGImage` -> off-screen `CGContext.draw` (straight RGBA vs premultiplied/opaque pixel format).

### Probe 7: Mach Memory & Opt-In Crash-Ramp (`MemoryProbe`, `MemoryRampProbe`)
- **Standard snapshots (`[MEM_BASELINE]`, `[MEM_PEAK_AND_POST]`):** Read `MACH_TASK_BASIC_INFO` (`resident_size`), `TASK_VM_INFO` (`phys_footprint`), and try `os_proc_available_memory()` (`TODO(author): verify` availability and behavior on physical watchOS; emit `UNSUPPORTED` if unavailable).
- **Opt-in memory-ramp probe (`[MEM_RAMP]`):** Disabled in standard suite (`SKIPPED` by default); triggered via an explicit **"Run Memory Ramp (Will Crash)"** button.
  - Allocates fixed-size chunks (e.g., `4 MB` steps) and fills each page with **incompressible pseudo-random data** (e.g., xorshift/random bytes, not zeros or repeating patterns) to prevent OS zero-page compression or deduplication.
  - After each successful step, writes persistent state atomically to `ramp_state.json` in the app container using `FileManager.default` atomic writing (`ramp_in_progress=true`, `resident_mb`, `phys_footprint_mb`, `available_mb`, `last_ok_mb`). `UserDefaults` alone is avoided because its asynchronous flush may be lost during abrupt jetsam termination.
  - **Clean exit handling:** If the user cancels or the probe clean-aborts due to `scenePhase` leaving `.active`, the atomic breadcrumb file is cleared / `ramp_in_progress=false` is written, preventing a false unclean exit report on the next launch.
  - **Unclean exit detection:** When watchOS terminates the process (jetsam), the next launch detects `ramp_in_progress=true`, populates `[MEM_RAMP]` (`mem_ramp_prev_unclean_exit=true`, `mem_ramp_prev_last_ok_mb`, `mem_ramp_prev_last_phys_footprint_mb`), and resets the breadcrumb file.

---

## 4. Mac-Side Echo Server Contract (`probe_server.dart`)

Single-file Dart server using **`dart:io` only** (zero external packages):
- Prints the local IPv4 address and `<hostname>.local` on the Mac terminal only so the contributor can configure the watch scheme/UI (never emitted by the watch into the result block).
- Exposes TCP echo port (`bsd_socket_tcp` / `nw_connection_tcp`) and HTTP/WS port (`GET /ping`, `GET /stream?frames=N&bytes=M`, `POST /input`, `GET /ws` echo, plus optional self-signed TLS mode for ATS comparison).

### Contributor Mac & Network Checklist
1. **macOS Application Firewall:** When starting `probe_server.dart`, accept the prompt *"Do you want the application to accept incoming network connections?"*. If missed or blocked, check **System Settings → Network → Firewall → Options** and ensure incoming connections for Dart are allowed.
2. **Router Client Isolation (AP Isolation):** Verify the Wi-Fi router does not have "Client Isolation" or "AP Isolation" enabled (which prevents wireless LAN devices from communicating directly with each other).
3. **Guest Wi-Fi:** Do not connect the Watch or Mac to a Guest Wi-Fi network, as guest networks almost universally block device-to-device LAN traffic.
4. **Interface Binding:** `probe_server.dart` must bind to `InternetAddress.anyIPv4` (`0.0.0.0`), not `InternetAddress.loopbackIPv4` (`127.0.0.1`), so incoming connections from the Watch's Wi-Fi IP are accepted.

---

## 5. Paste-Ready Output Format Specification

Strictly **one `KEY=VALUE` pair per line**, plus one trailing `RESULT_JSON=` line:

```text
======== GATE 0D HARDWARE PROBE v1 ========
PROBE_SPEC_VERSION=1
TIMESTAMP_UTC=<YYYY-MM-DDTHH:MM:SSZ>
DEVICE_MODEL=<hw.machine identifier e.g. Watch7,5 or Simulator>
WATCHOS_VERSION=<e.g. 26.5 or 27.x>
ARCH=<arm64 | arm64_32 | x86_64>
SCREEN_PT=<WxH>
SCREEN_SCALE=<float>
LAUNCH_MODE=<xcode_debugger | standalone_watch | unknown>
ATS_PROFILE=<relaxed | strict | unknown>
IPHONE_LINK=<available | unavailable>
LAN_ROUTER_INTERNET=<yes | no | offline_test>
LOW_POWER_MODE=<true | false>
THERMAL_STATE=<nominal | fair | serious | critical>
LUMINANCE_REDUCED=<true | false>

[MEM_BASELINE]
mem_baseline_resident_mb=<float>
mem_baseline_phys_footprint_mb=<float>
mem_baseline_available_mb=<float | UNSUPPORTED>

[JIT]
jit_mmap_status=<ALLOWED | BLOCKED_BY_OS | FAIL | TIMEOUT | INTERRUPTED | SKIPPED>
jit_mmap_detail=<domain:code | vocab_token>
jit_mprotect_status=<ALLOWED | BLOCKED_BY_OS | FAIL | TIMEOUT | INTERRUPTED | SKIPPED>
jit_mprotect_detail=<domain:code | vocab_token>

[NW_PATH_MONITOR]
nw_path_status=<satisfied | unsatisfied | requiresConnection | unknown>
nw_path_unsatisfied_reason=<none | str>

[NET_ACTUAL_PATH]
net_path_hint=<wifi | cellular | companion_proxy | unknown>
net_actual_protocol=<h2 | h3 | http/1.1 | tcp | unknown | na>

[NET_CONTROL]
http_ping_ip_status=<ALLOWED | BLOCKED_BY_OS | FAIL | TIMEOUT | INTERRUPTED | SKIPPED>
http_ping_ip_rtt_ms=<float | na>
http_ping_ip_detail=<domain:code | vocab_token>
https_ping_ip_status=<ALLOWED | BLOCKED_BY_OS | FAIL | TIMEOUT | INTERRUPTED | SKIPPED>
https_ping_ip_rtt_ms=<float | na>
https_ping_ip_detail=<domain:code | vocab_token>

[NET_LOWLEVEL]
bsd_socket_tcp_status=<ALLOWED | BLOCKED_BY_OS | FAIL | TIMEOUT | INTERRUPTED | SKIPPED>
bsd_socket_tcp_rtt_ms=<float | na>
bsd_socket_tcp_detail=<domain:code | vocab_token>
nw_connection_tcp_status=<ALLOWED | BLOCKED_BY_OS | FAIL | TIMEOUT | INTERRUPTED | SKIPPED>
nw_connection_tcp_rtt_ms=<float | na>
nw_connection_tcp_detail=<WAITING(ENETDOWN) | domain:code | vocab_token>
urlsession_websocket_status=<ALLOWED | BLOCKED_BY_OS | FAIL | TIMEOUT | INTERRUPTED | SKIPPED>
urlsession_websocket_rtt_ms=<float | na>
urlsession_websocket_detail=<domain:code | vocab_token>

[MDNS_LOCAL]
getaddrinfo_local_status=<ALLOWED | BLOCKED_BY_OS | FAIL | TIMEOUT | INTERRUPTED | SKIPPED>
getaddrinfo_local_ms=<float | na>
getaddrinfo_local_addr_count=<int>
getaddrinfo_local_detail=<domain:code | vocab_token>
http_ping_local_status=<ALLOWED | BLOCKED_BY_OS | FAIL | TIMEOUT | INTERRUPTED | SKIPPED>
http_ping_local_rtt_ms=<float | na>
http_ping_local_detail=<domain:code | vocab_token>

[LAN_URLSESSION_BYTES]
lan_ping_n20_status=<ALLOWED | BLOCKED_BY_OS | FAIL | TIMEOUT | INTERRUPTED | SKIPPED>
lan_ping_n20_min_ms=<float | na>
lan_ping_n20_p50_ms=<float | na>
lan_ping_n20_p95_ms=<float | na>
lan_ping_n20_max_ms=<float | na>
lan_stream_4kb_n30_status=<ALLOWED | BLOCKED_BY_OS | FAIL | TIMEOUT | INTERRUPTED | SKIPPED>
lan_stream_4kb_ttfb_ms=<float | na>
lan_stream_4kb_kbps=<float | na>
lan_stream_1x_n30_status=<ALLOWED | BLOCKED_BY_OS | FAIL | TIMEOUT | INTERRUPTED | SKIPPED>
lan_stream_1x_bytes=<int>
lan_stream_1x_ttfb_ms=<float | na>
lan_stream_1x_kbps=<float | na>
lan_stream_native_n30_status=<ALLOWED | BLOCKED_BY_OS | FAIL | TIMEOUT | INTERRUPTED | SKIPPED>
lan_stream_native_bytes=<int>
lan_stream_native_ttfb_ms=<float | na>
lan_stream_native_kbps=<float | na>
lan_post_input_n20_status=<ALLOWED | BLOCKED_BY_OS | FAIL | TIMEOUT | INTERRUPTED | SKIPPED>
lan_post_input_n20_min_ms=<float | na>
lan_post_input_n20_p50_ms=<float | na>
lan_post_input_n20_p95_ms=<float | na>
lan_post_input_n20_max_ms=<float | na>

[WCSESSION]
wcsession_status=<ALLOWED | BLOCKED_BY_OS | FAIL | TIMEOUT | INTERRUPTED | SKIPPED>
wcsession_detail=<deferred_to_v1_1 | domain:code | vocab_token>
wcsession_rtt_p50_ms=<float | na>
wcsession_throughput_kbps=<float | na>

[DECODE_CPU]
decode_1x_px=<WxH>
decode_native_px=<WxH>
zlib_1x_static_bytes=<int>
zlib_1x_static_p50_ms=<float | na>
zlib_1x_static_max_ms=<float | na>
zlib_1x_noisy_bytes=<int>
zlib_1x_noisy_p50_ms=<float | na>
zlib_1x_noisy_max_ms=<float | na>
zlib_native_static_bytes=<int>
zlib_native_static_p50_ms=<float | na>
zlib_native_static_max_ms=<float | na>
zlib_native_noisy_bytes=<int>
zlib_native_noisy_p50_ms=<float | na>
zlib_native_noisy_max_ms=<float | na>
cgimage_draw_rgba_native_p50_ms=<float | na>
cgimage_draw_rgba_native_max_ms=<float | na>
cgimage_draw_premul_native_p50_ms=<float | na>
cgimage_draw_premul_native_max_ms=<float | na>

[MEM_PEAK_AND_POST]
mem_peak_resident_mb=<float>
mem_peak_phys_footprint_mb=<float>
mem_peak_available_mb=<float | UNSUPPORTED>
mem_post_resident_mb=<float>
mem_post_phys_footprint_mb=<float>
mem_post_available_mb=<float | UNSUPPORTED>

[MEM_RAMP]
mem_ramp_status=<ALLOWED | BLOCKED_BY_OS | FAIL | TIMEOUT | INTERRUPTED | SKIPPED>
mem_ramp_prev_unclean_exit=<true | false>
mem_ramp_prev_last_ok_mb=<float | na>
mem_ramp_prev_last_resident_mb=<float | na>
mem_ramp_prev_last_phys_footprint_mb=<float | na>
mem_ramp_prev_last_available_mb=<float | UNSUPPORTED | na>

RESULT_JSON=<single-line compact JSON object containing all key/value fields above>
======== END GATE 0D ========
```

### Canonical Status Definitions & Detail Allowlist
Every `*_status` field MUST use exactly one of these six values:
- **`ALLOWED`**: Probe completed successfully (OS granted mapping or live echo/transfer succeeded).
- **`BLOCKED_BY_OS`**: OS policy denied or stalled the operation (e.g., `EPERM`/`EACCES` on executable mapping; `NWConnection` ending timeout in `WAITING(ENETDOWN)`; low-level socket/WS failure while `[NET_CONTROL]` HTTP ping succeeded).
- **`FAIL`**: Non-policy protocol, ATS (`-1022`), decode, or transport error.
- **`TIMEOUT`**: Deadline elapsed without completion and without an explicit OS block reason such as `ENETDOWN`.
- **`INTERRUPTED`**: Aborted mid-run because `scenePhase` left `.active` (`scene_left_active`) or user cancelled.
- **`SKIPPED`**: Intentionally omitted (e.g., `deferred_to_v1_1`, opt-in `[MEM_RAMP]` not invoked, or `[NET_LOWLEVEL]` skipped after `[NET_CONTROL]` failed).

**Strict `*_detail` grammar:** Must match `"domain:code"` (`NSPOSIXErrorDomain`, `NSURLErrorDomain`, `POSIX`, `NWError`, or `OtherDomain`, e.g. `NSPOSIXErrorDomain:50`, `NSURLErrorDomain:-1004`, `POSIX:13`, `OtherDomain:-99`) or one of these fixed vocabulary tokens:
`none`, `WAITING(ENETDOWN)`, `deferred_to_v1_1`, `scene_left_active`, `user_cancelled`, `clean_exit`, `timeout`, `skipped_control_failed`, `unsupported`.
*Never use `error.localizedDescription` or `String(describing:)`.* The CI validator enforces allowlist regex `^[a-zA-Z0-9_\(\)]+(:[a-zA-Z0-9_-]+)?$`.

### Strict Privacy & Formatting Rules
1. **One key per line + `RESULT_JSON=`:** No multi-field metric lines; `RESULT_JSON=` enables deterministic parsing.
2. **Never include host IP, hostname, `.local` name, UDID, serial number, or user-assigned device name:** Log only generic model identifiers from `hw.machine` (e.g., `Watch7,5`, `TODO(author): verify`), OS version, screen geometry, statuses, timings, and error codes.
3. **Mandatory context fields:** `SCREEN_PT`, `SCREEN_SCALE`, `LAUNCH_MODE`, `ATS_PROFILE`, `IPHONE_LINK`, `LAN_ROUTER_INTERNET`, `LOW_POWER_MODE`, `THERMAL_STATE`, and `LUMINANCE_REDUCED` must always be emitted.

### Results Submission Path
Contributors can submit results via either:
1. **Git PR:** Save the result block in `docs/results/YYYY-MM-DD-<DEVICE_MODEL>-<WATCHOS_VERSION>-<IPHONE_LINK>.md` using `docs/results/TEMPLATE.md` (sanitize `DEVICE_MODEL` for filenames by replacing commas with underscores, e.g. `Watch7,5` -> `Watch7_5`).
2. **GitHub Issue:** Open an issue titled `[Gate 0d] <DEVICE_MODEL> <WATCHOS_VERSION> (<IPHONE_LINK>)` and paste the exact block between `======== GATE 0D HARDWARE PROBE v1 ========` and `======== END GATE 0D ========`.

---

## 6. CI & Validation Plan (for Implementation Phase)

1. **Unsigned watchOS device SDK build (`--sdk watchos`, `CODE_SIGNING_ALLOWED=NO`):** Verify the SwiftUI probe compiles cleanly against the physical device SDK (catching any Simulator-only APIs such as `os_proc_available_memory` or `MAP_JIT` header discrepancies).
2. **Simulator negative-control run:** Boot the watchOS Simulator in CI alongside `probe_server.dart` (`dart:io` only) and run the probe suite. Expected Simulator result: all `[NET_LOWLEVEL]` probes (`bsd_socket_tcp`, `nw_connection_tcp`, `urlsession_websocket`) report **`ALLOWED`**, serving as the negative control confirming our probe + echo server connect when TN3135 does not block them.
3. **Result-block validator (`validate_gate0d.py`):** Assert exact start/end delimiters, one `KEY=VALUE` per line, valid 6-value status enums, strict detail regex, `RESULT_JSON=` consistency, and **zero leaked IPv4/IPv6 addresses, `.local` strings, or UUIDs**.

### Implementation Roadmap
- **Stage 6b:** Implement `mac_echo_server/probe_server.dart` (`dart:io` only) and `ci_validator/validate_gate0d.py` (fully testable on Linux/macOS CI).
- **Stage 6c:** Implement the watchOS SwiftUI probe app in `gate0d_probe/watch_app/` (using an XcodeGen `project.yml` for reproducible project generation rather than a manual `.pbxproj`).
