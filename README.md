# Ur Fonts

A native macOS font manager for very large libraries. Browse, preview, activate,
and keep folders in sync without copying or moving a single font file.

Built for libraries with tens of thousands of fonts, the scale where most font
managers start to lag. Family-first rows, fixed-height CoreText previews,
in-place activation, and a delta scanner instead of full rescans.

**Status:** pre-release. Entering a few weeks of daily use before launch. No
notarized build yet.

---

## Why another font manager?

Because the hard parts are not the part that looks like the product.

The interface is the easy 20%. The rest is fontd semantics: per-file versus
per-face registration, confirming scope with `CTFontManagerGetScopeForURL`,
Fonts-folder exceptions, duplicate PostScript behavior, and cache differences
between macOS releases. It is scanning tens of thousands of files without
re-reading them,
canonicalizing paths (`/var` versus `/private/var`), and surviving cloud
providers that block on read. It is Adobe apps that ignore fontd notifications
and rebuild font menus on their own schedule.

None of that is discoverable from Apple's documentation alone. It takes spikes
and bug reports.

Large libraries are also rare. Most designers own hundreds of fonts, not tens of
thousands, so vendors optimize for the median: collections, tags, cloud sync,
team seats. Frame time at that scale does not sell subscriptions. A slow
Electron shell costs the vendor little; fixing scroll jank costs a lot and does
not move seats. Fonts make a bad demo too: the difference between 60 fps and
12 fps is obvious in use and invisible in a screenshot.

The macOS pieces that make it fast are old and unglamorous: view reuse, CoreText
line drawing, fixed row heights, FSEvents, signposts. Modern SwiftUI defaults —
`List`, self-sizing rows, a `Text` per row — are exactly the wrong tools at this
scale. Most apps pick the defaults, hit five thousand rows, and stop.

It is "easy sauce" only after accepting the constraints:

- in-place registration instead of copies
- family-first snapshots instead of live file access
- one CTFont per face, with derived point sizes
- fixed-height Canvas rows
- a canonical-path delta scanner
- and no per-app hacks

The code for that is a few thousand lines. Knowing which few thousand is the
expensive part.

---

## What works today

- Index static or watched folders. New installs seed the standard macOS font
  folders as watched. Files are read-only, never renamed or moved.
- Add individual font files or drop files and folders on the browser.
- Browse a family-first list or grid over tens of thousands of fonts, with a
  nested folder tree that mirrors indexed directories.
- Active sidebar item for fonts currently registered through Ur Fonts, with the
  same list, preview and activation controls.
- Warnings page for duplicate PostScript names and missing files, grouped by
  type with expandable disclosure sections and reveal/copy-path actions. Remove
  Missing Entries deletes the stale rows, never the files.
- Preview in the font itself, with editable text, presets, a size slider in the
  status bar, and text/background colors. Script-aware samples for CJK, Arabic,
  Hebrew and others once the coverage index is built from the filter popover.
  Unsupported characters show the font's `.notdef`; previews never substitute
  another font.
- Activate and deactivate families globally through CoreText, with a journal and
  launch reconciliation. Fonts inside system Fonts folders are left alone.
- Watch folders with FSEvents plus a five-minute sweep; only changed paths are
  re-read.
- Font sheet: every style rendered in the sample text, per-style activation and
  absolute file paths, variable-font axis sliders, OpenType feature list,
  sectioned glyph map with character, code point and SVG copy, file info.
  Duplicate file versions appear individually; when one PostScript name is
  active, the others are disabled and name the active path.
- Folder labels, watched/static folders, Ignore This Folder for any subtree
  (also managed in Settings → Ignored Folders, with FontBase cache detection),
  font rows disappear, files stay, reveal in Finder, safe removal.
- Collections, sorted alphabetically, with create/rename/delete, add/remove from a
  family, and Activate All / Deactivate All from the collection menu.
- Named preview samples (⌘E) with text, size and colors.
- Appearance setting in Settings (⌘,) for System, Light or Dark. The choice is
  remembered across launches and applies to every window, panel and menu.
- System fonts visible by default, hideable from Filters; Apple's leading `.`
  is stripped for display.
- Non-Latin family names keep the local name and add a Latin label in
  parentheses, and sort under that label.
- Export/Import Settings as versioned JSON: folders, collections, samples,
  preview settings and ignored folder paths, ready for a dotfiles repo.
- Google Fonts lives under Hosts in the sidebar and uses the same list/grid rows
  as the library, including inline previews from a lightweight subset before
  download. Click the activation square to download and activate a family; the
  family sheet lists every style with its own preview.
- Headless test modes that never take focus.

Not there yet: favorites, tags, Quick Look, document preflight, font-cache repair
for re-exported fonts, full GlyphsApp language parity, notarized release.

## Requirements

- macOS 15 or later
- Swift 6.2 or newer toolchain

## Build and run

```sh
swift build
swift test
./scripts/ci.sh            # tests, fixtures, headless scenarios, Release bundle
./scripts/test.sh          # ci.sh plus the network-dependent Google render
./scripts/build-icons.sh   # compiles Assets.car and UrFonts.icns from design/icon
./scripts/build-app.sh     # assembles build/Ur Fonts.app (ad-hoc signed)
open "build/Ur Fonts.app"
```

The app stores its library at
`~/Library/Application Support/Ur Fonts/library.sqlite3`.

### Where your data lives

- **Library database:** `~/Library/Application Support/Ur Fonts/library.sqlite3`.
  Folders, indexed files and faces, the activation journal, collections, saved
  samples and ignored folder paths.
- **App preferences:** `~/Library/Preferences/com.10k24.urfonts.plist`.
  Appearance (`urfonts.appearance`: `system`, `light` or `dark`), system-font
  visibility (`urfonts.showSystemFonts`) and file-name fallback
  (`urfonts.fallbackFileNames`). Inspect with
  `defaults read com.10k24.urfonts`.
- **Google Fonts downloads:** `~/Library/Application Support/Ur Fonts/GoogleFonts`
  (catalog cache, TTF files and licenses).
- **Google host previews:** `~/Library/Caches/Ur Fonts/HostPreviews`. Safe to
  delete; they are re-fetched.
- **Exported settings:** versioned JSON, written wherever you choose with
  Settings → Export. It is not read on launch.

Font files are never modified, moved or copied. The library only stores paths
and metadata.

A command line surface exists for indexing and diagnostics:

```sh
urfonts-cli index <folder> --db <path>
urfonts-cli search "inter" --db <path>
urfonts-cli folders --db <path>
urfonts-cli stats --db <path>
urfonts-cli index-coverage --db <path>
urfonts-cli google-catalog
urfonts-cli google-download Inter
```

## How it is built

- SwiftPM, Swift 6 strict concurrency, macOS 15.
- GRDB/SQLite for the library; an immutable in-memory snapshot for the UI.
- CoreText for names, previews and registration; a small SFNT reader for `fvar`
  axes and metrics.
- SwiftUI shell, fixed-height lazy rows, CoreText drawing inside `Canvas`.
- FSEvents for folder changes.

Architecture and data flow: `docs/ARCHITECTURE.md`. Setup, gate and code
conventions: `CONTRIBUTING.md`. Notable changes: `CHANGELOG.md`. Invariants and
the working backlog live in `AGENTS.md` and `OPEN_ISSUES.md`.

## Who

Built by [Shakeel Mohamed](https://shakeel.design) at
[10k24](https://10k24.com), a Los Angeles design studio built on creativity,
computing, and collaboration. Typography is the practice; performance is the
habit.

## License

Apache-2.0. See `LICENSE` and `NOTICE`.
