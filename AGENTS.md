# AGENTS.md - Ur Fonts

## Mission

Build a native macOS font manager for very large libraries. Target machine holds
about 23,000 font files. FontBase is the incumbent; modern managers lag when
scrolling that library. Ur Fonts must scroll smoothly, activate fonts in place,
never copy or move a user's font files, and keep a static or watched folder in
sync with deltas instead of rescans.

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
- No Windows or Linux.
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
- Registration is per-file: about 2 ms per font once warm (1,000 fonts in about
  2 s), and the first call in a process pays a fontd start cost. Measure with
  `scripts/register-spike.sh`; do not copy numbers from here.
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

- The browser is family-first. 23,000 files collapse to a few thousand rows.
- Rows have fixed height. Total content height is `count * rowHeight`. No
  self-sizing rows, no layout pass per row.
- One `CTLine` per row drawn into a SwiftUI `Canvas`. No TextKit, no
  `NSAttributedString`, no `Text` inside rows. Truncate with
  `CTLineCreateTruncatedLine`. Oversize the canvas to the glyph ink bounds so
  descenders are not clipped.
- Rows conform to `Equatable` and use `.equatable()`.
- Nothing walks the library or reads a file inside `body`. Views read precomputed
  values from the catalog snapshot.
- `FontLoader` is an actor with an LRU of about 256 `CTFont` objects, prefetch of
  the visible window plus 50 at bounded concurrency, and `F_RDADVISE` read-ahead.
  Skip prefetch above a scroll velocity threshold.
- Phase 0 measured both containers with `UrFonts --headless list-spike`. The
  fixed-height SwiftUI lazy stack wins on p99 and keeps only visible rows alive.
  `NSTableView` created row views for every jump and exceeded the frame budget.
  Keep the list behind a small container type, but switch it only with a new
  measurement, not an opinion. The spike does not capture SwiftUI's Core
  Animation commit, so Phase 2 re-measures the real browser with signposts.
- Grid tiles are drawn live; only a bounded `NSCache` of recent tiles is kept.
  No per-font preview files on disk by default.
- The browser is `ScrollView` + `LazyVStack` with 64 pt rows and an `@State`
  `LoadedFont` per visible row, loaded through `FontLoader.shared`. A row's
  `.task(id:)` keys on path and face index only; size changes never reload.
- `--headless browser` renders the real window offscreen, captures it with
  `cacheDisplay`, and proves the process never activates. Use it to check layout
  and glyph orientation; use a real window for frame timing. `--grid` and
  `--query` select the other view and a search term.
- Sidebar selection uses an enum, never an optional ID. A `nil` tag is SwiftUI's
  "no selection" and makes the All Fonts row unselectable.
- Detail content and the status bar are a pinned `VStack`. `safeAreaInset` lets
  the footer float above short states such as no search results.
- Preview size is derived from one cached CTFont per face with
  `CTFontCreateCopyWithAttributes`. Never key a font load on point size: that
  reopens the file and blanks the row on every slider tick.
- Grid tiles fit the whole sample by shrinking it. List rows truncate with an
  ellipsis. Both inset horizontally so italic overhangs survive.
- The family sheet renders the large preview through `PreviewLine.drawFitted`
  and derives axis variations with `CTFontDescriptorCreateCopyWithAttributes` +
  `kCTFontVariationAttribute`. `CTFontCreateCopyWithAttributes` takes a
  descriptor, not an attribute dictionary.
- The glyph map comes from `CTFontCopyCharacterSet` over the face's own cmap,
  scanning code points up to U+2FFFF and skipping controls. Nothing is indexed;
  it runs when the sheet opens and works for inactive fonts.

### Indexing

- Read each font file once. One pass yields names, axes, metrics, coverage and
  the descriptors preview later reuses.
- CoreText gives localized names and descriptors. A small SFNT reader supplies
  what CoreText does not expose: PANOSE, `fvar` axes, `STAT`, `cmap`, `GSUB`
  feature tags, raw metrics.
- Change detection is `path -> (inode, size, mtimeNanos, parseVersion, status)`.
  FSEvents gives a path, so a delta costs one `stat`, not a rescan.
