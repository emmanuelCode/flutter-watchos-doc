#!/usr/bin/env bash
# Usage: syntax_check_one.sh <engine-src-root> <file> [watchsimulator|watchos]
SRC="$1"; f="$2"; TARGET_SDK="${3:-watchsimulator}"
SDK=$(xcrun --sdk "$TARGET_SDK" --show-sdk-path)
if [ "$TARGET_SDK" = "watchos" ]; then
  TARGET="arm64-apple-watchos10.0"
else
  TARGET="arm64-apple-watchos10.0-simulator"
fi
case "$f" in *.mm) LANG_FLAGS="-x objective-c++ -fobjc-arc -std=c++20" ;; *) LANG_FLAGS="-std=c++20" ;; esac
out=$(xcrun --sdk "$TARGET_SDK" clang++ -fsyntax-only $LANG_FLAGS -target "$TARGET" -isysroot "$SDK" -I "$SRC/engine/src" "$f" 2>&1)
if [ $? -eq 0 ]; then echo "OK|$f|"; else echo "FAIL|$f|$(echo "$out" | grep -m1 'error' | cut -c1-200)"; fi
