# AGENTS.md - Ur Fonts

## Mission

Build a native macOS font manager for very large libraries. The target library
holds tens of thousands of font files. FontBase is the incumbent; modern managers
lag when scrolling that library. Ur Fonts must scroll smoothly, activate fonts in
place, never copy or move a user's font files, and keep a static or watched
folder in sync with deltas instead of rescans.

The product is the library and the browser. Activation is a side effect of the
library, not the other way round.

## Always use these skills

- **caveman** in terse mode: cut filler, keep technical accuracy.
- **software-design-philosophy**: deep modules, simplicity, no reinvented wheels.

Work in focused increments of about 30 minutes. Finish the increment, verify it,
then continue. Do not stop at the first green test if the increment is unfinished.

## Non-goals

- No font editing, renaming, moving or copying. Library files are opened read-only.
- No sandbox. Global font registration and folder access need an unsandboxed app.
- No Mac App Store. Direct notarized distribution only.
- No Adobe integration, no plug-ins, no Apple Events. If a font is inactive the
  user activates it and restarts the Adobe app if the app caches its font menu.
- No per-app or per-window activation. Activation is always global.
- No accounts, teams, crowd tags, or required cloud service.
- macOS only in the current scope. Windows and Linux are backlog, not current work.
- No WOFF or WOFF2 rendering. CoreText cannot use them.
- No WOFF2 web export pipeline. CSS export only.

## Key insights

These are the facts the design rests on. Verify before changing any of them.

### Activation

- `CTFontManagerRegisterFontURLs(urls as CFArray, .user, true, handler)` makes
  fonts available to all processes for the current user, from any folder, and the
  registration survives sessions until unregistered. `.user` and `.persistent`
  are the same value (2). `.session` (3) lasts until logout.
- The font file must not move or be renamed while registered. This matches the
  read-only rule.
- Symlinking into `~/Library/Fonts` does not work. Registration is the only
  copy-free path.
- Confirmation is observable: `CTFontManagerGetScopeForURL`,
  `CTFontManagerCopyRegisteredFontDescriptors(.user, true)`, and the distributed
  `kCTFontManagerRegisteredFontsChangedNotification`. Do not report success
  before fontd reports the scope.
- Fonts already inside a standard Fonts folder are enabled and disabled with
  `CTFontManagerEnableFontDescriptors`, not registration. Never touch them unless
  the user explicitly opts in.
- Registering the same file twice fails with "The file has already been
  registered in the specified scope." Treat that as success when the scope
  matches; do not surface it as an error.
- Duplicate PostScript names across different files are **not** reliably
  rejected. A second file with the same PostScript name registered cleanly in
  the Phase 0 spike. fontd will not solve conflicts for us: detect them and warn
  before activating both.
- Registration is per-file: about 2 ms per font once warm, and the first call in
  a process pays a fontd start cost. Measure with `scripts/register-spike.sh`;
  do not copy numbers from here.
- Running apps refresh their font menus on their own schedule. Activate then
  launch is reliable. Activate into a running app may need a relaunch. This is
  app behavior, documented in the README, not something we work around.
- `ActivationEngine` is the only writer to fontd. The unit of registration is
  the file path; the journal stores one row per face. Every success is read back
  with `CTFontManagerGetScopeForURL`; a registration that fontd does not confirm
  is a failure, never an optimistic success.
- Reconcile at launch drops journal rows whose scope no longer matches fontd. It
  never re-registers anything by itself.
- Re-parsing a changed file must preserve activation rows: face IDs are stable,
  so capture them before the face delete and reinsert after the insert.
- Fonts under `/System/Library/Fonts`, `/Library/Fonts` or
  `~/Library/Fonts` are installed, not ours. Skip them in the engine and show a
  lock in the UI; never unregister them.
- Toggling is family-level in the UI. Activating a family registers each of its
  files once and journals every face.
- Preview never registers anything. `CTFontManagerCreateFontDescriptorsFromURL`
  plus `CTFontCreateWithFontDescriptor` is enough, and it is process-local.
  Variable fonts return one descriptor per named instance, so dedupe descriptors;
  register by URL, not by descriptor.

### Performance

- The browser is family-first. Tens of thousands of files collapse to a few
  thousand rows.
- Rows have fixed height. Total content height is `count * rowHeight`. No
  self-sizing rows, no layout pass per row.
