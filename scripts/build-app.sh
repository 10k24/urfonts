#!/usr/bin/env bash
# Assembles build/Ur Fonts.app around the release binary.
# Development bundle: no icon, no Sparkle yet, ad-hoc signed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build -c release --product UrFonts
binary="$(swift build -c release --show-bin-path)/UrFonts"

app="$root/build/Ur Fonts.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$binary" "$app/Contents/MacOS/UrFonts"
cp "$root/macos/Info.plist" "$app/Contents/Info.plist"

for resource in Assets.car UrFonts.icns; do
    if [ -f "$root/macos/$resource" ]; then
        cp "$root/macos/$resource" "$app/Contents/Resources/$resource"
    fi
done

codesign --force --sign - "$app" >/dev/null 2>&1 || true

echo "$app"
