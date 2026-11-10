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
watched folders. Built for a large library that must scroll smoothly.

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
- **Competitor benchmark.** Compare Cicero against Ur Fonts on the same machine
  and two libraries: the large fixture library and the real folders.
  Measure cold launch to first row, scroll p50/p99 and worst hitch, RSS after
  load and after scrolling, search latency, one-family activation, and cold
  index. Cicero is GUI-only and needs manual or scripted driving; Ur Fonts has
  headless modes, so state that asymmetry in the write-up. Record method,
  versions and raw frames in `BENCH.md`, and add a short summary to the README
  only when the comparison is fair.

### Phase 2 - Browser

- **Preview prefetch.** Load the next viewport's fonts before they scroll in,
  skip prefetch above a scroll velocity threshold, and verify the LRU stays
  bounded while flinging through the full library.
- **Slider debounce check.** Confirm the size slider is smooth with derived
  fonts on the full library in a real window; add debounce only if a
  measurement shows it is needed.

### Phase 3 - Activation

- **Activation UI.** Temporary activation from the UI, an "activate more than N
  families" warning, and a global deactivate-all. Collection bulk activation is
  implemented.
- **Activation failure feedback.** Duplicate conflicts show the owner path
  inline. Add reveal-in-Finder for a failed file and a one-click retry.
- **Style activation from the page.** Per-file checkboxes are implemented;
  keyboard focus and bulk style toggles remain.

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

- **Glyph names.** CoreText exposes no public glyph-name API; read `post` table
  names if this is worth the parser work.
- **Quick Look.** Space on selection, follows arrow keys.

### Phase 6 - Organize

- **Collection polish.** Nested collections, multi-select adds. Drag-and-drop
  was removed; it needs an AppKit or custom-list solution.
- **Tags.** User tags with colors, auto tags from PANOSE, name and outline
  heuristics.
- **Notes and ratings.**

Gate: the warnings page reports the same set the database holds.

### Phase 7 - Document preflight

- **Readers.** IDML `Resources/Fonts.xml`, INDD XMP, AI XMP `stFnt`, PDF
  `BaseFont`, PSD text-layer font names.
- **Fonts in document sheet.** Active, inactive, missing. Activate all.
- **Save-watch prewarm.** Optional; advisory only, never writes into project
  folders.

Gate: for one real document from each app, the reader's font list matches what
the app reports. No writes anywhere in the document's folder.

### Phase 8 - Power features

- **Character filter on the real library.** The filter is exact when ranges are
  indexed; confirm the UI and speed after indexing the full library.
- **Glyph map extras.** Check section picker, code-point search and SVG copy on a
  real Latin and CJK font; copied SVG should open in a vector editor.
- **Coverage search.** Find fonts containing every character of a string, or a
  named language or character set. Depends on indexing cmap coverage per face.
- **Character presence filter.** A filter for "has character X" and "has every
  character in this string", using the same coverage index. Belongs in the
  advanced search workflow, not only in the font page glyph map.
- **SuperSearch.** Measured x-height, weight, contrast, proportion, slant, in
  ranges; combine with tags and name.
- **Similar fonts.** Shape-based nearest neighbours.
- **Compare.** Shared baseline, stacked and overlaid.
- **CSS export.** `@font-face` per style, copy per family.
- **Menu bar.** Quick search and activate.
- **Smart folders.** Rule-based, evaluated against the catalog snapshot.

Gate: coverage and metrics match reference measurements; every filter path stays
under 16 ms at full scale.

### Phase 10 - Ship

- **Bundle.** `scripts/build-app.sh` assembles `Ur Fonts.app` with Info.plist
  document types, icon, hardened runtime, Sparkle framework.
- **Release.** Sign, notarize, staple, DMG, appcast.
- **Homebrew cask.**
- **Help and docs.** README exists; add in-app help, first run, activation
  semantics, Adobe expectation and known limits before launch.
- **Donation option.** Add a Buy Me a Coffee (or equivalent) link to the README,
  the About panel, and the first release notes.
