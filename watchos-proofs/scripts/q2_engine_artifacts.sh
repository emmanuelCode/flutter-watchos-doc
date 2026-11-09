#!/usr/bin/env bash
# Q2 — gather the OFFICIAL engine pieces we need: the desktop embedder library for this Flutter version,
# its icudtl.dat, the iOS engine (for the gap analysis), and a flutter_assets bundle of our probe app.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
rl() { mkdir -p /tmp/watch_proofs; echo "$*" >> /tmp/watch_proofs/results.log; echo "$*"; }

FLUTTER_ROOT=$(cd "$(dirname "$(command -v flutter)")/.." && pwd)
HASH=$(cat "$FLUTTER_ROOT/bin/internal/engine.version")
BASE="https://storage.googleapis.com/flutter_infra_release/flutter/$HASH"
rm -rf /tmp/engine/macos /tmp/engine/assets; mkdir -p /tmp/engine/macos /tmp/engine/assets /tmp/engine/dl

flutter precache --ios --macos >/dev/null 2>&1 || echo "WARN: flutter precache failed"

PICK=""
for arch in darwin-arm64 darwin-x64; do
  code=$(curl -s -o /dev/null -w "%{http_code}" -I "$BASE/$arch/FlutterEmbedder.framework.zip")
  rl "Q2: HEAD $arch/FlutterEmbedder.framework.zip -> HTTP $code"
  [ "$code" = "200" ] && [ -z "$PICK" ] && PICK="$arch"
done
if [ -z "$PICK" ]; then
  echo "FAIL: no FlutterEmbedder.framework published for this engine version. Engine artifacts in the SDK cache:"
  ls "$FLUTTER_ROOT/bin/cache/artifacts/engine/" 2>/dev/null
  exit 1
fi
curl -sfL -o /tmp/engine/dl/embedder.zip "$BASE/$PICK/FlutterEmbedder.framework.zip" || { echo "FAIL: download failed"; exit 1; }
unzip -q -o /tmp/engine/dl/embedder.zip -d /tmp/engine/dl/embedder
BIN=$(find /tmp/engine/dl/embedder -type f -name FlutterEmbedder ! -path '*/Headers/*' | head -n 1)
[ -n "$BIN" ] || { echo "FAIL: no FlutterEmbedder binary inside the zip:"; find /tmp/engine/dl/embedder | head -n 30; exit 1; }
ARCHS=$(lipo -archs "$BIN")
rl "Q2: using $PICK embedder library, $(( $(stat -f %z "$BIN") / 1024 / 1024 )) MB, archs: $ARCHS"
case " $ARCHS " in
  *" arm64 "*) lipo "$BIN" -thin arm64 -output /tmp/engine/macos/FlutterEmbedder 2>/dev/null || cp "$BIN" /tmp/engine/macos/FlutterEmbedder ;;
  *) echo "FAIL: the embedder library has no arm64 slice ($ARCHS), so it cannot run in an arm64 watch simulator"; exit 1 ;;
esac

ICU=$(find /tmp/engine/dl/embedder "$FLUTTER_ROOT/bin/cache/artifacts/engine" -name icudtl.dat 2>/dev/null | head -n 1)
[ -n "$ICU" ] || { echo "FAIL: icudtl.dat not found"; exit 1; }
cp "$ICU" /tmp/engine/icudtl.dat
rl "Q2: icudtl.dat found ($(( $(stat -f %z /tmp/engine/icudtl.dat) / 1024 )) KB)"

IOSBIN=$(find "$FLUTTER_ROOT/bin/cache/artifacts/engine" -path '*Flutter.xcframework/ios-*simulator*/Flutter.framework/Flutter' -type f | head -n 1)
if [ -n "$IOSBIN" ]; then cp "$IOSBIN" /tmp/engine/ios_Flutter; rl "Q2: official iOS Simulator engine found ($(( $(stat -f %z "$IOSBIN") / 1024 / 1024 )) MB) for the gap analysis"
else rl "Q2: official iOS Simulator engine NOT found in the SDK cache"; fi

echo "== build the probe app bundle with the stock Flutter SDK =="
cd "$ROOT/engine_probe/app" && flutter pub get >/dev/null && flutter build bundle --debug 2>&1 | tail -n 5
SRCASSETS=$(find "$ROOT/engine_probe/app/build" -type d -name flutter_assets | head -n 1)
[ -n "$SRCASSETS" ] && [ -f "$SRCASSETS/kernel_blob.bin" ] || { echo "FAIL: no kernel_blob.bin produced"; find "$ROOT/engine_probe/app/build" -maxdepth 3 | head; exit 1; }
cp -R "$SRCASSETS" /tmp/engine/assets/flutter_assets
rl "Q2: probe app bundle ready (kernel_blob.bin $(( $(stat -f %z /tmp/engine/assets/flutter_assets/kernel_blob.bin) / 1024 )) KB)"
echo "PASS: official engine pieces gathered"
