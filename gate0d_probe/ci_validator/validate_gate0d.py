#!/usr/bin/env python3
"""Gate 0d Result Block Validator.

Enforces strict grammar, valid enums, exact RESULT_JSON equivalence, and
verifies zero leaked IP addresses, .local names, UUIDs, or usernames.
Usage:
  python3 validate_gate0d.py <file-to-validate>
  python3 validate_gate0d.py --test
"""

import json
import re
import sys
import tempfile
from pathlib import Path

ALLOWED_STATUSES = {"ALLOWED", "BLOCKED_BY_OS", "FAIL", "TIMEOUT", "INTERRUPTED", "SKIPPED"}
ALLOWED_VOCAB_TOKENS = {
    "none",
    "WAITING(ENETDOWN)",
    "deferred_to_v1_1",
    "scene_left_active",
    "user_cancelled",
    "clean_exit",
    "timeout",
    "skipped_control_failed",
    "unsupported",
}
DETAIL_REGEX = re.compile(r"^(NSPOSIXErrorDomain|NSURLErrorDomain|POSIX|NWError|OtherDomain):-?\d+$")

RE_IPV4 = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
RE_IPV6 = re.compile(r"\b(?:[0-9a-fA-F]{1,4}:){2,7}[0-9a-fA-F]{1,4}\b")
RE_LOCAL = re.compile(r"\.local\b", re.IGNORECASE)
RE_UUID = re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")
RE_USER_PATH = re.compile(r"/(?:Users|home)/[a-zA-Z0-9_\-]+")

SECTIONS = {
    "[MEM_BASELINE]",
    "[JIT]",
    "[NW_PATH_MONITOR]",
    "[NET_ACTUAL_PATH]",
    "[NET_CONTROL]",
    "[NET_LOWLEVEL]",
    "[MDNS_LOCAL]",
    "[LAN_URLSESSION_BYTES]",
    "[WCSESSION]",
    "[DECODE_CPU]",
    "[MEM_PEAK_AND_POST]",
    "[MEM_RAMP]",
}

ENUM_RULES = {
    "PROBE_SPEC_VERSION": {"1"},
    "ARCH": {"arm64", "arm64_32", "x86_64"},
    "LAUNCH_MODE": {"xcode_debugger", "standalone_watch", "unknown"},
    "ATS_PROFILE": {"relaxed", "strict", "unknown"},
    "IPHONE_LINK": {"available", "unavailable"},
    "LAN_ROUTER_INTERNET": {"yes", "no", "offline_test"},
    "LOW_POWER_MODE": {"true", "false"},
    "THERMAL_STATE": {"nominal", "fair", "serious", "critical"},
    "LUMINANCE_REDUCED": {"true", "false"},
    "nw_path_status": {"satisfied", "unsatisfied", "requiresConnection", "unknown"},
    "nw_path_unsatisfied_reason": {"none", "not_available", "cellular_denied", "wifi_denied", "local_network_denied", "unknown"},
    "net_path_hint": {"wifi", "cellular", "companion_proxy", "unknown"},
    "net_actual_protocol": {"h2", "h3", "http/1.1", "tcp", "unknown", "na"},
    "mem_ramp_prev_unclean_exit": {"true", "false"},
}

def is_float(s: str) -> bool:
    try:
        float(s)
        return True
    except ValueError:
        return False

def is_int(s: str) -> bool:
    try:
        int(s)
        return True
    except ValueError:
        return False

def validate_detail(val: str, key_name: str) -> None:
    if val in ALLOWED_VOCAB_TOKENS or DETAIL_REGEX.match(val):
        return
    raise ValueError(f"Invalid detail token '{val}' for {key_name}; must match domain:code or fixed vocabulary")

