#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH_SDK="$(xcrun --sdk watchsimulator --show-sdk-path)"
SIM_UDID="${WATCH_UDID:-$(cat /tmp/watch_sim_udid 2>/dev/null || cat /tmp/watch_udid 2>/dev/null || xcrun simctl list devices booted | grep -E -o '[0-9A-F-]{36}' | head -n 1)}"

echo "Q6: using simulator $SIM_UDID"

# 1. Borrow include flags from Q5 and search for embedder.h
Q5_INCS=$(grep -oE '\-I[[:space:]]*[^[:space:]]+' "$ROOT/scripts/q5_run_engine.sh" 2>/dev/null || true)
FLUTTER_SDK="$(dirname "$(dirname "$(which flutter 2>/dev/null || echo /dev/null)")")"
SEARCH_DIRS=("/tmp" "$ROOT")
[ -d "$FLUTTER_SDK" ] && SEARCH_DIRS+=("$FLUTTER_SDK")
[ -d "$HOME" ] && SEARCH_DIRS+=("$HOME")

set +e
FOUND_INCS=()
while IFS= read -r dir; do
  [ -n "$dir" ] && FOUND_INCS+=("-I" "$dir")
done < <(find -L "${SEARCH_DIRS[@]}" -name "embedder.h" -exec dirname {} \; 2>/dev/null | sort -u)
set -e

ALL_INCS=("-I" "$ROOT/engine_probe" $Q5_INCS "${FOUND_INCS[@]}")

xcrun --sdk watchsimulator clang -arch arm64 -mwatchos-simulator-version-min=10.0 \
  -isysroot "$WATCH_SDK" \
  "${ALL_INCS[@]}" \
  "$ROOT/engine_probe/engine_host.c" \
  -o /tmp/engine/engine_host_q6 \
  -framework CoreFoundation

codesign --force -s - /tmp/engine/engine_host_q6

# Safely locate assets (directory containing kernel_blob.bin), ICU, and engine library
set +e
BLOB_PATH=$(find /tmp "$ROOT" -name "kernel_blob.bin" 2>/dev/null | head -n 1)
ASSETS_DIR=$(dirname "$BLOB_PATH" 2>/dev/null || true)
ICU_PATH=$(find /tmp "$ROOT" -name "icudtl.dat" 2>/dev/null | head -n 1)
ENGINE_LIB=$(find /tmp/engine/watchos -name "FlutterEmbedder" 2>/dev/null | head -n 1)
set -e

[ -z "$ASSETS_DIR" ] && ASSETS_DIR="/tmp/engine/flutter_assets"
[ -z "$ICU_PATH" ] && ICU_PATH="/tmp/engine/icudtl.dat"
[ -z "$ENGINE_LIB" ] && ENGINE_LIB="/tmp/engine/watchos/FlutterEmbedder"

echo "Q6: ENGINE_LIB=$ENGINE_LIB"
echo "Q6: ASSETS_DIR=$ASSETS_DIR"
echo "Q6: ICU_PATH=$ICU_PATH"

if [ ! -f "$ENGINE_LIB" ]; then echo "Q6: ERROR: ENGINE_LIB $ENGINE_LIB not found"; exit 1; fi
if [ ! -d "$ASSETS_DIR" ]; then echo "Q6: ERROR: ASSETS_DIR $ASSETS_DIR not found"; exit 1; fi
if [ ! -f "$ICU_PATH" ]; then echo "Q6: ERROR: ICU_PATH $ICU_PATH not found"; exit 1; fi

xcrun simctl spawn "$SIM_UDID" /tmp/engine/engine_host_q6 \
  "$ENGINE_LIB" \
  "$ASSETS_DIR" \
  "$ICU_PATH" \
  /tmp/engine_frame.bin \
  198 242 12 \
  /tmp/engine_frame2.bin > /tmp/engine/host_q6.out 2>&1 || {
    echo "Q6: host failed with exit code $?"
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