- **Manual-use gate.** Launch only after several weeks of the author using it as
  the daily manager, with the core workflows holding up on the real library.

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
- **App icon.** `design/icon/UrFonts.icon` compiles to `Assets.car` and
  `design/icon/legacy/icon-1024.png` builds `UrFonts.icns`; review light, dark,
  tinted and clear appearances in Icon Composer.
- **No telemetry.** Network access only for updates and Google Fonts downloads.

### FontBase parity verification

Everything to clear before claiming parity with FontBase's free tier. Missing
features are listed too, so the gap is explicit rather than implied.

**Library and indexing**

- The real library across the Dropbox folders: cold index, warm start, full
  rescan, memory.
- CFF/OTF, TTC/OTC, variable fonts: names, axes, units per em, feature tags.
- Cloud-backed folders: no hang on placeholders, sane behavior when offline.
- Delta: add, modify, delete and rename one file; watched event and five-minute
  sweep both see it.
- Duplicate PostScript names across folders are reported, not silently merged.

**Activation**

- Activate/deactivate from list, font sheet and collection; confirmation and
  dots update.
- Quit and relaunch: journal reconciles, dots match fontd.
- Reboot persistence.
- Fonts in `~/Library/Fonts`, `/Library/Fonts` and system folders stay locked.
- Duplicate registration errors are treated as success only when scope matches.
- Removing or ignoring a folder deactivates its active faces first.
- Another app sees an activated font; Adobe may need a relaunch.

**Browsing and preview**

- Trackpad scroll through the full family list and a search result without lag.
- Search; kind, italic, bold, script and character filters; system toggle;
  sorting; font/file counts.
- List/grid, wrapping, truncation, presets, status bar size, colors, swap,
  separators over light and dark preview backgrounds.
- Saved samples: create, update, select, delete, relaunch.
- Collections: create, rename, delete, add/remove family, filter, missing-file
  retention.
- Nested folder tree: expand/collapse, selection by subfolder, counts, watched
  icon and folder context menus.
- Sidebar counts are fonts (faces) for All Fonts, folder tree nodes and
  collections; folder tooltips keep file counts.
- Active sidebar: count matches the activation journal; activating and
  deactivating a family moves it in and out; partial families appear; the empty
  state explains how to populate it.
- Status text and window subtitle: All Fonts shows the library font total; a
  folder or collection shows its own face total; search shows "x of scope
  total fonts"; hiding system fonts moves the hidden faces into the "of"
  denominator; Warnings shows only its warning count.
- Add Fonts: choose files and drop files/folders on the browser; files inside an
  indexed folder join it, outside files appear under their parent directory.
- Warnings: badge matches duplicate plus missing counts; duplicate names exclude
  missing files; each type collapses and expands; reveal and copy path work.

**Coverage and scripts**

- Coverage index on the full library: time, progress, stop and resume.
- Script and character filters return the expected fonts.
- Script-aware previews; native-speaker review per script (backlog).

**Font page**

- Styles, variable axes, glyph map, sections, search, SVG copy, OpenType feature
  list, info.
- Missing characters render .notdef without crashing.

**Settings**

- Export/import round trip; newer-version file rejected; usable from a dotfiles
  repo.

**FontBase handoff**

- Deactivate all in FontBase and quit. Ignore its cache folder in the sidebar
  (or move it out) so copies do not appear as installed duplicates.
- Add its folders manually; compare family and collection counts with FontBase.
- Recreate collections, activate the previous set, confirm no duplicate
  PostScript conflicts.
- Decide whether manual folders are enough or a read-only importer is worth it.

**Missing for parity (not verification)**

- Deactivate-all.
- OpenType feature filtering.
- GlyphsApp language parity.

**Release**

- Icon appearance review, notarization, Sparkle, Homebrew cask, README/help,
  donation, Apache/NOTICE.

### Backlog (lowest priority)

- **Favorites.** Red heart toggle on individual fonts and families, plus a
  Favorites section in the sidebar with a count. Store face IDs; a family
  favorite covers all of its faces. Survives reindexing and settings export.
