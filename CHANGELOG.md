# Changelog

All notable changes are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Before 1.0, minor
versions may change behavior.

## [Unreleased]

### Added

- Folder indexing with static and watched roots, FSEvents deltas, a five-minute
  sweep and a nested folder tree built from indexed paths.
- Read-only font parsing for `head`, `hhea`, `OS/2`, `name` and `fvar`, including
  TTC/OTC collections and variable font axes.
- Family-first browser with list and grid layouts, fixed-height CoreText rows,
  search by family, style and PostScript name, and kind, italic, bold and script
  filters.
- Preview text, presets and a 12–108 pt size slider in the status bar, with text
  and background colors.
- Global activation through CoreText with a journal, launch reconciliation,
  duplicate PostScript detection and installed-font protection.
- Font sheet with per-style activation, variable axes, glyph map, OpenType
  feature tags, file paths and info.
- Collections with create, rename, delete and bulk activation, always sorted
  alphabetically.
- Saved preview samples with text, size and colors.
- In-app help window (⌘?) covering library behavior, activation, previews,
  warnings, Google Fonts and known limits.
- About panel with the 10k24 Studio credit and a repository link. Local builds
  show a development timestamp and a timestamp build number.
- First-run welcome sheet explaining the read-only model, adding a folder and
  global activation.
- Warnings for duplicate PostScript names and missing files.
- Google Fonts host with inline subset previews, per-style downloads, license
  labels and the same activation controls as local fonts.
- Versioned settings export and import for folders, collections, samples,
  preview settings and ignored folder paths.
- Settings for appearance (System, Light, Dark) and ignored folders, both
  persisted across launches.
- Headless scenarios that render real views offscreen and prove the process never
  takes focus.
- New UR mark app icon with a dark background, compiled into `Assets.car` and the
  legacy `.icns`.
- CI gate covering tests, a Release build, fixtures, CLI round trip, headless
  scenarios and app bundle assembly.

### Changed

- The development bundle is now `UrFonts.app`; the executable remains `UrFonts`.
- Toolbar reload is scope-aware: folder and subfolder selections scan only that
  scope, and unchanged scans skip the full snapshot rebuild.

### Fixed

- Family checkboxes activate every unique style. Duplicate OTF/TTF and WEB files
  collapse into one style with a preferred file; alternates remain visible but
  disabled. Placeholder name tables such as `false` no longer create fake
  families or block family activation.

- Online-only cloud files are skipped without creating warning rows; previously
  indexed files that become online-only remain visible as unavailable.
- Network, timeout and offline failures show a retryable message instead of a
  database or file-system error.
- A file owned by two overlapping roots is moved to one folder rather than
  failing the scan.
- Preview rows no longer reload a font when only the point size changes.
