# Ur Fonts

A native macOS font manager for very large libraries. Browse, preview and
activate fonts in place, and keep folders in sync without copying or modifying a
font file.

Built for libraries with tens of thousands of fonts: family-first rows,
fixed-height CoreText previews, in-place activation and a delta scanner.

[![CI](https://github.com/10k24/urfonts/actions/workflows/ci.yml/badge.svg)](https://github.com/10k24/urfonts/actions/workflows/ci.yml)

**Status:** pre-release. **Source only:** no `.app` or DMG binaries are
published. Build from source with Xcode 26 or newer.

## What works

- Index watched or static folders. New installs seed the standard macOS font
  folders. Files are read-only, never renamed or moved.
- Add individual font files or drop files and folders on the browser.
- Family-first list and grid over tens of thousands of fonts, with search,
  filters, sorting and a nested folder tree.
- Preview in the font itself: sample text, presets, size and colors. Unsupported
  characters show `.notdef`; previews never substitute another font.
- Global activation through CoreText, with a journal and launch reconciliation.
  Installed system fonts stay locked; duplicate PostScript names are blocked.
- Font sheet with every style, per-style activation, absolute paths, variable
  axes, OpenType feature tags, glyph map and file info. Family counts match the
  styles the checkbox activates; duplicate files are marked as alternates.
- Collections, sorted alphabetically, with bulk activation. Saved preview
  samples with text, size and colors.
- Warnings for duplicate PostScript names and missing files. Cleanup removes
  library rows, never files.
- Google Fonts under Hosts, with inline previews, per-style download and
  activation, and saved licenses.
- Settings for appearance, filename fallback and ignored folders, plus versioned
  settings export/import. In-app help, first-run guidance and an About panel.
- Headless test modes that never take focus.

Not there yet: favorites, tags, Quick Look, document preflight, font-cache repair
for re-exported fonts, full GlyphsApp language parity, signed/notarized builds.

## Requirements

- macOS 15 or later
- Xcode 26 or newer, or a Swift 6.2+ toolchain

## Build and run

```sh
git clone https://github.com/10k24/urfonts.git
cd urfonts
./scripts/build-app.sh
open "build/UrFonts.app"
```

No prebuilt apps are published. Build locally from source.

```sh
swift test
./scripts/ci.sh            # deterministic gate
./scripts/test.sh          # ci.sh plus the network Google render
```

## Where your data lives

- **Library database:** `~/Library/Application Support/Ur Fonts/library.sqlite3`.
  Folders, files, faces, activation journal, collections, samples and ignored
  folder paths.
- **App preferences:** `~/Library/Preferences/com.10k24.urfonts.plist`.
  Appearance, system-font visibility, file-name fallback, first-run state and
  the selected saved sample. Inspect with `defaults read com.10k24.urfonts`.
- **Google Fonts:** `~/Library/Application Support/Ur Fonts/GoogleFonts` for
  downloads, catalog cache and licenses.
- **Google host previews:** `~/Library/Caches/Ur Fonts/HostPreviews`. Safe to
  delete.
- **Exported settings:** versioned JSON, written wherever you choose.

Font files are never modified, moved or copied. The library stores paths and
metadata only.

## Command line

```sh
urfonts-cli index <folder> --db <path>
urfonts-cli search "inter" --db <path>
urfonts-cli stats --db <path>
urfonts-cli folders --db <path>
urfonts-cli index-coverage --db <path>
urfonts-cli google-catalog
urfonts-cli google-download Inter
```

## Docs

- `docs/ARCHITECTURE.md` — modules and data flow
- `CONTRIBUTING.md` — setup, gate, style and support
- `CHANGELOG.md` — notable changes
- `BENCH.md` — measured performance
- `AGENTS.md` and `OPEN_ISSUES.md` — invariants and backlog

## Who

Built by [Shakeel Mohamed](https://shakeel.design) at
[10k24](https://10k24.com), a Los Angeles design studio.

## License

Apache-2.0. See `LICENSE` and `NOTICE`.
