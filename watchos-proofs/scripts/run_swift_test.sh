#!/usr/bin/env bash
# Usage: run_swift_test.sh <TestClassName>   (needs $WATCH_UDID; $SCHEME is set by build_swift.sh)
set -o pipefail
cd "$(dirname "$0")/../swift_proofs"
xcodebuild test \
  -scheme "${SCHEME:-WatchProofs}" \
  -destination "id=$WATCH_UDID" \
  -only-testing:"WatchProofsTests/$1" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 30 \
  2>&1 | tee "/tmp/xcodebuild_$1.log" | grep -E "Test Case|error:|\*\* TEST|Testing failed|Unable to|failed"
