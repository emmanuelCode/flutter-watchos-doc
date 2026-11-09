#!/usr/bin/env bash
# Q1 — facts from the REAL engine source (at the exact engine version of this Flutter SDK), and a compile test:
# does the engine's own base layer (fml) compile for watchOS? Also fetches embedder.h for Q5.
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

echo "== compile the engine's fml base layer for the watchOS Simulator (syntax-only, C++20 as the engine requires) =="
find "$E/fml" \( -name '*.cc' -o -name '*.mm' \) \
  -not -name '*_unittest*' -not -name '*_benchmark*' -not -path '*/testing/*' \
  -not -path '*/platform/android/*' -not -path '*/platform/fuchsia/*' -not -path '*/platform/linux/*' -not -path '*/platform/win/*' \
  | sort > /tmp/fml_files.txt
TOTAL=$(wc -l < /tmp/fml_files.txt | tr -d ' ')
xargs -P 3 -I{} bash "$ROOT/scripts/syntax_check_one.sh" "$SRC" {} < /tmp/fml_files.txt > /tmp/fml_results.txt
OK=$(grep -c '^OK|' /tmp/fml_results.txt); FAIL=$(grep -c '^FAIL|' /tmp/fml_results.txt)
UNAVAIL=$(grep '^FAIL|' /tmp/fml_results.txt | grep -ciE "unavailable|not available on watchOS|is not supported")
MISSING=$(grep '^FAIL|' /tmp/fml_results.txt | grep -ciE "file not found")
rl "Q1: fml files: $TOTAL checked, $OK compile for watchOS, $FAIL fail ($UNAVAIL because an API is unavailable on watchOS, $MISSING because of a missing header from outside the sampled source)"
grep '^FAIL|' /tmp/fml_results.txt | head -n 12 | while IFS='|' read -r _ file err; do rl "Q1:   FAIL ${file#$SRC/engine/src/}: $err"; done
exit 0
