# Releasing

Ur Fonts is distributed directly as a notarized app, outside the Mac App Store.
This checklist covers a signed release. Development builds only need
`scripts/build-app.sh`.

## Before tagging

1. Run `./scripts/ci.sh`. A red gate blocks the release.
2. Run `./scripts/test.sh` once with network access for the Google render.
3. Run `./scripts/bench.sh` on the real library and update `BENCH.md` if the
   numbers moved.
4. Bump `CFBundleShortVersionString` in `macos/Info.plist`. Set
   `URFONTS_BUILD_NUMBER` when building the release; local builds get a
   timestamp automatically.
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

Confirm `build/UrFonts.app/Contents/Resources/Assets.car` exists before shipping.
`make-dmg.sh` refuses to package without it. CI and development machines may
fall back to the legacy `.icns`; that is not a release build.

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
`build/UrFonts-<version>.dmg`, verifies the image, submits it to the notary
service, and staples the ticket. Development runs without those variables stay
ad-hoc signed and are not suitable for distribution.

## Verify

```sh
spctl --assess --type execute --verbose "build/UrFonts.app"
xcrun stapler validate "build/UrFonts-<version>.dmg"
hdiutil attach "build/UrFonts-<version>.dmg" -nobrowse
```

Open the mounted app on a clean macOS account, activate one local font and one
Google Fonts download, and confirm the library loads from a fresh database.

## Publish

1. Tag the release and push the tag.
2. Attach the DMG to the GitHub release.
3. Publish the changelog entry.
4. Update the Homebrew cask when one exists.

## Not ready

- A Developer ID Application certificate and an Apple Developer Program
  membership are required before this checklist can run.
- Sparkle is not integrated. The updater framework, appcast and EdDSA keys are
  deferred until there is a distribution feed and key management.
- There is no automated release workflow yet. The signed-DMG steps above are
  manual and must run on a machine with the Developer ID identity.
