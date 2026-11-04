# OPEN ISSUES - Ur Fonts

Kanban board. State is the H2 heading an item sits under, and nothing else:
**TODO** is open work, **Needs Verification** is implemented and covered by tests
but needs a real window to confirm, **Done** is finished. A finished item never
carries its state in the text. Done items are one line; the reusable reasoning
lives in `AGENTS.md` or the code, never here.

No counts, no dates, no `file:line` refs. Gates are the numbers in
`AGENTS.md` section Performance budget.

## Scope

A native macOS font manager for very large libraries. Replaces FontBase for the
work that matters: browse, preview, activate in place, organize, keep up with
watched folders. Built for a 23,000-file library that must scroll smoothly.

Locked decisions:

| Decision | Value |
|---|---|
| Display name | Ur Fonts, bundle `Ur Fonts.app` |
| Bundle ID | `com.10k24.urfonts` |
| Deployment | macOS 15.0+ |
| License | Apache-2.0, NOTICE for MIT-derived code |
| Distribution | Direct, Developer ID, notarized, Sparkle, Homebrew cask later |
| Sandbox | Off |
| Activation | Global only, `CTFontManagerRegisterFontURLs(.user)` |
| Adobe | No integration. Manual activation. Document preflight only |
| Plugins | None |
| List unit | Family-first, style expansion |
| Storage | SQLite via GRDB, in-memory catalog snapshot |
| UI | SwiftUI, fixed-height lazy rows, Canvas previews |

## TODO

### Phase 0 - Spikes

- **CI harness.** Run `swift test`, the fixture generator and the headless
  scenarios on a macOS runner. Gate: green with no focus change.

### Phase 2 - Browser

- **Preview prefetch.** Load the next viewport's fonts before they scroll in,
  skip prefetch above a scroll velocity threshold, and verify the LRU stays
  bounded while flinging through 26,000 faces.
- **Slider debounce check.** Confirm the size slider is smooth with derived
  fonts on the 25,000-face library in a real window; add debounce only if a
  measurement shows it is needed.

### Phase 3 - Activation

- **Activation UI.** Collection activation, temporary activation from the UI, an
  "activate more than N families" warning, and deactivate-all.
- **Activation feedback.** Show the conflict reason inline and offer reveal in
  Finder for a failed file.
- **Style activation from the page.** Keyboard focus and bulk style toggles.

### Phase 4 - Watcher

- **Cloud file providers.** Scanning an online-only Dropbox root stalled with no
  output and no files committed. Detect dataless files before reading, skip them
  with a report, and never let a scan hang on a provider.
- **Event replay.** Events while the app was closed rely on the launch rescan
  and the five-minute sweep. Persist and replay FSEvents IDs if a real folder
  proves this is not enough.
- **Watcher tests in CI.** The FSEvents test is opt-in; decide whether a CI
  runner can own it reliably.

### Phase 5 - Viewing

- **Saved samples.** Named samples with their own text and colors; apply to list,
  grid and font page.
- **Glyph sections.** Group the map by script instead of one flat grid, and add
  glyph names and SVG copy.
- **Quick Look.** Space on selection, follows arrow keys.
- **Script-aware samples.** Pick a Latin, CJK, Arabic or other sample from the
  font's coverage instead of showing tofu.

### Phase 6 - Organize

- **Collections.** Nested, manual, drag and drop.
- **Tags.** User tags with colors, auto tags from PANOSE, name and outline
  heuristics.
- **Notes and ratings.**
- **Problems.** Duplicates, conflicts, missing files, damaged files, offline
  volumes, with safe actions that never remove the last copy.

Gate: persistence round-trips through export and import; problems page reports
the same set the database holds.

### Phase 7 - Document preflight

- **Readers.** IDML `Resources/Fonts.xml`, INDD XMP, AI XMP `stFnt`, PDF
  `BaseFont`, PSD text-layer font names.
- **Fonts in document sheet.** Active, inactive, missing. Activate all.
- **Save-watch prewarm.** Optional; advisory only, never writes into project
  folders.

Gate: for one real document from each app, the reader's font list matches what
the app reports. No writes anywhere in the document's folder.

### Phase 8 - Power features

- **Coverage search.** Find fonts containing every character of a string, or a
  named language or character set.
- **SuperSearch.** Measured x-height, weight, contrast, proportion, slant, in
  ranges; combine with tags and name.
- **Similar fonts.** Shape-based nearest neighbours.
- **Compare.** Shared baseline, stacked and overlaid.
- **CSS export.** `@font-face` per style, copy per family.
- **Menu bar.** Quick search and activate.
- **Smart folders.** Rule-based, evaluated against the catalog snapshot.

Gate: coverage and metrics match reference measurements; every filter path stays
under 16 ms with 23,000 fonts.

### Phase 9 - Google Fonts

- **Metadata.** Bundled snapshot generated from the public directory; refresh
  script.
- **Download.** TTF from the official `google/fonts` repository, cached under
  Application Support, license file copied alongside.
- **Browse and activate.** Downloaded files behave like any other library folder.

Gate: clean install browses the catalog, downloads and activates a family, and
works offline after the first fetch.

### Phase 10 - Ship

- **Bundle.** `scripts/build-app.sh` assembles `Ur Fonts.app` with Info.plist
  document types, icon, hardened runtime, Sparkle framework.
- **Release.** Sign, notarize, staple, DMG, appcast.
- **Homebrew cask.**
- **README and help.** Install, first run, activation semantics, Adobe
  expectation, known limits.

Gate: notarized `Ur Fonts.app` launches on a clean macOS 15 account and activates
a font.