def validate_block(text: str) -> dict:
    start_tag = "======== GATE 0D HARDWARE PROBE v1 ========"
    end_tag = "======== END GATE 0D ========"

    if start_tag not in text or end_tag not in text:
        raise ValueError(f"Missing start/end delimiters ({start_tag} ... {end_tag})")

    body = text.split(start_tag, 1)[1].split(end_tag, 1)[0]

    # Privacy / IP leak assertions
    if RE_IPV4.search(body):
        raise ValueError("Privacy violation: leaked IPv4 address detected")
    if RE_IPV6.search(body):
        raise ValueError("Privacy violation: leaked IPv6 address detected")
    if RE_LOCAL.search(body):
        raise ValueError("Privacy violation: leaked .local hostname detected")
    if RE_UUID.search(body):
        raise ValueError("Privacy violation: leaked UUID detected")
    if RE_USER_PATH.search(body):
        raise ValueError("Privacy violation: leaked local user filesystem path detected")

    lines = [ln.strip() for ln in body.splitlines() if ln.strip()]
    kv = {}
    json_val = None

    for ln in lines:
        if ln in SECTIONS:
            continue
        if ln.startswith("RESULT_JSON="):
            json_str = ln[len("RESULT_JSON="):].strip()
            try:
                json_val = json.loads(json_str)
            except Exception as e:
                raise ValueError(f"Malformed RESULT_JSON line: {e}")
            continue

        if "=" not in ln:
            raise ValueError(f"Unexpected line format (expected KEY=VALUE or section): '{ln}'")

        k, v = ln.split("=", 1)
        k, v = k.strip(), v.strip()
        if k in kv:
            raise ValueError(f"Duplicate key: '{k}'")
        kv[k] = v

    req_headers = [
        "PROBE_SPEC_VERSION", "TIMESTAMP_UTC", "DEVICE_MODEL", "WATCHOS_VERSION",
        "ARCH", "SCREEN_PT", "SCREEN_SCALE", "LAUNCH_MODE", "ATS_PROFILE",
        "IPHONE_LINK", "LAN_ROUTER_INTERNET", "LOW_POWER_MODE", "THERMAL_STATE",
        "LUMINANCE_REDUCED"
    ]
    for h in req_headers:
        if h not in kv:
            raise ValueError(f"Missing required header '{h}'")

    if not re.match(r"^\d+x\d+$", kv["SCREEN_PT"]):
        raise ValueError(f"SCREEN_PT must be WxH (got {kv['SCREEN_PT']})")
    if not is_float(kv["SCREEN_SCALE"]):
        raise ValueError(f"SCREEN_SCALE must be float (got {kv['SCREEN_SCALE']})")

    for k, allowed in ENUM_RULES.items():
        if k in kv and kv[k] not in allowed:
            raise ValueError(f"Value '{kv[k]}' for key '{k}' not in allowed set {allowed}")

    for k, v in kv.items():
        if k.endswith("_status") and k != "nw_path_status":
            if v not in ALLOWED_STATUSES:
                raise ValueError(f"Invalid status '{v}' for key '{k}' (allowed: {ALLOWED_STATUSES})")
        elif k.endswith("_detail"):
            validate_detail(v, k)
        elif k.endswith("_mb") or k.endswith("_ms") or k.endswith("_kbps"):
            if v != "na" and v != "UNSUPPORTED" and not is_float(v):
                raise ValueError(f"Value '{v}' for float/na key '{k}' is neither float nor na")
        elif k.endswith("_bytes") or k.endswith("_count"):
            if not is_int(v):
                raise ValueError(f"Value '{v}' for integer key '{k}' is not an int")

    if json_val is None:
        raise ValueError("Missing RESULT_JSON= line")

    if set(kv.keys()) != set(json_val.keys()):
        diff = set(kv.keys()) ^ set(json_val.keys())
        raise ValueError(f"Keys in key=value lines do not match keys in RESULT_JSON: mismatch={diff}")

    for k, v in kv.items():
        jv = str(json_val[k])
        if jv != v:
            raise ValueError(f"Value mismatch for '{k}': block has '{v}', JSON has '{jv}'")

    return kv

