#!/usr/bin/env bash
# Builds a distributable DMG around the app bundle.
#
# Development builds are ad-hoc signed. Set SIGN_IDENTITY to a Developer ID
# Application identity for a signed build, and NOTARY_PROFILE to a notarytool
# keychain profile to notarize and staple the DMG.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    macos/Info.plist)"
if [ -z "$version" ]; then
    echo "missing CFBundleShortVersionString in macos/Info.plist" >&2
    exit 1
fi

./scripts/build-app.sh >/dev/null
app="build/URFonts.app"
if [ ! -d "$app" ]; then
    echo "missing $app" >&2
    exit 1
fi

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$app"
fi

staging="$(mktemp -d "${TMPDIR:-/tmp}/urfonts-dmg.XXXXXX")"
ditto "$app" "$staging/URFonts.app"
ln -s /Applications "$staging/Applications"

dmg="build/URFonts-$version.dmg"
hdiutil create -volname "URFonts" -srcfolder "$staging" \
    -ov -format UDZO "$dmg" >/dev/null
hdiutil verify "$dmg" >/dev/null

if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$dmg" \
        --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg"
fi

echo "$dmg"