- One `CTLine` per row drawn into a SwiftUI `Canvas`. No TextKit, no
  `NSAttributedString`, no `Text` inside rows. Truncate with
  `CTLineCreateTruncatedLine`. Oversize the canvas to the glyph ink bounds so
  descenders are not clipped.
- Rows conform to `Equatable` and use `.equatable()`.
- Nothing walks the library or reads a file inside `body`. Views read precomputed
  values from the catalog snapshot.
- `FontLoader` is an actor with an LRU of about 256 fonts. Prefetch of the
  visible window and `F_RDADVISE` read-ahead are planned, not implemented; do
  not describe them as present.
- Phase 0 measured both containers with `UrFonts --headless list-spike`. The
  fixed-height SwiftUI lazy stack wins on p99 and keeps only visible rows alive.
  `NSTableView` created row views for every jump and exceeded the frame budget.
  Keep the list behind a small container type, but switch it only with a new
  measurement, not an opinion. The spike does not capture SwiftUI's Core
  Animation commit, so Phase 2 re-measures the real browser with signposts.
- Grid tiles are drawn live; only a bounded `NSCache` of recent tiles is kept.
  No per-font preview files on disk by default.
- The browser is `ScrollView` + `LazyVStack` with uniform rows: 128 pt normally,
  176 pt for mid-length samples and 224 pt for the full alphabet preset (four
  lines). Row height changes only when the sample text does. Each row has an
  `@State` `LoadedFont`, loaded through `FontLoader.shared`. A row's
  `.task(id:)` keys on path and face index only; size changes never reload.
- List rows wrap with a typesetter and measure line ink bounds, so display faces
  with ink past their metrics do not overlap. Text space is y-up: a line's ink
  ascent is `bounds.maxY`, descent is `-bounds.minY`. Getting that backwards
  makes text grow upward when the size increases.
- Wrapped text centers when it fits and pins to the top (6 pt) when it does not,
  so overflow clips at the bottom rather than above the row. Grid tiles stay
  single-line and fitted.
- Sorting uses the displayed family name, after system dot stripping, not the
  raw grouping key. Otherwise Apple's dot-prefixed names sort before letters.
- Presets live in `PreviewPreset` and only change the sample text. Size is a
  separate control in the status bar and never tied to a preset. It cannot live
  in the toolbar: macOS 26/27 draws toolbar sliders untinted (gray) even with
  `.tint` or a native `trackFillColor`, while content sliders keep the accent.
  Missing characters map to glyph 0 (.notdef); no crash path is needed.
- `--headless browser` renders the real window offscreen, captures it with
  `cacheDisplay`, and proves the process never activates. Use it to check layout
  and glyph orientation; use a real window for frame timing. `--grid` and
  `--query` select the other view and a search term; `--warnings` opens the
  Warnings page and waits for its rows; `--active` selects the Active list.
  `--headless add-files` exercises the individual file add against a temporary
  database.
- Sidebar selection uses an enum, never an optional ID. A `nil` tag is SwiftUI's
  "no selection" and makes the All Fonts row unselectable.
- Detail content and the status bar are a pinned `VStack`. `safeAreaInset` lets
  the footer float above short states such as no search results.
- Preview size is derived from one cached CTFont per face with
  `CTFontCreateCopyWithAttributes`. Never key a font load on point size: that
  reopens the file and blanks the row on every slider tick.
- Scroll-position bookkeeping lives in a reference-type `ScrollMemory`, not
  `@State`. Writing `@State` on every scroll tick invalidated the whole lazy
  stack and made scrolling lag. The binding still updates `topFamilyID`; only
  the cache writes are non-observable.
- `--headless scroll [--query ...] [--rows]` measures the real browser list
  offscreen. `--rows` moves one row per step, which matches normal scrolling;
  without it the driver jumps across the list and measures worst-case row churn.
- Grid tiles fit the whole sample by shrinking it. List rows truncate with an
  ellipsis. Both inset horizontally so italic overhangs survive.
- The family sheet renders the large preview through `PreviewLine.drawFitted`
  and derives axis variations with `CTFontDescriptorCreateCopyWithAttributes` +
  `kCTFontVariationAttribute`. `CTFontCreateCopyWithAttributes` takes a
  descriptor, not an attribute dictionary.
- The glyph map comes from `CTFontCopyCharacterSet` over the face's own cmap,
  scanning code points up to U+2FFFF and skipping controls. Nothing is indexed;
  it runs when the sheet opens and works for inactive fonts.