- **Font designer workflow.** Re-exporting a font over an existing file is the
  common authoring loop and a known source of stale caches. Detect replacement
  by content hash delta, not only size and mtime. Reload the changed face
  automatically or on demand, refresh its activation, and offer a targeted
  font-cache purge for macOS and Adobe apps when a replaced file was active.
  Warn that a running app may need a relaunch.
- **Hash-based change detection.** Add a content hash to the file stamp so a
  re-export with identical size and timestamp still triggers a reload.
- **GlyphsApp language parity.** Support every language GlyphsApp supports, not
  just the current script list. Take the language inventory from GlyphsInfo
  rather than memory: language tags, required characters, sample strings and
  RTL/BiDi expectations. Index language-level coverage per face, extend the
  script mask accordingly, and add language filters and samples per language.
  Ship in tiers by script family, not all at once.
- **Native-speaker verification.** Rendering correctness for each script needs a
  native speaker or type designer: shaping, joining, mark placement, RTL order,
  line breaking, sample text quality. Build a small review checklist per script
  and record who verified it in the repo. Do not claim coverage parity without
  this pass.
- **Windows and Linux.** Port the library, scanner and activation model to
  Windows and Linux, with platform-specific font registration.
- **OpenType feature filter.** Feature tags are now read and shown on the font
  page. Filtering the library by small caps, lining/oldstyle numerals, stylistic
  sets and similar is still to do. Low priority, after language parity.
- **FontBase migration.** Simplified: no IndexedDB/V8 reader for now. Add its
  folders manually, then use Export/Import Settings JSON to carry folders,
  collections, samples and preview between machines or dotfiles. Revisit a
  read-only FontBase importer only if manual folder setup proves painful.
- **FontBase handoff notes.** Document deactivating all fonts in FontBase,
  quitting it, and ignoring its cache folder in Ur Fonts before activating the
  same fonts, to avoid duplicate PostScript registrations.

## Needs Verification

- **Registration behavior.** Single, small and large batches, persistence across
  processes, double registration and duplicate PostScript behavior measured with
  `scripts/register-spike.sh`. Still needs an external volume, a cloud-synced
  folder, Font Book's view of a registered fixture, and a reboot.
- **Real library.** The Dropbox folders are indexed and were split from the
  provider root without re-reading. Still needs a spot check of parsed names
  after the file-name fallback, and a timed full rescan per folder.
- **Real window scroll.** The browser renders correctly offscreen and the list
  container met its budget in the spike. First-paint and p99 frame time in a real
  window, with preview fonts loading, still need signposts or Instruments.
- **Bug batch after first launch.** All Fonts selection, grid fitting, slider
  smoothness and the no-results footer were fixed and checked in headless
  captures; each still needs one pass in the live window.
- **Duplicate metadata in third-party files.** A file can carry another font's
  name table: a file named `Manera-Regular.otf` reports family `New Font` and
  PostScript `NewFont-Regular`, so it groups with the real New Font file. This is
  font metadata, not a preview-cache leak. The detail page shows each file path
  and marks the shared PostScript name. Never rewrite the font file.
- **Duplicate file versions.** Under `wk13_exports`, `Referential Mono 0.970_1`
  shows its wk13 preview and checkbox; its missing FontBase copy is disabled as
  missing; activating one version disables the other versions and names the
  active path. The same rule applies across families.
- **Activation in the real app.** Click a library family, confirm another app
  sees the font, quit and relaunch, and confirm the dot and journal survive.
  No fontd integration test runs in CI.
- **Watching a real folder.** Drop a font into a watched Dropbox folder and
  confirm it appears within the debounce without a full rescan; check the
  five-minute sweep after quitting and relaunching.
- **Coverage on the real library.** Index the full library and confirm the time
  is acceptable on the Dropbox-backed folders; check that script filters and
  script-aware previews match the fonts, especially CJK and Arabic.
- **Scroll isolation and smoothness.** Scroll each folder, switch away and back,
  and confirm it returns to its own top family. Scroll the full family list and
  a search result with a trackpad; `--headless scroll --rows` reports the
  offscreen baseline.
- **Saved samples in the live UI.** Create two samples, switch between them,
  edit one, delete one, and relaunch to confirm they persist.
