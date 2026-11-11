#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH_SDK="$(xcrun --sdk watchsimulator --show-sdk-path)"
SIM_UDID="${WATCH_UDID:-$(cat /tmp/watch_sim_udid 2>/dev/null || cat /tmp/watch_udid 2>/dev/null || xcrun simctl list devices booted | grep -E -o '[0-9A-F-]{36}' | head -n 1)}"

echo "Q7: using simulator $SIM_UDID"

# 1. Borrow include flags from Q5
Q5_INCS=$(grep -oE '\-I[[:space:]]*[^[:space:]]+' "$ROOT/scripts/q5_run_engine.sh" 2>/dev/null || true)

# 2. Search Flutter SDK cache, /tmp, $ROOT, and $HOME (following symlinks)
FLUTTER_SDK="$(dirname "$(dirname "$(which flutter 2>/dev/null || echo /dev/null)")")"
SEARCH_DIRS=("/tmp" "$ROOT")
[ -d "$FLUTTER_SDK" ] && SEARCH_DIRS+=("$FLUTTER_SDK")
[ -d "$HOME" ] && SEARCH_DIRS+=("$HOME")

FOUND_INCS=()
while IFS= read -r dir; do
  [ -n "$dir" ] && FOUND_INCS+=("-I" "$dir")
done < <(find -L "${SEARCH_DIRS[@]}" -name "embedder.h" -exec dirname {} \; 2>/dev/null | sort -u)

ALL_INCS=("-I" "$ROOT/engine_probe" $Q5_INCS "${FOUND_INCS[@]}")

xcrun --sdk watchsimulator clang -arch arm64 -mwatchos-simulator-version-min=10.0 \
  -isysroot "$WATCH_SDK" \
  "${ALL_INCS[@]}" \
  "$ROOT/engine_probe/engine_host.c" \
  -o /tmp/engine/engine_host_q7 \
  -framework CoreFoundation

codesign --force -s - /tmp/engine/engine_host_q7

# Use the retagged, patched engine library in /tmp/engine/watchos/FlutterEmbedder
xcrun simctl spawn "$SIM_UDID" /tmp/engine/engine_host_q7 \
  /tmp/engine/watchos/FlutterEmbedder \
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
