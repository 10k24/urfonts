# Contributing

Ur Fonts is a native macOS font manager for large libraries. Contributions are
welcome, especially around font parsing, CoreText behavior, performance and
accessibility. The project is pre-release, so the schema and internal APIs can
still change.

Read `AGENTS.md` before changing behavior. It records the invariants the design
depends on; `docs/ARCHITECTURE.md` describes how the modules fit together.

## Requirements

- macOS 15 or later.
- Xcode 26 or newer, or a Swift 6.2+ toolchain.
- No Apple Developer account is needed for development builds. Release signing
  and notarization are separate.

## Build and run

```sh
swift build
swift test
./scripts/ci.sh            # deterministic gate
./scripts/test.sh          # ci.sh plus the network Google render
./scripts/bench.sh         # Release performance sample
./scripts/build-app.sh     # build/Ur Fonts.app, ad-hoc signed
open "build/Ur Fonts.app"
```

A bare SwiftPM binary launches as a background-only process. Use the app bundle
when checking menus, focus, activation or window behavior.

The library database and preferences live outside the repo. `README.md` lists
the exact paths.

## What CI runs

CI runs `scripts/ci.sh` on a GitHub-hosted macOS runner. That script covers:

- `swift test`
- a Release build
- a 23,000-font generated fixture, a cold index under 30 s, CLI stats and search
- a search p99 under 16 ms
- headless scenarios that prove the process never takes focus
- app bundle assembly

The runner image default Xcode is older than the package tools version, so the
workflow selects the latest stable Xcode first.

`act` cannot emulate macOS runners. Do not use it to judge a workflow change.
Validate with `actionlint`, then run `./scripts/ci.sh` locally. `scripts/test.sh`
also renders the Google Fonts host sheet, which needs network access, so CI
leaves it out.

## Tests

- Core behavior belongs in `Tests/UrFontsCoreTests`, colocated by module.
- Scanner and catalog tests use generated fixtures. Do not depend on fonts in
  the repository; there are none.
- Activation has a fake registrar for state-machine tests and an opt-in real
  test against one known font.
- Headless scenarios are the app-level check. They must fail when the production
  command seam is broken, and must assert that the process is not active.
- Bug fixes should come with a failing test first when the behavior is testable
  without a window.

## Code style

- Four spaces, no trailing whitespace, 100-column soft limit.
- `camelCase` functions and properties, `PascalCase` types, lower-case file names.
- Prefer `let`, early returns and explicit optionals. No force unwrap on paths
  that can fail.
- Minimal `try/catch`. Let errors reach one boundary that logs and shows one safe
  message. Raw database errors never reach the UI.
- Comments explain why and what the interface promises, not what the line does.
- American spelling in code and docs.
- No new dependency without a reason the standard library or an existing
  dependency cannot do the job. GRDB is the only current dependency.

## Architecture rules

- Feature logic goes in a deep module in `UrFontsCore`. The app target is UI and
  orchestration.
- `AppModel` owns state; views render and send commands through the command seam.
- Anything that walks the library or reads a font file runs off the main actor.
- Activation has one writer. Preview layout has one owner. Search filtering has
  one owner.
- Views never branch on font format, activation scope or file state if a value
  type can carry that decision.

## Font files and user data

- Never modify, rename, move or copy a font file.
- Never commit font files, trial libraries, generated fixtures, build artifacts
  or signing secrets.
- Never write into a user's font folder.
- Do not add telemetry. Network access is only for Google Fonts downloads and,
  later, updates.

## Pull requests

- Keep changes focused. One behavior per pull request when possible.
- Explain the user-visible effect and why the approach is the simplest one that
  works.
- Include tests for new core behavior and a headless check for new app wiring.
- Update the docs touched by the change: `README.md` for user-facing behavior,
  `docs/ARCHITECTURE.md` for module shape, `CHANGELOG.md` for notable changes.
- Match the surrounding style. Do not reformat unrelated code.
- By contributing, you agree that your contribution is licensed under
  Apache-2.0, the license in `LICENSE`.

## Versioning

- Versions follow Semantic Versioning. Before 1.0, minor releases may include
  breaking changes; patch releases stay compatible.
- Tags are `vMAJOR.MINOR.PATCH`. `CFBundleShortVersionString` matches the tag and
  `CFBundleVersion` increments for every build.
- `CHANGELOG.md` keeps changes under `Unreleased` until a tag, then moves them to
  a version heading with the release date.
- The settings export has its own schema version in `LibraryConfiguration`.
  Bump it when the JSON shape changes, accept older files, and reject newer ones
  with a readable message.
- Database migrations are append-only. Never edit a migration that has shipped.

## Support policy

- Supported platform: macOS 15 and later.
- The project is pre-release and maintained on a best-effort basis. There is no
  guaranteed response time or support contract.
- Report bugs and feature requests through GitHub issues. Include macOS version,
  app version, steps to reproduce and the relevant log excerpt or headless
  artifact path.
- Do not upload commercial or licensed font files. A font name and table dump are
  usually enough.
- Windows and Linux are out of scope for now.

## Reporting a security issue

Do not open a public issue for a vulnerability that could expose user data or
execute code. Use the repository's private vulnerability reporting, then disclose
publicly after a fix is available.
