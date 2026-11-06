#!/usr/bin/env bash
# Compiles the app icon into Assets.car (macOS 26+) and UrFonts.icns (15-25).
# Sources are authored by hand; see design/icon/README.md.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

icon="design/icon/UrFonts.icon"
legacy="design/icon/legacy/icon-1024.png"
out="macos"

if [ ! -d "$icon" ]; then
    echo "missing $icon" >&2
    echo "Author it in Icon Composer. See design/icon/README.md." >&2
    exit 1
fi

mkdir -p "$out" build

echo "compiling $icon"
xcrun actool "$icon" \
    --compile "$out" \
    --platform macosx \
    --minimum-deployment-target 15.0 \
    --app-icon UrFonts \
    --output-partial-info-plist "build/icon-info.plist" \
    --output-format human-readable-text \
    --notices \
    --warnings

if [ -f "$legacy" ]; then
    echo "building UrFonts.icns from $legacy"
    iconset="build/UrFonts.iconset"
    mkdir -p "$iconset"

    sips -z 16 16 "$legacy" --out "$iconset/icon_16x16.png" >/dev/null
    sips -z 32 32 "$legacy" --out "$iconset/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$legacy" --out "$iconset/icon_32x32.png" >/dev/null
    sips -z 64 64 "$legacy" --out "$iconset/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$legacy" --out "$iconset/icon_128x128.png" >/dev/null
    sips -z 256 256 "$legacy" --out "$iconset/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$legacy" --out "$iconset/icon_256x256.png" >/dev/null
    sips -z 512 512 "$legacy" --out "$iconset/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$legacy" --out "$iconset/icon_512x512.png" >/dev/null
    cp "$legacy" "$iconset/icon_512x512@2x.png"

    iconutil -c icns "$iconset" -o "$out/UrFonts.icns"
else
    echo "warning: no $legacy; macOS 15-25 will have no icon" >&2
fi

echo
echo "wrote:"
for file in "$out/Assets.car" "$out/UrFonts.icns"; do
    [ -f "$file" ] && echo "  $file"
done
