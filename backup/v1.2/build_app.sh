#!/usr/bin/env bash
set -euo pipefail

APP_NAME="JungleRunner"
VER="${1:-1.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK="/home/alina/sdk/iPhoneOS16.5.sdk"
CLANG="/usr/bin/clang-19"
LLD="/usr/bin/ld64.lld-19"
BUILD="/tmp/jr_build_$$"
OUTPUT="${SCRIPT_DIR}/JungleRunner_v${VER}.ipa"

echo "╔══════════════════════════════════════════╗"
echo "║    Jungle Runner — Build v${VER}        ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Fix SDK stdint.h
if [ -f "${SDK}/usr/include/stdint.h" ]; then
    mv "${SDK}/usr/include/stdint.h" "${SDK}/usr/include/stdint.h.bak" 2>/dev/null || true
fi

rm -rf "$BUILD"
mkdir -p "$BUILD/objects"

CFLAGS="-target arm64-apple-ios14.0 \
  -isysroot $SDK \
  -isystem \"$SDK/usr/include\" \
  -iframework \"$SDK/System/Library/Frameworks\" \
  -fobjc-arc -fno-modules -fvisibility=hidden \
  -x objective-c -std=c11 -O2 \
  -I\"$SCRIPT_DIR\" \
  -c"

SOURCES=("main.m" "AppDelegate.m")

echo "━━━ Compiling ━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for f in "${SOURCES[@]}"; do
    OBJ="${f%.*}.o"
    echo "  ▶ $f ..."
    $CLANG $CFLAGS "$SCRIPT_DIR/$f" -o "$BUILD/objects/$OBJ" || {
        echo "❌ FAIL: $f"
        exit 1
    }
done
echo "  ✅ All compiled"
echo ""

echo "━━━ Linking ${APP_NAME} ━━━━━━━━━━━━━━━━"
$LLD -demangle \
  -arch arm64 \
  -platform_version ios 14.0 16.5 \
  -syslibroot "$SDK" \
  -lobjc -lc++ -lc -lz \
  -framework Foundation \
  -framework UIKit \
  -framework CoreGraphics \
  -framework WebKit \
  -e _main \
  -o "$BUILD/$APP_NAME" \
  "$BUILD/objects/"*.o || { echo "❌ Link failed"; exit 1; }
echo "  ✅ Linked"
echo ""

echo "━━━ Creating .app ━━━━━━━━━━━━━━━━━━━━"
APP_DIR="$BUILD/${APP_NAME}.app"
mkdir -p "$APP_DIR"
cp "$BUILD/$APP_NAME" "$APP_DIR/$APP_NAME"
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Info.plist"
echo -n "APPL????" > "$APP_DIR/PkgInfo"

# Copy all Assets (HTML, GLB, JS, textures)
cp -R "$SCRIPT_DIR/Assets/"* "$APP_DIR/" 2>/dev/null || true
echo "  ✅ ${APP_NAME}.app with assets"
echo ""

echo "━━━ Signing ━━━━━━━━━━━━━━━━━━━━━━━━━━"
if command -v ldid &>/dev/null; then
    ldid -S "$APP_DIR/$APP_NAME" 2>/dev/null && echo "  🔐 Signed" || echo "  ⚠️ Sign skipped"
else
    echo "  ⚠️ ldid not found"
fi
echo ""

echo "━━━ Packaging IPA ━━━━━━━━━━━━━━━━━━━━"
IPA_DIR="$BUILD/ipa"
rm -rf "$IPA_DIR"
mkdir -p "$IPA_DIR/Payload"
cp -R "$APP_DIR" "$IPA_DIR/Payload/${APP_NAME}.app"
cd "$IPA_DIR"

# Use python for zip (zip cmd may not be available)
python3 -c "
import zipfile, os
with zipfile.ZipFile('$OUTPUT', 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk('Payload'):
        for f in files:
            fp = os.path.join(root, f)
            zf.write(fp, fp)
"
cd "$SCRIPT_DIR"
echo "  ✅ $OUTPUT"
echo ""

IPA_SIZE=$(python3 -c "import os; print(f'{os.path.getsize(\"$OUTPUT\")/1024/1024:.1f}')")
echo "╔══════════════════════════════════════════╗"
echo "║  ✅ BUILD COMPLETE                       ║"
echo "╠══════════════════════════════════════════╣"
echo "║  IPA: JungleRunner_v${VER}.ipa"
echo "║  Size: ${IPA_SIZE} MB"
echo "╚══════════════════════════════════════════╝"

file "$APP_DIR/$APP_NAME"
