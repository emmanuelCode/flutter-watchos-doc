#!/usr/bin/env bash
# Generic runner for any Swift package under watchos-proofs/ (needs $WATCH_UDID).
# Usage: swift_pkg.sh build <pkgdir> <scheme>
#        swift_pkg.sh test  <pkgdir> <scheme> <TestTarget/TestClass>
# Success/failure is xcodebuild's own exit code.
MODE="$1"; PKG="$2"; SCHEME="$3"; ONLY="${4:-}"
cd "$(dirname "$0")/../$PKG" || exit 1
LOG="/tmp/xcodebuild_${PKG}_${MODE}_$(echo "$ONLY" | tr '/' '_').log"

if [ "$MODE" = "build" ]; then
  xcodebuild build-for-testing -scheme "$SCHEME" -destination "id=$WATCH_UDID" > "$LOG" 2>&1
else
  xcodebuild test -scheme "$SCHEME" -destination "id=$WATCH_UDID" -only-testing:"$ONLY" \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 30 > "$LOG" 2>&1
fi
CODE=$?

grep -E "Test Case|error:|\*\* (TEST )?BUILD|\*\* TEST|Testing failed|Unable to|failed|Cannot|requires" "$LOG" | cut -c1-240 | head -n 60
if [ "$CODE" -ne 0 ]; then
  echo "--- last 40 lines of xcodebuild output ---"
  tail -n 40 "$LOG" | cut -c1-240
fi
exit "$CODE"
