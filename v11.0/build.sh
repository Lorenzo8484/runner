#!/usr/bin/env bash
set -euo pipefail
APP_NAME="JungleRunner" VER="${1:-8.0}"
SDIR="$(cd "$(dirname "$0")" && pwd)"
SDK="/home/alina/sdk/iPhoneOS16.5.sdk"
CLANG="/usr/bin/clang-19" LLD="/usr/bin/ld64.lld-19"
BUILD="/tmp/jr8_build_$$" OUT="$SDIR/JungleRunner_v${VER}.ipa"

echo "╔══════════════════════════════════════════╗"
echo "║  Jungle Runner v${VER} — SceneKit Native ║"
echo "╚══════════════════════════════════════════╝"

[ -f "${SDK}/usr/include/stdint.h" ] && mv "${SDK}/usr/include/stdint.h" "${SDK}/usr/include/stdint.h.bak" 2>/dev/null || true
rm -rf "$BUILD"; mkdir -p "$BUILD/obj"

CFLAGS="-target arm64-apple-ios14.0 -isysroot $SDK -isystem '$SDK/usr/include' -iframework '$SDK/System/Library/Frameworks' -fobjc-arc -fno-modules -fvisibility=hidden -x objective-c++ -std=c++17 -O2 -Wno-deprecated-declarations -I'$SDIR' -DVERSION_STR=v${VER} -c"
SOURCES="main.m AppDelegate.m AudioEngine.m ParticleSystem.m GLTFLoader.mm GameViewController.m"

for f in $SOURCES; do
    echo "  ▶ $f"
    $CLANG $CFLAGS "$SDIR/$f" -o "$BUILD/obj/${f%.*}.o" || { echo "❌ $f"; exit 1; }
done
echo "  ✅ All compiled"

echo "  ▶ Linking..."
$LLD -demangle -arch arm64 -platform_version ios 14.0 16.5 -syslibroot "$SDK" -lobjc -lc++ -lc -lz -framework Foundation -framework UIKit -framework SceneKit -framework SpriteKit -framework Metal -framework AVFoundation -framework QuartzCore -framework CoreGraphics -e _main -o "$BUILD/$APP_NAME" "$BUILD/obj/"*.o || { echo "❌ Link"; exit 1; }
echo "  ✅ Linked"

ADIR="$BUILD/${APP_NAME}.app"; mkdir -p "$ADIR"
cp "$BUILD/$APP_NAME" "$ADIR/"; cp "$SDIR/Info.plist" "$ADIR/"
echo -n "APPL????" > "$ADIR/PkgInfo"
ldid -S "$ADIR/$APP_NAME" 2>/dev/null && echo "  🔐 Signed" || echo "  ⚠️ Unsigned"

[ -d "$SDIR/Assets" ] && cp -R "$SDIR/Assets" "$ADIR/" && echo "  📦 Assets bundled"

IDIR="$BUILD/ipa"; rm -rf "$IDIR"; mkdir -p "$IDIR/Payload"
cp -R "$ADIR" "$IDIR/Payload/"
cd "$IDIR"
python3 -c "import zipfile,os;zf=zipfile.ZipFile('$OUT','w',zipfile.ZIP_DEFLATED);[zf.write(os.path.join(r,f),os.path.join(r,f))for r,_,fs in os.walk('Payload')for f in fs]"
cd "$SDIR"
echo "  ✅ $OUT ($(python3 -c "import os;print(f'{os.path.getsize(\"$OUT\")/1024:.0f}')") KB)"
file "$ADIR/$APP_NAME"
