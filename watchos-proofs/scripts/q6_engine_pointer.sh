#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH_SDK="$(xcrun --sdk watchsimulator --show-sdk-path)"
SIM_UDID="${WATCH_UDID:-$(cat /tmp/watch_sim_udid 2>/dev/null || cat /tmp/watch_udid 2>/dev/null || xcrun simctl list devices booted | grep -E -o '[0-9A-F-]{36}' | head -n 1)}"

echo "Q6: using simulator $SIM_UDID"

xcrun --sdk watchsimulator clang -arch arm64 -mwatchos-simulator-version-min=10.0 \
  -isysroot "$WATCH_SDK" \
  -I "$ROOT/engine_probe" \
  "$ROOT/engine_probe/engine_host.c" \
  -o /tmp/engine/engine_host_q6 \
  -framework CoreFoundation

codesign --force -s - /tmp/engine/engine_host_q6

xcrun simctl spawn "$SIM_UDID" /tmp/engine/engine_host_q6 \
  /tmp/engine/FlutterEmbedder \
  /tmp/engine/flutter_assets \
  /tmp/engine/icudtl.dat \
  /tmp/engine_frame.bin \
  198 242 12 \
  /tmp/engine_frame2.bin > /tmp/engine/host_q6.out 2>&1 || {
    cat /tmp/engine/host_q6.out
    exit 1
  }

cat /tmp/engine/host_q6.out

python3 "$ROOT/scripts/frame_check.py" /tmp/engine_frame2.bin /tmp/engine_frame2.png --frame2

if cmp -s /tmp/engine_frame.bin /tmp/engine_frame2.bin; then
  echo "Q6: FAIL - frame 1 and frame 2 are identical"
  exit 1
else
  echo "Q6: PASS - frame 1 and frame 2 are distinct binary frames"
fi
