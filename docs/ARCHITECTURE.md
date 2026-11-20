# Architecture

Ur Fonts is a SwiftPM package with three products: a UI-free core library, a
SwiftUI app, and a command line surface. This document describes how the pieces
fit together. The invariants that must not change without a measurement or a
deliberate decision live in `AGENTS.md`; performance budgets live there too.

## Constraints

- Font files are opened read-only. The app never renames, moves, copies or
  rewrites them.
- Activation is in place through CoreText, not by linking into a Fonts folder.
- The browser is family-first: many files collapse into a few thousand rows.
- The snapshot is the source of truth for views. No view walks the library or
  opens a font inside its body.
- macOS 15 or later, unsandboxed, direct distribution. No Mac App Store, no
  Apple Events, no plug-ins.

## Targets

| Target | Responsibility |
|---|---|
| `UrFontsCore` | Parsing, scanning, watching, catalog, activation, coverage, Google Fonts, preview drawing, configuration. No SwiftUI, no AppKit views. |
| `UrFonts` | SwiftUI app, `AppModel`, commands, settings, sidebar, browser, font page, hosts, headless harness. Main-actor by default. |
| `urfonts-cli` | Indexing, search, folder and activation diagnostics without launching the UI. |
| `UrFontsFixtures` / `FixtureGen` | Synthetic font fixtures for tests and manual scale checks. Never linked into the app. |

Core directories:

- `FontKit` reads `head`, `hhea`, `OS/2`, `name`, `fvar`, `cmap` coverage and
  GSUB/GPOS feature tags. `STAT` is not implemented.
- `Scanner` walks folders, tracks file stamps, parses in parallel and produces
  delta sets.
- `Watch` wraps FSEvents per folder with a fallback sweep.
- `Catalog` owns the SQLite store, migrations, the immutable snapshot and the
  search index.
- `Activation` owns the registration engine, the registrar protocol, the
  journal and launch reconciliation.
- `Coverage` indexes `cmap` coverage as a separate manual pass.
- `GoogleFonts` fetches the catalog, downloads TTFs and licenses, and caches
  small CSS preview subsets.
- `FontManagers` detects other managers' cache folders for the ignore list.
- `Preview` holds the font loader and the CoreText line and tile drawing.
- `Config` defines the versioned settings export.

## Data flow

1. A folder is added or seeded as a library root. Paths are resolved with
   `LibraryPath.resolve`; the canonical path is the stored identity.
2. `LibraryScanner` walks the root, skips ignored subtrees, and checks file
   provider metadata before opening anything. Online-only placeholders are
   skipped and counted; only files that were already indexed are marked
   `cloud`.
3. Changed files are parsed off the main actor, bounded by the active processor
   count. The main parse reads SFNT tables, including the `name` table for
   family, style and PostScript names. Preview loading uses CoreText descriptors
   separately; it is not part of indexing.
4. `LibraryDatabase` commits the batch in one transaction. A file already owned
   by another folder is moved rather than duplicated, and activation rows are
   preserved when a file is re-parsed.
5. The database builds an immutable `CatalogSnapshot`: families, faces, search
   blobs, counts and precomputed display fields. `AppModel` derives
   `visibleFamilies` only when the query, filter, selection, catalog revision or
   system-font toggle changes.
6. Views read precomputed values. Rows load one `CTFont` per face through
   `FontLoader` and draw a `CTLine` into a `Canvas`.

## Persistence

- Library: `~/Library/Application Support/Ur Fonts/library.sqlite3`, SQLite
  through GRDB with WAL and ordered migrations.
- Existing tables: `folder`, `file`, `face`, `activation`, `collection`,
  `collection_item`, `excluded_path`, `sample`. The wider schema sketch in
  `AGENTS.md` is a target, not current.
- File rows carry path, inode, size, mtime, parse version and status. Change
  detection is one `stat` for a known path, not a rescan.
- The activation journal stores one row per active face. The unit of
  registration is the file path.
- Collections store face IDs, so membership survives a different folder layout
  and an offline volume.
- Preferences: `~/Library/Preferences/com.10k24.urfonts.plist` holds appearance,
  system-font visibility and file-name fallback. The README lists the exact keys.
- Settings export is versioned JSON. It carries folders, collections (by
  PostScript name), samples, preview settings and ignored paths. A newer file is
  rejected, never silently accepted. Export/import and the filename fallback live
  in Settings, not the preview popover.