- Parse in parallel, bounded by `activeProcessorCount`, commit in one transaction.
- Advanced metrics (x-height ratio, contrast, classification, embeddings) are a
  lazy background pass after the first index, cached, never blocking the browser.
- The snapshot is the warm-launch cost. One joined query, positional row reads,
  memoized family keys, lowercased search folds. Measure with
  `urfonts-cli stats` before adding a cache.
- Search covers family, styles and PostScript names. Family grouping uses a
  case- and diacritic-folded key; search folds only lowercase because it runs on
  every style and PostScript name.
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
- `urfonts-cli split-folder <old> <child>...` moves existing file rows into
  subfolders by path prefix, then deletes the old folder. Use it instead of a
  rescan when a provider root was indexed and should become its subfolders.

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
- Developer ID, hardened runtime, notarized, Sparkle. One dependency for updates,
  one for the database.
- Apache-2.0. MIT-derived code keeps its notice in `NOTICE`.

## Architecture / file layout

```
Sources/UrFontsCore          no UI, every public type Sendable
  FontKit/                   SFNT reader: head, hhea, OS/2, name, fvar, STAT,
                             cmap, GSUB tags
  Scanner/                   walk, stamps, parallel parse, delta sets
  Watch/                     FSEvents per folder, fallback sweep
  Catalog/                   GRDB store, migrations, snapshot, search index
  Activation/                engine, registrar protocol, journal, reconcile
  Preview/                   FontLoader LRU, CTLine and tile drawing
  Metrics/                   outline measurement, classification, coverage
  Documents/                 IDML, INDD, AI, PDF, PSD font extraction
  Sync/                      user-data export and merge
Sources/UrFonts              SwiftUI app, MainActor by default
  App/                       commands, model, headless harness
  Sidebar/ Browser/ FontPage/ Info/ Windows/ Settings/ Components/
Sources/urfonts-cli          index, search, activate, headless, bench
Tests/UrFontsCoreTests       parser, scanner, catalog, activation with fakes
Tests/UrFontsSnapshotTests   ImageRenderer golden images
macos/                       Info.plist template, entitlements, icon
Resources/                   character sets, language data, classification data
scripts/                     build-app.sh, release.sh, make-dmg.sh, test.sh, bench.sh
tools/                       fixture generator, snapshot diff
docs/                        ARCHITECTURE.md, ADOBE.md (why no integration)
```

Rules:

- State lives in structs, behavior as methods. No module-level mutable globals.
- `AppModel` owns state; views render and send commands. One command seam.
- Feature code goes in a deep module in `UrFontsCore`; the app layer is UI and
  orchestration only.
- Any code that walks the library or reads a file runs off the main actor.

## Data model

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

Measured on the target library of about 23,000 files. These are gates, not
aspirations.

| Metric | Target |
|---|---|
| Warm launch to first painted row | under 400 ms |
| Cold index, 23,000 files | under 30 s |
| Single-file delta, end to end | under 50 ms |
| Search keystroke to filtered list | under 16 ms |
| List scroll, p99 frame | under 8.3 ms |
| Grid scroll | at least 60 fps |
| Steady RSS while scrolling | under 300 MB, flat with library size |
| Font files read at warm launch | zero |
| Activate one family to confirmed | under 250 ms |

## Swift conventions

- 4-space indentation, 100 column soft limit, no trailing whitespace.
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
- The scanner and catalog are tested against the generated 23,000-file fixture,
  not a hand-written sample of ten.
- Activation has two layers: a fake registrar for state machine tests, and an
  opt-in real test that registers and unregisters one known font.
- Headless scenarios cover the app wiring. A scenario must fail when the command
  seam is sabotaged.
- Golden images cover previews at fixed scale, light and dark, Latin and CJK.

### Traps that produce false green

- A focus test that asserts nothing about focus proves nothing. Assert
  `NSApp.isActive == false` explicitly.
- A benchmark that runs in Debug is not the build users run. Measure Release.
- A fixture with ten files does not exercise the 23,000-row path.
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
