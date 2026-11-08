#!/usr/bin/env bash
# P0 — the Swift code compiles for watchOS. Also picks the scheme the test steps will use.
set -eo pipefail
cd "$(dirname "$0")/../swift_proofs"

LIST=$(xcodebuild -list 2>&1) || true
echo "$LIST"
if echo "$LIST" | grep -q "WatchProofs-Package"; then SCHEME="WatchProofs-Package"; else SCHEME="WatchProofs"; fi
echo "INFO: scheme $SCHEME"
echo "SCHEME=$SCHEME" >> "${GITHUB_ENV:-/dev/null}"

xcodebuild build-for-testing -scheme "$SCHEME" -destination "id=$WATCH_UDID" 2>&1 \
  | tee /tmp/xcodebuild_P0.log | grep -E "error:|\*\* BUILD"