## Activation

`ActivationEngine` is the only writer to fontd. It takes file URLs, registers
scope `.user`, and reads the scope back before reporting success. Fonts already
inside a standard Fonts folder are installed, not ours: the engine skips them,
and the UI shows a locked state. Library files with duplicate PostScript names
activate together; the UI warns in orange when an installed font already owns the
name. A variable-file alternate is activatable: it replaces the family's static
styles and exposes its named instances. Journal rows are reconciled against fontd
at launch; reconcile never re-registers anything by itself.

## Preview

`FontLoader` is an actor with a bounded LRU. It resolves a catalog face by
PostScript name, because CoreText reports one descriptor per named variable
instance and the SFNT face index alone can select the wrong face; the face index
is only a fallback for subset files with no catalog face. It caches one `CTFont`
per face and derives point sizes with `CTFontCreateCopyWithAttributes` so moving
the size slider never reopens a file. `PreviewLine` owns line breaking,
truncation and vertical placement; the row caches that layout and the Canvas
draws it. Sample text follows the face being drawn, never a family-wide mask
union, and the uniform row height fits the longest script sample in the visible
set. CoreText fallback runs are replaced with the primary font's `.notdef`, so
previews never substitute another font. Activation controls and the VF badge
share `PreviewMetrics.controlScale`.

## Search and filtering

`CatalogFilter` is a value type evaluated by the snapshot, which keeps filters
testable without the app. Search covers family, style and PostScript names using
a lowercased UTF-8 blob. Language and character facets wait on the coverage
index. Coverage is a manual second pass because re-reading the library is
expensive and cloud folders can block.

## Cloud folders

Dataless File Provider files and iCloud placeholders are detected before open.
Files that were never indexed are skipped and counted, with no row and no
warning. An indexed file that becomes online-only keeps its faces, is marked
`cloud`, and shows as unavailable in the font sheet. Materialized files are
indexed on the next scan. Timeouts and offline failures are classified by
`CloudAccess` and surface as retryable cloud errors, never as damaged fonts.

## Google Fonts

The catalog comes from the public Google Fonts metadata endpoint. Downloadable
TTFs come from the official `google/fonts` repository. Downloads and licenses
live under Application Support in a managed folder that is indexed like any
other folder but hidden from the sidebar. Host rows reuse the library rows,
search and activation controls. Undownloaded families render from tiny CSS
subsets cached outside the library; previews never enter the catalog or settings
export.

## Concurrency

- `UrFontsCore` public types are `Sendable`. Mutable stores and engines are
  actors.
- The app target defaults to `MainActor`. `AppModel` owns state and exactly one
  `LibraryScanner`, so watcher deltas, sweeps, rescans and imports serialize.
- Anything that walks the library or reads a font file runs off the main actor.
- View bodies never start file or database work.

## Headless and CI

Headless modes set the activation policy to prohibited before any window exists
and assert that the process never becomes active. They render real views
offscreen with `ImageRenderer` or `NSHostingView` and write artifacts under the
temporary directory.

`scripts/ci.sh` is the deterministic gate: unit tests, Release build, a
23,000-font fixture with cold-index and one-file delta budgets, a search p99
budget, headless scenarios and bundle assembly. CI runs it on a macOS runner with
a current Xcode. `scripts/test.sh` adds the network-dependent Google render
locally. `act` cannot emulate macOS runners, so workflow changes are validated
with `actionlint` and by running the gate directly. Scroll and grid budgets still
require a real-window signpost run.

## Packaging

`scripts/build-app.sh` assembles `build/UrFonts.app` around the Release binary,
copies `Info.plist` and icon assets, and ad-hoc signs the bundle for development.
The bundle identifier is `com.10k24.urfonts`. A bare SwiftPM binary launches as
background-only; the bundle is required for menus, focus and activation.
Notarization, Sparkle and the DMG pipeline are release work, not part of the
development bundle.

## Where to change what

- New catalog behavior belongs in `UrFontsCore/Catalog`; views consume the
  snapshot.
- New file parsing belongs in `UrFontsCore/FontKit`.
- New activation semantics belong in `UrFontsCore/Activation`; views only map
  state to controls.
- New UI state belongs on `AppModel`; views render and send commands.
- New user-facing copy goes through `Messages` with dotted localization keys.
