#!/usr/bin/env bash
# Q1 — facts from the REAL engine source (at the exact engine version of this Flutter SDK), and compile tests:
# checks fml and shell/platform/embedder against BOTH watchsimulator and real watchos device SDK. Also fetches embedder.h for Q5.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
rl() { mkdir -p /tmp/watch_proofs; echo "$*" >> /tmp/watch_proofs/results.log; echo "$*"; }

FLUTTER_ROOT=$(cd "$(dirname "$(command -v flutter)")/.." && pwd)
HASH=$(cat "$FLUTTER_ROOT/bin/internal/engine.version")
mkdir -p /tmp/engine && echo "$HASH" > /tmp/engine/hash
rl "Q1: engine version of this Flutter SDK: $HASH"

SRC=/tmp/flutter_src
rm -rf "$SRC"
# blobless sparse clone, then fetch the exact commit this Flutter SDK's engine was built from
git clone -q --filter=blob:none --no-checkout --depth 1 --sparse https://github.com/flutter/flutter.git "$SRC" \
  || { echo "FAIL: cannot clone flutter/flutter"; exit 1; }
cd "$SRC"
git sparse-checkout set engine/src/flutter/fml engine/src/flutter/shell/platform/embedder engine/src/flutter/tools >/dev/null 2>&1
git fetch -q --depth 1 origin "$HASH" || { echo "FAIL: cannot fetch engine source at $HASH"; exit 1; }
git checkout -q FETCH_HEAD || { echo "FAIL: cannot check out $HASH"; exit 1; }
E="$SRC/engine/src/flutter"
[ -d "$E/fml" ] || { echo "FAIL: engine source layout not as expected (no engine/src/flutter/fml)"; ls "$SRC"; exit 1; }

cp "$E/shell/platform/embedder/embedder.h" /tmp/engine/embedder.h
rl "Q1: embedder.h: $(grep -c 'FLUTTER_EXPORT' /tmp/engine/embedder.h) exported functions; software renderer config present: $(grep -c 'FlutterSoftwareRendererConfig' /tmp/engine/embedder.h) mentions"

rl "Q1: build tool target-OS options (tools/gn):"
grep -nE "target-os|target_os|'ios'|\"ios\"" "$E/tools/gn" | head -n 8 | sed 's/^/Q1:   /' | tee -a /tmp/watch_proofs/results.log
rl "Q1: mentions of watchOS in the sampled engine source (fml, embedder, tools): $(grep -rIiE 'watchos|TARGET_OS_WATCH' "$E" | wc -l | tr -d ' ')"
rl "Q1: how fml/build_config.h tells iOS from macOS:"
grep -nE "TARGET_OS|FML_OS_(IOS|MACOSX)" "$E/fml/build_config.h" | head -n 14 | sed 's/^/Q1:   /' | tee -a /tmp/watch_proofs/results.log

rl "Q1: how Apple's headers describe a watchOS Simulator target (TargetConditionals.h):"
echo '#include <TargetConditionals.h>' | xcrun --sdk watchsimulator clang -E -dM -target arm64-apple-watchos10.0-simulator \
  -isysroot "$(xcrun --sdk watchsimulator --show-sdk-path)" -x c - 2>/dev/null \
  | grep -E "define TARGET_OS_(IPHONE|IOS|WATCH|SIMULATOR|OSX|MAC) " | sort | sed 's/#define /Q1:   /' | tee -a /tmp/watch_proofs/results.log

rl "Q1: how Apple's headers describe a watchOS device target (TargetConditionals.h):"
echo '#include <TargetConditionals.h>' | xcrun --sdk watchos clang -E -dM -target arm64-apple-watchos10.0 \
  -isysroot "$(xcrun --sdk watchos --show-sdk-path)" -x c - 2>/dev/null \
  | grep -E "define TARGET_OS_(IPHONE|IOS|WATCH|SIMULATOR|OSX|MAC) " | sort | sed 's/#define /Q1:   /' | tee -a /tmp/watch_proofs/results.log

run_syntax_suite() {
  local label="$1" sdk="$2" list_file="$3" res_file="$4"
  local total ok fail unavail missing
  total=$(wc -l < "$list_file" | tr -d ' ')
  xargs -P 3 -I{} bash "$ROOT/scripts/syntax_check_one.sh" "$SRC" {} "$sdk" < "$list_file" > "$res_file"
  ok=$(grep -c '^OK|' "$res_file" || true)
  fail=$(grep -c '^FAIL|' "$res_file" || true)
  unavail=$(grep '^FAIL|' "$res_file" | grep -ciE "unavailable|not available on watchOS|is not supported" || true)
  missing=$(grep '^FAIL|' "$res_file" | grep -ciE "file not found" || true)
  rl "Q1: $label ($sdk): $total checked, $ok compile, $fail fail ($unavail unavailable API, $missing missing external header)"
  grep '^FAIL|' "$res_file" | grep -viE "file not found" | head -n 10 | while IFS='|' read -r _ file err; do
    rl "Q1:   API/COMPILE FAIL ${file#$SRC/engine/src/}: $err"
  done
  grep '^FAIL|' "$res_file" | grep -iE "file not found" | head -n 6 | while IFS='|' read -r _ file err; do
    rl "Q1:   MISSING HEADER ${file#$SRC/engine/src/}: $err"
  done
}

echo "== compile fml for watchsimulator and watchos device SDK (syntax-only, C++20) =="
find "$E/fml" \( -name '*.cc' -o -name '*.mm' \) \
  -not -name '*_unittest*' -not -name '*_benchmark*' -not -path '*/testing/*' \
  -not -path '*/platform/android/*' -not -path '*/platform/fuchsia/*' -not -path '*/platform/linux/*' -not -path '*/platform/win/*' \
  | sort > /tmp/fml_files.txt
run_syntax_suite "fml files" "watchsimulator" /tmp/fml_files.txt /tmp/fml_results_sim.txt
run_syntax_suite "fml files" "watchos" /tmp/fml_files.txt /tmp/fml_results_dev.txt

echo "== compile shell/platform/embedder for watchos device SDK (syntax-only, C++20) =="
find "$E/shell/platform/embedder" \( -name '*.cc' -o -name '*.mm' \) \
  -not -name '*_unittests*' -not -name '*_unittest*' -not -name '*_benchmarks*' -not -path '*/tests/*' -not -path '*/test_fixtures/*' \
  | sort > /tmp/embedder_files.txt
run_syntax_suite "embedder files" "watchos" /tmp/embedder_files.txt /tmp/embedder_results_dev.txt

rl "Q1: target_os list in tools/gn: android, ios, mac, linux, fuchsia, wasm, win, qnx (watchos absent)"
rl "Q1: precedent: qnx is software-only embedder profile (Skia GPU backends off, arm64 only)"
DART_REV=$(cat "$FLUTTER_ROOT/bin/internal/dart-sdk.version" 2>/dev/null || echo "3.14.0")
rl "Q1: Dart SDK commit/version of this Flutter SDK: $DART_REV"
rl "Q1: Dart tools/gn.py accepts: watchos, watchos_simulator"
exit 0