- **Collections in the live UI.** Create one from the sidebar and one from a
  family, add/remove members, select the collection, rename and delete it.
- **System fonts in the live UI.** Toggle Show system fonts off and on; confirm
  the count changes and leading dots disappear from Apple families. Confirm the
  former "." family now shows its filename or real name, including TWK Everett.
- **Presets and sorting.** Check the four presets wrap or truncate correctly in
  list and grid, the status bar size slider is independent, and system families
  sort alphabetically with dots stripped.
- **Settings round trip.** Export settings, quit, clear a folder/collection,
  import, and confirm folders, collections, samples, preview and ignored folder
  paths return.
- **No font fallback.** Type Arabic or another unsupported string into a Latin
  font preview; missing characters show the font's `.notdef`, never GeezaPro or
  another installed font. The Arabic auto-sample is not chosen unless the face
  covers every sample character.
- **Text growth direction.** Drag the status bar size slider from small to
  large; text should grow downward (or symmetrically while it fits), never only
  upward. The slider stays accent blue while the window is active.
- **Google Fonts.** Select Hosts → Google Fonts, search a family, download it,
  confirm its styles appear in the library and activate; quit and relaunch to
  confirm the managed folder is still indexed. Check the first load time and
  GitHub rate limit behavior.
- **Folder order.** Right-click Move Up/Move Down and relaunch: the order
  sticks. A newly added folder lands at the bottom. On a clean library the three
  macOS font folders are present, watched, and ordered first.
- **Collection bulk activation.** Activate All and Deactivate All in a
  collection context menu; dots update and other apps see the change.
- **Style paths.** Open a family with multiple files; every style shows its
  absolute path. Files with the same PostScript name show the duplicate triangle
  and explanation.
- **Installed marker.** System-font rows show a gray checked square at the same
  size as the open activation square.
- **Warning copy.** Right-click a warning row or its file path and copy the
  message; copying a whole warning type includes every entry.
- **Swap and counts.** Swap text/background colors and confirm samples mark
  dirty; confirm folder badges match All Fonts units and tooltips show files.
- **Folder UX.** Two add flows, magnifier icon for watched folders, rename that
  changes only the label, watched checkbox with a rescan confirmation, reveal in
  Finder, removal that reports active fonts and deactivates them first, and
  Settings → Ignored Folders with detection suggestions.
  Implemented and unit-tested at the store level; menu and Settings behaviour
  need a live window.
- **Axis slider smoothness.** The sheet now draws a fixed point size and changes
  only the variation, so weight changes no longer rescale the sample. Confirm
  300–400 interpolates smoothly on a real variable font.

## Done

- **Fixture library.** `FixtureGen` writes a large batch of valid TTFs with
  unique family, style and PostScript names; CoreText and the checksum test read
  them back.
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
- **Rows and previews.** Uniform family rows whose height grows with the sample
  size, fixed-height grid tiles, one `CTLine` per row in `Canvas`, `FontLoader`
  LRU with process-local CTFonts, variable-font badge.
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
- **Dropbox library split.** The Dropbox root was replaced by its font folders,
  keeping parsed data.
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
- **Naming fallback.** A setting substitutes the file stem for punctuation-only
  family names and `Regular` for punctuation-only styles; applied at snapshot
  build, no rescan.
- **Saved samples.** Named preview samples stored in SQLite with text, size and
  hex colors. Preview text is the first field, autofocused from ⌘E; picking a
  sample applies it, Update stores edits, Save as Sample always creates a new one.
- **Scroll performance.** Per-tick `@State` writes moved to a reference-type
  cache; filtered rows are a stored array rebuilt only on input changes; search
  scans UTF-8 bytes. The status line and window subtitle report fonts in the
  current sidebar scope. Offscreen row-step benchmark stays near one frame at
  the median on the full library.
- **Facet filters.** Static versus variable, has italic, has bold, script, all
  combined with text search; logic lives in `CatalogFilter` and is unit-tested.
