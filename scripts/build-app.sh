#!/usr/bin/env bash
# Assembles build/UrFonts.app around the release binary.
# Development bundle: ad-hoc signed, no Sparkle yet.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# Generated icon artifacts are not tracked. Rebuild them on a clean checkout.
if [ ! -f "$root/macos/Assets.car" ] || [ ! -f "$root/macos/UrFonts.icns" ]; then
    "$root/scripts/build-icons.sh"
fi

swift build -c release --product UrFonts
binary="$(swift build -c release --show-bin-path)/UrFonts"

app="$root/build/UrFonts.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$binary" "$app/Contents/MacOS/UrFonts"
cp "$root/macos/Info.plist" "$app/Contents/Info.plist"

# Local builds get a unique, human-readable build stamp. Release builds set
# URFONTS_BUILD_NUMBER explicitly and skip the development marker.
if [ -n "${URFONTS_BUILD_NUMBER:-}" ]; then
    build_number="$URFONTS_BUILD_NUMBER"
    stamp=""
else
    build_number="$(date -u +%Y%m%d%H%M%S)"
    stamp="Development build · $(date -u +"%Y-%m-%d %H:%M UTC")"
fi
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
if [ -n "$stamp" ]; then
    /usr/libexec/PlistBuddy \
        -c "Add :UrFontsBuildStamp string $stamp" "$app/Contents/Info.plist"
else
    /usr/libexec/PlistBuddy \
        -c "Delete :UrFontsBuildStamp" "$app/Contents/Info.plist" 2>/dev/null || true
fi

for resource in Assets.car UrFonts.icns; do
    if [ -f "$root/macos/$resource" ]; then
        cp "$root/macos/$resource" "$app/Contents/Resources/$resource"
    fi
done

codesign --force --sign - "$app" >/dev/null 2>&1 || true

echo "$app"