- Glyph sections are a coarse Unicode bucket picker, not a full block database.
  SVG copy draws the outline at units per em and flips Y in the root transform.
  CoreText has no public glyph-name API; names would require parsing `post`.
- OpenType features come from the GSUB/GPOS feature list only: version, then
  Script/Feature/Lookup offsets, then feature records. No shaping or lookup
  interpretation. Unknown tags show raw; `ssNN` and `cvNN` are numbered.
- Separators over previews are chosen by background luminance (black or white at
  16%), never `Color.primary`, which follows the app appearance instead.

### Indexing

- Read each font file once. The parser reads `head`, `hhea`, `OS/2`, `name` and
  `fvar` today. `STAT`, `cmap` coverage and `GSUB` feature tags are planned;
  coverage and language filters must not ship before the cmap pass exists.
- CoreText gives localized names and descriptors. The SFNT reader supplies
  PANOSE, `fvar` axes and normalized metrics; nothing else yet.
- Change detection is `path -> (inode, size, mtimeNanos, parseVersion, status)`.
  FSEvents gives a path, so a delta costs one `stat`, not a rescan.
- Parse in parallel, bounded by `activeProcessorCount`, commit in one transaction.
- Advanced metrics (contrast, classification, embeddings) are planned as a lazy
  background pass. Only x-height and cap height from `OS/2` exist today.
- The snapshot is the warm-launch cost. One joined query, positional row reads,
  memoized family keys, lowercased search folds. Measure with
  `urfonts-cli stats` before adding a cache.
- Search covers family, styles and PostScript names. Family grouping uses a
  case- and diacritic-folded key; search folds only lowercase because it runs on
  every style and PostScript name.
- Facet filtering is a value type (`CatalogFilter`) evaluated by the snapshot, so
  it is testable without the app. Language and character facets wait for cmap
  coverage; do not fake them from font names.
- `visibleFamilies` is a stored array rebuilt only when query, filter, selection
  or the catalog changes. Never filter inside a view body: a fresh array per
  scroll tick made SwiftUI diff thousands of rows and was the search-result lag.
- Collections store face IDs, not family IDs. A family is in a collection when
  any of its faces is. Missing files keep their faces, so collection membership
  survives an offline volume. Counts are cached per collection.
- Active is a selection scope over the activation journal, not a folder. It
  lists families with any active face and counts active faces; changing the
  journal invalidates the visible cache. Installed system fonts never appear.
- Search uses a lowercased UTF-8 blob per family, not `String.contains`, so a
  keystroke scans bytes instead of graphemes.
- Settings export is `LibraryConfiguration`, versioned JSON. Collections store
  PostScript names, not face IDs, so a file survives a different folder layout.
  Version is checked on import; never silently accept a newer file.
- Sidebar counts are fonts (faces), matching All Fonts. File counts belong in
  tooltips; file and face counts differ for TTC/OTC files.
- User-facing text says "fonts", never "faces". A face is the stored unit; a
  font is what the user selects and previews. "Face" stays in the schema and
  code. The window subtitle and status bar count fonts: the denominator is the
  selected sidebar item's faces (library total only for All Fonts), and the
  numerator is the faces in visible rows after search, filters and the system
  toggle. Scope counts use paths and collection membership, never the sum of a
  family's faces, because a family can span folders.
- A saved sample is a snapshot of preview text, size and colors. Selecting one
  applies it; Update overwrites the selected sample; Save as Sample always
  creates a new one. Dirty state compares the current settings to the selected
  record, never to a shadow copy.
- A useful name must contain a letter or digit. Punctuation alone is not enough:
  some trial fonts use "." plus DEL or other control characters, which render as
  a bare dot. With the naming setting on, the snapshot substitutes the file
  stem, then full name, then PostScript name; punctuation-only styles become
  `Regular`. This happens at snapshot build, so the setting applies without a
  rescan.
- A family whose name has no Latin letters displays
  `<local name> (<Latin label>)` and sorts under the Latin label. The label is
  the PostScript family prefix, then the file stem. The grouping key stays the
  local name.
- The sidebar folder tree is built from indexed paths, not a directory walk.
  Roots are added folders; children exist only where a file lives. Selection is
  a path prefix, so a collapsed root and an expanded child stay consistent.
- Individual file adds group by parent directory. Files already inside an
  indexed folder join that folder (longest matching path); other files get a
  one-time folder for their directory so the tree can reveal them. A Finder
  drop may contain folders and files.
