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

- **Fixture library.** Generate 23,000 tiny valid TTFs with unique family,
  style and PostScript names. Gitignored, one script. Gate: the indexer walks
  and parses the whole set without special cases.
- **List container spike.** Two implementations of the same 23,000-row browser:
  fixed-height `LazyVStack` and `NSTableView`, both with Canvas previews. Gate:
  choose on measured p99 frame time and memory, record the number in AGENTS.md.
- **Registration spike.** Register and unregister 1, 100 and 1,000 fonts from a
  local folder, an external volume and a cloud-synced folder. Check reboot
  persistence, scope readback, duplicate PostScript failure, and what Font Book
  shows. Gate: every observed behavior and failure mode written into AGENTS.md.
- **Headless harness spike.** App launched with `.prohibited` activation policy
  drives one command through the production command seam, asserts
  `NSApp.isActive == false`, writes a snapshot and exits with a status. Gate:
  green on a CI macOS runner with no focus change.

### Phase 1 - Core skeleton

- **SwiftPM package.** Targets `UrFontsCore`, `UrFonts`, `urfonts-cli`. Swift 6.2,
  strict concurrency, macOS 15.
- **Schema and migrations.** GRDB, WAL, tables in AGENTS.md section Data model.
- **SFNT reader.** `head`, `hhea`, `OS/2`, `name` (IDs 1, 2, 16, 17), `fvar`,
  `STAT`, `cmap`, `GSUB` feature tags. Damaged tables return less, never crash.
- **Scanner.** Enumerate with prefetched resource keys, stamp map, bounded
  parallel parse, delta set, `parseVersion` for re-index.
- **Catalog.** Immutable snapshot plus in-memory search index; views never read
  files or query per row.
- **CLI.** `urfonts-cli index`, `search`, `list`, `--json`.
- **Headless.** `--headless index` and `--headless search`.

Gate: cold index of 23,000 files under 30 s; warm launch reads zero font files;
`swift test` green.

### Phase 2 - Browser

- **App shell.** One main window, split view, sidebar, detail browser.
- **Family-first list.** Fixed row height, style expansion, selection, keyboard
  navigation, `.equatable()` rows.
- **Search.** Token parser (`name:`, `tag:`, `wght:`, `script:`, `variable:`),
  debounce, in-memory filter.
- **Grid view.** Fixed tile size, same preview path.
- **Preview rendering.** `CTFont` from file URL, LRU 256, prefetch visible +/-
  50 at bounded concurrency, one `CTLine` per row in `Canvas`, manual ellipsis.
- **Headless.** `bench scroll`, `bench search`, snapshot mode.

Gate: scroll p99 frame under 8.3 ms; search under 16 ms; RSS under 300 MB and
flat while scrolling.

### Phase 3 - Activation

- **Registrar.** `FontRegistrar` protocol over CoreText; fake for tests.
- **Engine actor.** Activate, deactivate, batch by family or collection,
  temporary session scope, confirmation through `CTFontManagerGetScopeForURL`
  and the registered-fonts-changed notification.
- **Journal and reconcile.** Persist intent, reconcile at launch, repair moved
  or missing files, deactivate all, undo.
- **Conflicts.** Detect duplicate PostScript names before registering; explain
  and block.
- **Safety.** Never unregister or disable fonts under a standard Fonts folder
  unless the user explicitly opts in.

Gate: one family activated and confirmed under 250 ms; killing the app mid-batch
leaves a reconcilable state; fake-registrar unit tests cover every transition.

### Phase 4 - Watcher

- **FSEvents.** One stream per watched folder, `UseCFTypes | FileEvents |
  WatchRoot | NoDefer`, persisted `lastEventId`, one-second debounce.
- **Fallback sweep.** Every five minutes, and on mount notifications.
- **Delta handling.** Rename, delete, offline volume, permission loss, 1,000-file
  drop.

Gate: single-file delta under 50 ms end to end; large drop does not trigger a
full rescan.

### Phase 5 - Viewing

- **Preview settings.** Text, size, weight, line height, alignment, text color,
  background color.
- **Saved samples.** Named samples with their own text and colors; apply to list,
  grid and font page.
- **Variable fonts.** Axis sliders and named instances; persist the chosen
  instance per face.
- **Font page.** Large editable sample, style table with per-style switches,
  glyph map with sections and search, info panel.
- **Quick Look.** Space on selection, follows arrow keys.
- **Script-aware samples.** Pick a Latin, CJK, Arabic or other sample from the
  font's coverage instead of showing tofu.

Gate: golden snapshots; no clipped descenders; CJK and RTL fonts preview in their
own script.

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

## Done
