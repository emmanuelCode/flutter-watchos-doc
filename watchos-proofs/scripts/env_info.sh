#!/usr/bin/env bash
# Usage: env_info.sh swift|flutter — records tool versions for the result sheet.
R=/tmp/proof_results.txt
e() { echo "ENV|$*" >> "$R"; }
e "runner image: ${ImageOS:-?} ${ImageVersion:-?} ($(uname -m))"
e "macOS $(sw_vers -productVersion 2>&1)"
case "${1:-}" in
  swift)
    e "$(xcodebuild -version 2>&1 | tr '\n' ' ')"
    e "watchsimulator SDK $(xcrun --sdk watchsimulator --show-sdk-version 2>&1)"
    e "$(dart --version 2>&1)" ;;
  flutter)
    e "$(flutter --version 2>&1 | head -n 1)"
    e "$(dart --version 2>&1)" ;;
esac