- The Warnings page reports live duplicate PostScript names and files whose
  status is not `ok`. Duplicates only count `ok` files; a missing duplicate is
  noise. Warning types are collapsed `DisclosureGroup`s so the page reads as a
  summary; nothing on the page deletes or moves a file.
- System fonts are faces under `/System/Library/Fonts`. `/Library/Fonts` and
  `~/Library/Fonts` are user-installed, not system. The `showSystemFonts`
  setting (default on) hides a family only when every face is a system font.
- Apple prefixes private system family names with a dot. Strip that leading dot
  for display only when the whole family is a system family; never change the
  grouping key.
- Coverage is a second, manual pass. `cmap` formats 4 and 12 produce a script
  mask plus exact codepoint ranges per face (`face.script_mask`,
  `face.coverage_ranges`; either NULL means pending). It is not part of the main
  scan because reading the whole library again is expensive and cloud folders can
  block. `CoverageIndexer` batches it; the filter popover owns the Index Coverage
  action.
- Character filters load ranges lazily on first use and cache them; the cache is
  dropped when the library or coverage changes. Ranges are treated as coverage,
  so a sparse format 4 segment can over-report. Say so in the UI before
  promising exactness.
- Script-aware previews prefer a distinctive script (CJK, Hangul, Kana, Arabic,
  Hebrew, Devanagari, Thai) when the family covers it. Latin and Latin-plus-
  Greek/Cyrillic families keep the user's sample.
- Cloud file providers are not ordinary folders. Scanning an online-only
  Dropbox root stalled indefinitely because reading a placeholder blocks on the
  provider. Detect dataless files before opening them, skip and report them, and
  never scan a provider root by default.
- Paths must be canonical before they are compared. Foundation does not resolve
  the `/var` firmlink (`resolvingSymlinksInPath` leaves it), but FileManager and
  FSEvents return `/private/var/...`. The scanner uses `realpath`; without it
  every watched-file delta looks like a new file.
- The watcher reports `(root, changed path)` pairs. A file event triggers a
  delta scan of those paths only; a directory event triggers a folder scan. A
  five-minute sweep covers missed events. There is no event replay across app
  launches: the launch rescan is the recovery path.
- Folder labels live in `folder.display_name`. Renaming is a label change and
  must never touch the directory on disk.
- Turning watching on is a full rescan and is confirmed by the user first.
  Turning it off stops the watcher and keeps every file and activation row.
- Removing a folder deactivates its active faces before deleting rows; otherwise
  fonts stay registered with no journal entry to turn them off.
- `urfonts-cli split-folder <old> <child>...` moves existing file rows into
  subfolders by path prefix, then deletes the old folder. Use it instead of a
  rescan when a provider root was indexed and should become its subfolders.

### Google Fonts

- Catalog comes from `fonts.google.com/metadata/fonts` (public, no key);
  downloads are TTF files from the official `google/fonts` GitHub repository.
  The GitHub tree is one request and is cached with the catalog for a week.
- Downloads live in `Application Support/Ur Fonts/GoogleFonts/Fonts`, indexed as
  a `.managed` folder that never appears in the sidebar. Licenses are saved next
  to the fonts.
- Settings export excludes managed folders; Google downloads are re-fetchable,
  not user configuration.
- GitHub's unauthenticated limit is 60 requests/hour. Refresh uses the cache
  unless forced; do not fetch the tree per family.

### Headless testing

- `NSApp.setActivationPolicy(.prohibited)` before any window exists.
- Never call `NSApp.activate`, `makeKeyAndOrderFront`, `orderFrontRegardless`, or
  `NSRunningApplication.activate`.
- The harness asserts `NSApp.isActive == false` as a test step. That assertion is
  the guarantee, not a comment.
- Drive the production command seam (`AppCommand` to `AppModel.perform`), never a
  test-only path. A green run must prove the wiring the UI uses.
- Render with `ImageRenderer` when a window is unnecessary, or an `NSHostingView`
  bitmap when view lifecycle matters. No event loop needed.
- Artifacts go to `$TMPDIR/urfonts-headless/<run>/`: log, JSON state, PNGs.
- Unit and core tests use `swift test` and never launch the app.

### Documents

Planned. Nothing in this section is implemented yet.

- Document reading is preflight only: read the file, list fonts, activate on user
  action. No app control, no Apple Events, no plug-ins.
- Sources of font names: IDML `Resources/Fonts.xml`, INDD and AI XMP `stFnt`,
  PDF `BaseFont`, PSD text layers.
- Preflight never writes into the document's folder.

