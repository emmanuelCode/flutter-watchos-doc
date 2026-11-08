#!/usr/bin/env bash
# P0 — the Swift code compiles for watchOS. Also picks the scheme the test steps will use.
# Success/failure is xcodebuild's own exit code (not a grep result).
cd "$(dirname "$0")/../swift_proofs"

xcodebuild -list > /tmp/xcodebuild_list.log 2>&1
if grep -q "WatchProofs-Package" /tmp/xcodebuild_list.log; then SCHEME="WatchProofs-Package"; else SCHEME="WatchProofs"; fi
echo "INFO: scheme $SCHEME (schemes: $(sed -n '/Schemes:/,$p' /tmp/xcodebuild_list.log | tail -n +2 | tr -s ' \n' ' '))"
echo "SCHEME=$SCHEME" >> "${GITHUB_ENV:-/dev/null}"

LOG=/tmp/xcodebuild_P0.log
xcodebuild build-for-testing -scheme "$SCHEME" -destination "id=$WATCH_UDID" > "$LOG" 2>&1
CODE=$?

grep -E "error:|\*\* (TEST )?BUILD|Supported platforms|Unable to find|Cannot|requires" "$LOG" | cut -c1-240 | head -n 40
if [ "$CODE" -ne 0 ]; then
  echo "--- last 40 lines of xcodebuild output ---"
  tail -n 40 "$LOG" | cut -c1-240
fi
exit "$CODE"
