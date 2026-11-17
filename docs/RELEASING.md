# Releasing

Ur Fonts is distributed directly as a notarized app, outside the Mac App Store.
This checklist covers a signed release. Development builds only need
`scripts/build-app.sh`.

## Before tagging

1. Run `./scripts/ci.sh`. A red gate blocks the release.
2. Run `./scripts/test.sh` once with network access for the Google render.
3. Run `./scripts/bench.sh` on the real library and update `BENCH.md` if the
   numbers moved.
4. Bump `CFBundleShortVersionString` and increment `CFBundleVersion` in
   `macos/Info.plist`.
5. Move `CHANGELOG.md` entries from `Unreleased` to a version heading with the
   release date.
6. Confirm `LICENSE` and `NOTICE` are current.

## Versioning

- Tags are `vMAJOR.MINOR.PATCH`.
- `CFBundleShortVersionString` matches the tag without the `v`.
- `CFBundleVersion` increases for every uploaded build.
- The settings JSON schema version in `LibraryConfiguration` is independent of
  the app version.

## Signed DMG

Create a Developer ID Application certificate in the Apple Developer account and
store a notarytool profile in the login keychain:

```sh
xcrun notarytool store-credentials "urfonts-notary" \
    --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
```

Build, sign, notarize and staple:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="urfonts-notary" \
./scripts/make-dmg.sh
```

The script builds the bundle, re-signs it with the hardened runtime, creates
`build/URFonts-<version>.dmg`, verifies the image, submits it to the notary
service, and staples the ticket. Development runs without those variables stay
ad-hoc signed and are not suitable for distribution.

## Verify

```sh
spctl --assess --type execute --verbose "build/URFonts.app"
xcrun stapler validate "build/URFonts-<version>.dmg"
hdiutil attach "build/URFonts-<version>.dmg" -nobrowse
```

Open the mounted app on a clean macOS account, activate one local font and one
Google Fonts download, and confirm the library loads from a fresh database.

## Publish

1. Tag the release and push the tag.
2. Attach the DMG to the GitHub release.
3. Publish the changelog entry.
4. Update the Homebrew cask when one exists.

## Not ready

- Sparkle is not integrated. The updater framework, appcast and signing keys are
  release work; do not advertise automatic updates until they exist.
- There is no automated release workflow yet. The signed-DMG steps above are
  manual and must run on a machine with the Developer ID identity.
