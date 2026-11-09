#!/usr/bin/env bash
# Usage: syntax_check_one.sh <engine-src-root> <file>  — clang -fsyntax-only for the watchOS Simulator.
SRC="$1"; f="$2"
SDK=$(xcrun --sdk watchsimulator --show-sdk-path)
case "$f" in *.mm) LANG_FLAGS="-x objective-c++ -fobjc-arc -std=c++20" ;; *) LANG_FLAGS="-std=c++20" ;; esac
out=$(xcrun --sdk watchsimulator clang++ -fsyntax-only $LANG_FLAGS -target arm64-apple-watchos10.0-simulator -isysroot "$SDK" -I "$SRC/engine/src" "$f" 2>&1)
if [ $? -eq 0 ]; then echo "OK|$f|"; else echo "FAIL|$f|$(echo "$out" | grep -m1 'error' | cut -c1-200)"; fi