### Packaging

- SwiftPM executable plus `scripts/build-app.sh`. No Xcode project.
- Bundle is `Ur Fonts.app`; executable is `UrFonts`; bundle ID
  `com.10k24.urfonts`. The dev build script assembles `build/Ur Fonts.app` and
  ad-hoc signs it; notarization comes at release.
- A bare SwiftPM binary launches as `BackgroundOnly`; always package the bundle
  before judging activation, menus or focus.
- Developer ID, hardened runtime, notarized. GRDB is the only dependency today;
  Sparkle is planned for release. One dependency for updates, one for the
  database remains the target.
- Apache-2.0. MIT-derived code keeps its notice in `NOTICE`.

## Architecture / file layout

```
Sources/UrFontsCore          no UI, every public type Sendable
  FontKit/                   head, hhea, OS/2, name, fvar
                             (STAT, cmap, GSUB planned)
  Scanner/                   walk, stamps, parallel parse, delta sets
  Watch/                     FSEvents per folder, fallback sweep
  Catalog/                   GRDB store, migrations, snapshot, search index
  Activation/                engine, registrar protocol, journal, reconcile
  Coverage/                  batched cmap script index (manual)
  GoogleFonts/               catalog, tree, downloads
  Preview/                   FontLoader LRU, CTLine and tile drawing
  Metrics/                   planned: contrast, classification, coverage
  Documents/                 planned: IDML, INDD, AI, PDF, PSD extraction
  Sync/                      planned: user-data export and merge
Sources/UrFonts              SwiftUI app, MainActor by default
  App/                       commands, model, headless harness
  Sidebar/ Browser/ FontPage/ Info/ Windows/ Settings/ Components/
                             (Info, Windows, Settings, Components planned)
Sources/urfonts-cli          index, search, folders, activation, headless
BENCH.md                     planned: competitor and regression measurements
Tests/UrFontsCoreTests       parser, scanner, catalog, activation with fakes
Tests/UrFontsSnapshotTests   planned: ImageRenderer golden images
macos/                       Info.plist
Resources/                   planned: character sets, language data
scripts/                     build-icons.sh, build-app.sh, release, make-dmg,
                             test, bench (release scripts planned)
design/icon/                 Icon Composer source plus legacy 1024 PNG
tools/                       fixture generator
docs/                        planned: ARCHITECTURE.md, ADOBE.md
```

Rules:

- State lives in structs, behavior as methods. No module-level mutable globals.
- `AppModel` owns state; views render and send commands. One command seam.
- Feature code goes in a deep module in `UrFontsCore`; the app layer is UI and
  orchestration only.
- Any code that walks the library or reads a file runs off the main actor.

## Data model

Target model. Only `folder`, `file`, `face` and `activation` exist today, and
their columns are narrower than this sketch. Add a migration before relying on a
field listed here that the store does not have.

```
folder(id, path, kind static|watched, added_at, last_scan_at, last_event_id, available)
file(id, folder_id, path, volume_id, inode, size, mtime_ns, parse_version,
     face_count, status ok|missing|damaged, first_seen, last_seen)
face(id, file_id, face_index, postscript_name, family_name, style_name, full_name,
     localized_names_json, weight_class, width_class, is_italic, is_variable,
     axes_json, named_instances_json, upem, x_height, cap_height, ascender,
     descender, panose, vendor_id, designer, license_url, embedding,
     feature_tags, coverage_bloom, metrics_json, tags_auto)
family(id, display_name, sort_name, classification, foundry, year)
collection(id, name, parent_id, sort)
collection_item(collection_id, face_id)
tag(id, name, color, kind user|auto)
face_tag(face_id, tag_id)
note(face_id, body), rating(face_id, stars)
sample(id, name, text, fg_color, bg_color, size, weight, line_height,
       alignment, script, sort)
license(face_id, kind, seats, expires, vendor, notes)
activation(face_id, scope, activated_at, source manual|temporary|document)
```

Paths are mutable identifiers, never primary keys. User data is keyed by UUID so
a moved library keeps its tags.

## Performance budget

Measured on the large fixture library. These are gates, not aspirations.

| Metric | Target |
|---|---|
| Warm launch to first painted row | under 400 ms |
| Cold index, full fixture | under 30 s |
| Single-file delta, end to end | under 50 ms |
| Search keystroke to filtered list | under 16 ms |
| List scroll, p99 frame | under 8.3 ms |
| Grid scroll | at least 60 fps |
| Steady RSS while scrolling | under 300 MB, flat with library size |
| Font files read at warm launch | zero |
| Activate one family to confirmed | under 250 ms |