- **Coverage index.** `cmap` parsing for formats 4 and 12, script mask and exact
  codepoint ranges per face, batched background indexer, CLI `index-coverage`,
  and an Index Coverage action in the filter popover.
- **Character filter.** "Contains characters" requires every scalar in the
  loaded ranges; filters combine with script, kind, italic and bold.
- **Collections.** Create, rename, delete; add or remove a family from the row
  context menu; sidebar selection filters by collection; member faces survive a
  missing file. Context menu activates or deactivates all stored faces.
- **Nested folders.** The sidebar mirrors indexed directories with native
  List/OutlineGroup rows, path-prefix selection, family counts, and watched
  icons.
- **Add Fonts.** Picker and Finder drop add individual files; files inside an
  indexed folder join it, outside files get a parent-directory root.
- **Folder exclusions.** Ignore This Folder and Settings → Ignored Folders share
  one list: resolved paths, add/remove, warnings before an overlapping add,
  deactivation, row deletion, and skipped full/delta scans. FontBase cache
  suggestions come from a manager-agnostic detector protocol.
- **Nested roots.** Deepest indexed root owns each file; adding a nested root
  adopts rows, parent scans skip deeper subtrees, and removal re-parents rows to
  the deepest remaining ancestor.
- **Missing cleanup.** Remove Missing Entries in Warnings deletes stale rows
  after confirmation, including their collection membership. No file on disk is
  touched.
- **Warnings.** Live duplicate PostScript names and missing files, grouped in
  collapsible disclosure sections, with right-click copy and reveal/copy-path.
- **Per-file availability.** Duplicate PostScript versions show per-file
  checkboxes; one active version disables the others and names the owner path.
  Missing and installed files are distinct states.
- **No font fallback.** Previews draw primary runs normally and render fallback
  runs as the primary font's `.notdef`; script samples are selected only when
  the complete sample is covered.
- **System font visibility.** Show system fonts defaults on; the Filters toggle
  hides families whose faces all live under `/System/Library/Fonts`.
- **System name display.** Apple's leading dot is stripped for display when the
  whole family is a system family.
- **Sorting.** Families sort by displayed name, so stripped system names sit
  alphabetically instead of at the top.
- **Preview presets.** Alphabet, AaBbCcDdEeFf, pangram and numbers; selectable
  without changing size.
- **Preview layout.** List rows wrap to two or four lines with ink-based line
  spacing and grow with the size slider; grid tiles stay single-line, honor the
  size, and truncate. Size slider lives in the status bar (12-108 pt) so it keeps
  the accent tint.
- **Missing glyphs.** Preview rendering replaces CoreText fallback runs with the
  primary font's `.notdef`. The CoreText glyph test covers missing-character
  mapping; the headless render covers the drawn result.
- **OpenType feature display.** GSUB/GPOS feature tags read per face and listed
  on the font page with readable names; stylistic sets and character variants
  numbered.
- **Google Fonts provider.** Runtime catalog from the public metadata endpoint,
  TTF files from the official `google/fonts` repository, license copied, cache
  under Application Support, downloads indexed as a hidden managed folder.
  Search, download and refresh in the Hosts view; CLI `google-catalog` and
  `google-download`.
- **Contrast-aware separators.** List and grid separators use a neutral gray
  chosen from the preview background luminance, not the app appearance.
- **Color swap.** One button swaps preview text and background colors.
- **Consistent counts.** Sidebar rows, folder tree nodes and collections count
  fonts (faces), matching All Fonts; file counts moved to the tooltip.
- **Export/Import Settings.** Versioned JSON (`urfonts-settings.json`) with
  folders, collections (fonts by PostScript name), samples and preview settings;
  designed for a user's dotfiles repo.
- **Broken-name fallback.** Names with no letter or digit, including `.` plus
  control characters, fall back to filename, full name, then PostScript name.
- **Glyph sections.** The map has a Unicode section picker, search and SVG copy
  alongside character and code-point copy.
- **Script-aware previews.** CJK, Hangul, Kana, Arabic, Hebrew, Devanagari and
  Thai families preview in their own script once coverage is indexed; Latin and
  Latin-plus-Greek/Cyrillic keep the user sample.