GOLDEN_GOOD = """
======== GATE 0D HARDWARE PROBE v1 ========
PROBE_SPEC_VERSION=1
TIMESTAMP_UTC=2026-11-15T04:00:00Z
DEVICE_MODEL=Watch7_5
WATCHOS_VERSION=26.5
ARCH=arm64
SCREEN_PT=208x248
SCREEN_SCALE=2.0
LAUNCH_MODE=standalone_watch
ATS_PROFILE=relaxed
IPHONE_LINK=available
LAN_ROUTER_INTERNET=yes
LOW_POWER_MODE=false
THERMAL_STATE=nominal
LUMINANCE_REDUCED=false

[MEM_BASELINE]
mem_baseline_resident_mb=18.42
mem_baseline_phys_footprint_mb=14.10
mem_baseline_available_mb=UNSUPPORTED

[JIT]
jit_mmap_status=BLOCKED_BY_OS
jit_mmap_detail=POSIX:13
jit_mprotect_status=BLOCKED_BY_OS
jit_mprotect_detail=POSIX:13

[NW_PATH_MONITOR]
nw_path_status=unsatisfied
nw_path_unsatisfied_reason=none

[NET_ACTUAL_PATH]
net_path_hint=companion_proxy
net_actual_protocol=h2

[NET_CONTROL]
http_ping_ip_status=ALLOWED
http_ping_ip_rtt_ms=18.4
http_ping_ip_detail=none
https_ping_ip_status=SKIPPED
https_ping_ip_rtt_ms=na
https_ping_ip_detail=none

[NET_LOWLEVEL]
bsd_socket_tcp_status=BLOCKED_BY_OS
bsd_socket_tcp_rtt_ms=na
bsd_socket_tcp_detail=POSIX:1
nw_connection_tcp_status=BLOCKED_BY_OS
nw_connection_tcp_rtt_ms=na
nw_connection_tcp_detail=WAITING(ENETDOWN)
urlsession_websocket_status=BLOCKED_BY_OS
urlsession_websocket_rtt_ms=na
urlsession_websocket_detail=NSPOSIXErrorDomain:50

[MDNS_LOCAL]
getaddrinfo_local_status=ALLOWED
getaddrinfo_local_ms=4.2
getaddrinfo_local_addr_count=1
getaddrinfo_local_detail=none
http_ping_local_status=ALLOWED
http_ping_local_rtt_ms=21.1
http_ping_local_detail=none

[LAN_URLSESSION_BYTES]
lan_ping_n20_status=ALLOWED
lan_ping_n20_min_ms=16.1
lan_ping_n20_p50_ms=18.9
lan_ping_n20_p95_ms=24.5
lan_ping_n20_max_ms=28.1
lan_stream_4kb_n30_status=ALLOWED
lan_stream_4kb_ttfb_ms=24.2
lan_stream_4kb_kbps=1820.0
lan_stream_1x_n30_status=ALLOWED
lan_stream_1x_bytes=206336
lan_stream_1x_ttfb_ms=31.0
lan_stream_1x_kbps=2410.5
lan_stream_native_n30_status=ALLOWED
lan_stream_native_bytes=825344
lan_stream_native_ttfb_ms=44.1
lan_stream_native_kbps=2950.0
lan_post_input_n20_status=ALLOWED
lan_post_input_n20_min_ms=14.0
lan_post_input_n20_p50_ms=17.2
lan_post_input_n20_p95_ms=22.0
lan_post_input_n20_max_ms=25.4

[WCSESSION]
wcsession_status=SKIPPED
wcsession_detail=deferred_to_v1_1
wcsession_rtt_p50_ms=na
wcsession_throughput_kbps=na

[DECODE_CPU]
decode_1x_px=208x248
decode_native_px=416x496
zlib_1x_static_bytes=1047
zlib_1x_static_p50_ms=1.1
zlib_1x_static_max_ms=2.2
zlib_1x_noisy_bytes=98432
zlib_1x_noisy_p50_ms=12.4
zlib_1x_noisy_max_ms=16.8
zlib_native_static_bytes=3935
zlib_native_static_p50_ms=4.8
zlib_native_static_max_ms=7.1
zlib_native_noisy_bytes=382100
zlib_native_noisy_p50_ms=38.2
zlib_native_noisy_max_ms=49.1
cgimage_draw_rgba_native_p50_ms=3.4
cgimage_draw_rgba_native_max_ms=5.2
cgimage_draw_premul_native_p50_ms=1.8
cgimage_draw_premul_native_max_ms=3.0

[MEM_PEAK_AND_POST]
mem_peak_resident_mb=24.50
mem_peak_phys_footprint_mb=19.80
mem_peak_available_mb=UNSUPPORTED
mem_post_resident_mb=19.10
mem_post_phys_footprint_mb=14.60
mem_post_available_mb=UNSUPPORTED

[MEM_RAMP]
mem_ramp_status=SKIPPED
mem_ramp_prev_unclean_exit=false
mem_ramp_prev_last_ok_mb=na
mem_ramp_prev_last_resident_mb=na
mem_ramp_prev_last_phys_footprint_mb=na
mem_ramp_prev_last_available_mb=na

RESULT_JSON={"PROBE_SPEC_VERSION":"1","TIMESTAMP_UTC":"2026-11-15T04:00:00Z","DEVICE_MODEL":"Watch7_5","WATCHOS_VERSION":"26.5","ARCH":"arm64","SCREEN_PT":"208x248","SCREEN_SCALE":"2.0","LAUNCH_MODE":"standalone_watch","ATS_PROFILE":"relaxed","IPHONE_LINK":"available","LAN_ROUTER_INTERNET":"yes","LOW_POWER_MODE":"false","THERMAL_STATE":"nominal","LUMINANCE_REDUCED":"false","mem_baseline_resident_mb":"18.42","mem_baseline_phys_footprint_mb":"14.10","mem_baseline_available_mb":"UNSUPPORTED","jit_mmap_status":"BLOCKED_BY_OS","jit_mmap_detail":"POSIX:13","jit_mprotect_status":"BLOCKED_BY_OS","jit_mprotect_detail":"POSIX:13","nw_path_status":"unsatisfied","nw_path_unsatisfied_reason":"none","net_path_hint":"companion_proxy","net_actual_protocol":"h2","http_ping_ip_status":"ALLOWED","http_ping_ip_rtt_ms":"18.4","http_ping_ip_detail":"none","https_ping_ip_status":"SKIPPED","https_ping_ip_rtt_ms":"na","https_ping_ip_detail":"none","bsd_socket_tcp_status":"BLOCKED_BY_OS","bsd_socket_tcp_rtt_ms":"na","bsd_socket_tcp_detail":"POSIX:1","nw_connection_tcp_status":"BLOCKED_BY_OS","nw_connection_tcp_rtt_ms":"na","nw_connection_tcp_detail":"WAITING(ENETDOWN)","urlsession_websocket_status":"BLOCKED_BY_OS","urlsession_websocket_rtt_ms":"na","urlsession_websocket_detail":"NSPOSIXErrorDomain:50","getaddrinfo_local_status":"ALLOWED","getaddrinfo_local_ms":"4.2","getaddrinfo_local_addr_count":"1","getaddrinfo_local_detail":"none","http_ping_local_status":"ALLOWED","http_ping_local_rtt_ms":"21.1","http_ping_local_detail":"none","lan_ping_n20_status":"ALLOWED","lan_ping_n20_min_ms":"16.1","lan_ping_n20_p50_ms":"18.9","lan_ping_n20_p95_ms":"24.5","lan_ping_n20_max_ms":"28.1","lan_stream_4kb_n30_status":"ALLOWED","lan_stream_4kb_ttfb_ms":"24.2","lan_stream_4kb_kbps":"1820.0","lan_stream_1x_n30_status":"ALLOWED","lan_stream_1x_bytes":"206336","lan_stream_1x_ttfb_ms":"31.0","lan_stream_1x_kbps":"2410.5","lan_stream_native_n30_status":"ALLOWED","lan_stream_native_bytes":"825344","lan_stream_native_ttfb_ms":"44.1","lan_stream_native_kbps":"2950.0","lan_post_input_n20_status":"ALLOWED","lan_post_input_n20_min_ms":"14.0","lan_post_input_n20_p50_ms":"17.2","lan_post_input_n20_p95_ms":"22.0","lan_post_input_n20_max_ms":"25.4","wcsession_status":"SKIPPED","wcsession_detail":"deferred_to_v1_1","wcsession_rtt_p50_ms":"na","wcsession_throughput_kbps":"na","decode_1x_px":"208x248","decode_native_px":"416x496","zlib_1x_static_bytes":"1047","zlib_1x_static_p50_ms":"1.1","zlib_1x_static_max_ms":"2.2","zlib_1x_noisy_bytes":"98432","zlib_1x_noisy_p50_ms":"12.4","zlib_1x_noisy_max_ms":"16.8","zlib_native_static_bytes":"3935","zlib_native_static_p50_ms":"4.8","zlib_native_static_max_ms":"7.1","zlib_native_noisy_bytes":"382100","zlib_native_noisy_p50_ms":"38.2","zlib_native_noisy_max_ms":"49.1","cgimage_draw_rgba_native_p50_ms":"3.4","cgimage_draw_rgba_native_max_ms":"5.2","cgimage_draw_premul_native_p50_ms":"1.8","cgimage_draw_premul_native_max_ms":"3.0","mem_peak_resident_mb":"24.50","mem_peak_phys_footprint_mb":"19.80","mem_peak_available_mb":"UNSUPPORTED","mem_post_resident_mb":"19.10","mem_post_phys_footprint_mb":"14.60","mem_post_available_mb":"UNSUPPORTED","mem_ramp_status":"SKIPPED","mem_ramp_prev_unclean_exit":"false","mem_ramp_prev_last_ok_mb":"na","mem_ramp_prev_last_resident_mb":"na","mem_ramp_prev_last_phys_footprint_mb":"na","mem_ramp_prev_last_available_mb":"na"}
======== END GATE 0D ========
"""