## Swift conventions

- 4-space indentation, 100 column soft limit, no trailing whitespace. The limit
  is not enforced yet; existing outliers are fixed as files are touched.
- Swift 6.2, strict concurrency. `UrFontsCore` types are `Sendable`; mutable
  stores and engines are actors. The app target defaults to `MainActor`.
- `camelCase` functions and properties, `PascalCase` types, lower-case file names
  grouped by module.
- Prefer `let`, early returns, and explicit optionals. No force unwrap on paths
  that can fail. Force unwrap only for provably impossible states, with a comment.
- Minimal `try/catch`. Errors that can be designed out are designed out; errors
  that matter propagate to one boundary that logs and shows one message.
- Comments explain why and what the interface promises, not what the line does.
- No new dependency without a note in this file and a reason the standard library
  or an existing dependency cannot do it.
- American spelling.

## Design principles

- Code is a liability. The smallest thing that fully works is the thing to ship.
- Deep modules: simple interface, rich implementation. `Catalog`, `Activator`,
  `Scanner`, `FontLoader` hide all their machinery behind a few methods.
- One question, one owner. Activation state has one owner. Row geometry has one
  owner. Search filtering has one owner.
- Pull complexity down. Views never branch on font format, scope, or file state.
- Reuse before building. Check Foundation, CoreText, AppKit, GRDB and Cicero
  before writing a parser, cache, or collection type.
- Trust ground truth. Read the real scope from fontd, the real file stamps from
  the file system, the real frame times from Instruments or signposts.

## Guardrails

- Never run `git`. Staging is the user's job. Do not describe the repo state.
- Never delete files. Retiring a module is the user's call.
- Never edit `todo.md`.
- Use the edit tool for source edits, not shell text replacement.
- Verify by execution. If a claim cannot be measured, say so instead of asserting.
- If tests fail, fix them or record the failing case in `OPEN_ISSUES.md`. Do not
  proceed on a red gate.
- Do not invent benchmark numbers.
- Do not modify font files, their metadata, their timestamps, or their folders.
- No telemetry. Network only for Sparkle and explicit Google Fonts downloads.

## Testing

- Unit tests colocated by module in `Tests/UrFontsCoreTests`.
- The scanner and catalog are tested against the generated large fixture, not a
  hand-written sample of ten.
- Activation has two layers: a fake registrar for state machine tests, and an
  opt-in real test that registers and unregisters one known font.
- Headless scenarios cover the app wiring. A scenario must fail when the command
  seam is sabotaged.
- Golden images cover previews at fixed scale, light and dark, Latin and CJK.

### Traps that produce false green

- A focus test that asserts nothing about focus proves nothing. Assert
  `NSApp.isActive == false` explicitly.
- A benchmark that runs in Debug is not the build users run. Measure Release.
- A tiny fixture does not exercise the full-scale row path.
- A sabotage that does not compile reads as zero failures. Every sabotage must
  prove the suite still builds.
- A test that reads a snapshot instead of the drawn frame verifies the snapshot.
  Assert on what the renderer produced.
- A gate tuned to pass is not a gate. Fix the code or change the budget in this
  file, with a reason.

## Reference

- CoreText font registration:
  `CTFontManagerRegisterFontURLs`, `CTFontManagerUnregisterFontURLs`,
  `CTFontManagerGetScopeForURL`, `CTFontManagerCopyRegisteredFontDescriptors`,
  `CTFontManagerEnableFontDescriptors`, `CTFontManagerCreateFontDescriptorsFromURL`,
  `kCTFontManagerRegisteredFontsChangedNotification`.
- FSEvents: `FSEventStreamCreate` with `UseCFTypes | FileEvents | WatchRoot |
  NoDefer`, persisted `lastEventId`.
- OpenType: Microsoft OpenType spec for `OS/2`, `fvar`, `STAT`, `cmap`, `GSUB`.
- Prior art, MIT, study before writing new code: Cicero
  <https://github.com/opr-inzn/cicero> (`ActivationEngine`, `FontLoader`,
  `FolderWatcher`, `FontFileReader`, `LocalizedNames`, `ScriptSample`,
  `CoverageIndex`, `LetterMeasurements`).
- Verification notes for activation behavior are recorded in `OPEN_ISSUES.md`
  Phase 0 as they are measured.