### Cross-cutting

- **Bench gate in CI.** Index, search and scroll budgets fail the build when
  exceeded.
- **Accessibility.** Canvas rows expose label, value and actions so VoiceOver
  never forces per-row materialization.
- **Attribution.** `NOTICE` records MIT-derived Cicero code and bundled data
  licenses.
- **`docs/ADOBE.md`.** Why there is no integration, what users should expect
  after activating a font, and the restart rule.
- **Icon and visual design.**
- **No telemetry.** Network access only for updates and Google Fonts downloads.

## Needs Verification

- **Registration behavior.** Local folder, 1/100/1,000 files, persistence across
  processes, double registration and duplicate PostScript behavior measured with
  `scripts/register-spike.sh`. Still needs an external volume, a cloud-synced
  folder, Font Book's view of a registered fixture, and a reboot.
- **Real library.** The fixture library indexes and rescans well inside the
  budget. The user's actual 23,000 fonts, with CFF, TTC and variable files, still
  need a first run and a spot check of parsed names.
- **Real window scroll.** The browser renders correctly offscreen and the list
  container met its budget in the spike. First-paint and p99 frame time in a real
  window, with preview fonts loading, still need signposts or Instruments.
- **Bug batch after first launch.** All Fonts selection, grid fitting, slider
  smoothness and the no-results footer were fixed and checked in headless
  captures; each still needs one pass in the live window.
- **Activation in the real app.** Click a library family, confirm another app
  sees the font, quit and relaunch, and confirm the dot and journal survive.
  No fontd integration test runs in CI.
- **Watching a real folder.** Drop a font into a watched Dropbox folder and
  confirm it appears within the debounce without a full rescan; check the
  five-minute sweep after quitting and relaunching.

## Done

- **Fixture library.** `FixtureGen` writes 23,000 valid TTFs with unique family,
  style and PostScript names; CoreText and the checksum test read them back.
- **Headless harness.** `--headless focus-check` proves the process never
  activates while creating and backing a window; `--headless render` writes a
  PNG. Artifacts land in `$TMPDIR/urfonts-headless/`.
- **List container.** Fixed-height SwiftUI lazy stack chosen over `NSTableView`
  by `--headless list-spike`; the real browser re-measures in Phase 2.
- **Core skeleton.** SwiftPM package, GRDB schema with WAL, and `LibraryLocation`
  for the default database path.
- **Font parser.** Reads `head`, `hhea`, `OS/2`, `name`, `fvar`, handles `.ttc`
  collections, and normalizes metrics by units per em. Damaged data throws, never
  crashes.
- **Scanner.** Prefetched resource keys, stamp-map delta detection, bounded
  parallel parse, removed files marked missing, one transaction per scan.
- **Catalog and CLI.** Immutable family/face snapshot with in-memory search;
  `urfonts-cli index`, `search`, `stats`; fixture library indexes and rescans
  inside the budget.
- **Browser shell.** Sidebar with All Fonts and per-folder rows, Add Folder panel,
  rescan, toolbar search and list/grid toggle.
- **Rows and previews.** Fixed-height family rows and grid tiles, one `CTLine`
  per row in `Canvas`, `FontLoader` LRU with process-local CTFonts, variable-font
  badge.
- **Preview settings.** Sample text, size, text color and background color,
  applied live to every row and tile.
- **Browser snapshot.** `--headless browser` renders the real window offscreen,
  asserts it never activates, and writes a PNG.
- **App bundle.** `scripts/build-app.sh` assembles and ad-hoc signs
  `build/Ur Fonts.app` so the app launches as a normal foreground app.
- **Sidebar selection.** All Fonts and folders use a real selection enum, so
  every row selects and highlights.
- **Footer layout.** Detail content and the status bar are a pinned VStack; the
  no-results state no longer lifts the footer or leaves a gap.
- **Preview sizing.** One CTFont per face; size changes derive with
  `CTFontCreateCopyWithAttributes`, so the slider cannot blank or reload previews.
- **Grid fitting.** Tiles shrink the sample to fit width and height instead of
  clipping it; list rows still truncate.
- **Folder management.** Remove Folder with confirmation, `urfonts-cli folders`
  and `remove-folder`, and `split-folder` to adopt existing rows into subfolders
  without re-reading fonts.
- **Dropbox library split.** The 25,611-file Dropbox root was replaced by the
  four font folders, 23,689 files, keeping parsed data.
- **Activation engine.** Actor with activate, deactivate and reconcile; success
  measured with `CTFontManagerGetScopeForURL`; every confirmed face journaled.
- **Activation safety.** System Fonts folders are skipped and locked, duplicate
  PostScript names are refused, and re-parse preserves the journal.
- **Activation UI.** Trailing dot on rows and tiles with none, partial, all and
  installed states; click activates or deactivates the whole family.
- **Watcher.** FSEvents reports `(root, path)` pairs; one-second debounce;
  directory events rescan the folder, file events scan only those files. Five
  minute sweep covers missed events.
- **Watched folders in the UI.** Add Folder offers Watch or One-time Scan;
  sidebar eye icon and Watch/Stop Watching actions.
- **Canonical paths.** Scanner and watcher agree on `realpath`; delta scans
  touch only the changed paths.
- **Font page.** Double-click or context menu opens a sheet with a large preview,
  style list with per-style activation, variable axes, info, reveal and copy.
- **Variable preview.** Axis sliders rebuild the CTFont from a variation
  descriptor; preview updates live.
- **Glyph map.** Character grid from `CTFontCopyCharacterSet`, search by
  character or code point, click copies the character, context menu copies the
  code point.