def run_tests() -> None:
    try:
        validate_block(GOLDEN_GOOD)
        other_good = GOLDEN_GOOD.replace("jit_mmap_detail=POSIX:13", "jit_mmap_detail=OtherDomain:-99").replace('"jit_mmap_detail":"POSIX:13"', '"jit_mmap_detail":"OtherDomain:-99"')
        validate_block(other_good)
        print("PASS: Golden good fixture and OtherDomain token validated cleanly")
    except Exception as e:
        print(f"FAIL: Golden good fixture rejected: {e}")
        sys.exit(1)

    bad_cases = [
        ("Leaked IPv4", GOLDEN_GOOD.replace("none", "192.168.1.100", 1), "IPv4"),
        ("Leaked .local", GOLDEN_GOOD.replace("none", "devhost.local", 1), ".local"),
        ("Leaked UUID", GOLDEN_GOOD.replace("Watch7_5", "12345678-1234-1234-1234-123456789abc"), "UUID"),
        ("Invalid status enum", GOLDEN_GOOD.replace("jit_mmap_status=BLOCKED_BY_OS", "jit_mmap_status=GRANTED"), "Invalid status"),
        ("Free text detail", GOLDEN_GOOD.replace("POSIX:13", "Permission denied by kernel"), "Invalid detail token"),
        ("Invalid protocol enum", GOLDEN_GOOD.replace("net_actual_protocol=h2", "net_actual_protocol=spdy"), "not in allowed set"),
        ("JSON mismatch", GOLDEN_GOOD.replace('"mem_baseline_resident_mb":"18.42"', '"mem_baseline_resident_mb":"99.99"'), "Value mismatch"),
        ("Extra free text line", GOLDEN_GOOD.replace("[JIT]", "[JIT] extra line without equals"), "Unexpected line format"),
    ]

    for label, bad_text, expected_substr in bad_cases:
        try:
            validate_block(bad_text)
            print(f"FAIL: Expected bad fixture '{label}' to fail, but it passed!")
            sys.exit(1)
        except ValueError as err:
            if expected_substr.lower() not in str(err).lower():
                print(f"FAIL: Bad fixture '{label}' failed with unexpected error: {err}")
                sys.exit(1)
            print(f"PASS: Bad fixture '{label}' correctly rejected ({err})")

    with tempfile.NamedTemporaryFile("w", suffix=".txt", encoding="utf-8", delete=False) as tf:
        tf.write(GOLDEN_GOOD)
        tmp_path = Path(tf.name)
    try:
        validate_block(tmp_path.read_text(encoding="utf-8"))
        print("PASS: File Path read_text validated cleanly")
    finally:
        tmp_path.unlink(missing_ok=True)

    print()
    print("ALL VALIDATOR TESTS PASSED")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--test":
        run_tests()
        sys.exit(0)
    if len(sys.argv) < 2:
        print("usage: validate_gate0d.py <file> | --test")
        sys.exit(1)
    content = Path(sys.argv[1]).read_text(encoding="utf-8")
    try:
        validate_block(content)
        print(f"GATE 0D VALIDATION OK: {sys.argv[1]}")
    except Exception as e:
        print(f"GATE 0D VALIDATION FAIL: {e}")
        sys.exit(1)
