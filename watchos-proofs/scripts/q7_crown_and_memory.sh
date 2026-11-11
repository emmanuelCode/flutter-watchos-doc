#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH_SDK="$(xcrun --sdk watchsimulator --show-sdk-path)"
SIM_UDID="${WATCH_UDID:-$(cat /tmp/watch_sim_udid 2>/dev/null || cat /tmp/watch_udid 2>/dev/null || xcrun simctl list devices booted | grep -E -o '[0-9A-F-]{36}' | head -n 1)}"

echo "Q7: using simulator $SIM_UDID"

xcrun --sdk watchsimulator clang -arch arm64 -mwatchos-simulator-version-min=10.0 \
  -isysroot "$WATCH_SDK" \
  -I "$ROOT/engine_probe" \
  "$ROOT/engine_probe/engine_host.c" \
  -o /tmp/engine/engine_host_q7 \
  -framework CoreFoundation

codesign --force -s - /tmp/engine/engine_host_q7

xcrun simctl spawn "$SIM_UDID" /tmp/engine/engine_host_q7 \
  /tmp/engine/FlutterEmbedder \
  /tmp/engine/flutter_assets \
  /tmp/engine/icudtl.dat \
  /tmp/engine_frame.bin \
  198 242 15 \
  /tmp/engine_frame2.bin \
  /tmp/engine_frame3.bin > /tmp/engine/host_q7.out 2>&1 || {
    cat /tmp/engine/host_q7.out
    exit 1
  }

cat /tmp/engine/host_q7.out

python3 "$ROOT/scripts/frame_check.py" /tmp/engine_frame3.bin /tmp/engine_frame3.png --frame3

if cmp -s /tmp/engine_frame2.bin /tmp/engine_frame3.bin; then
  echo "Q7: FAIL - frame 2 and frame 3 are identical"
  exit 1
else
  echo "Q7: PASS - frame 2 and frame 3 are distinct binary frames"
fi
