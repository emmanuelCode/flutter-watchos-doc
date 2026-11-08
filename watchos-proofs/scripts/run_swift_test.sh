#!/usr/bin/env bash
# Usage: run_swift_test.sh <TestClassName>   (needs $WATCH_UDID; $SCHEME is set by build_swift.sh)
# Success/failure is xcodebuild's own exit code.
cd "$(dirname "$0")/../swift_proofs"
LOG="/tmp/xcodebuild_$1.log"

xcodebuild test \
  -scheme "${SCHEME:-WatchProofs}" \
  -destination "id=$WATCH_UDID" \
  -only-testing:"WatchProofsTests/$1" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 30 \
  > "$LOG" 2>&1
CODE=$?

grep -E "Test Case|error:|\*\* TEST|Testing failed|Unable to|failed|Cannot|requires" "$LOG" | cut -c1-240 | head -n 60
if [ "$CODE" -ne 0 ]; then
  echo "--- last 40 lines of xcodebuild output ---"
  tail -n 40 "$LOG" | cut -c1-240
fi
exit "$CODE"
