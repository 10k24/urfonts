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
  before activating both. The UI disables every non-active face whose PostScript
  name is already active and names the active file path.
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
  `~/Library/Fonts` are installed, not ours, but only while the file exists.
  Check `fileStatus == "ok"` first: a missing FontBase copy must show as missing,
  not installed. Skip installed files in the engine and show a gray checked
  square at the same size as the activation square; never unregister them.
- Toggling is family-level over unique styles, not files. Faces collapse by a
  style key (normalized style name, weight, width, italic). One preferred file
  per style is chosen deterministically: readable, then non-WEB, then OTF/OTC,
  then TTF, then path order. The family checkbox activates or deactivates every
  preferred style. Alternate files stay in the sheet and are disabled as
  alternates, never silently activated alongside the preferred file.
- Duplicate PostScript names across different style groups still warn and block:
  the sheet names the active owner path. A same-style OTF/TTF pair does not get
  a family-level fallback; the preferred file is the one that activates.
- Name tables that contain only placeholder identity (`false`, `none`, `null`,
  `undefined`, `untitled`, `nil`) are not faces. Fontshare WEB exports are the
  known case; filter them when building the snapshot so they cannot create a
  fake family or duplicate style groups.
- The representative face is file-driven only: preferred style file, readable,
  upright, weight closest to 400, then path. It never consults activation state
  or sidebar selection, so activating a family cannot change its preview. Never
  select a missing file for the row or sheet preview.
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
  No per-font preview files on disk by default. Columns follow the window width
  with a 280 pt minimum tile and a hard cap of four. Tiles are 240 pt tall with a
  140 pt preview area.
- The browser is `ScrollView` + `LazyVStack` with uniform rows. Base heights are
  128 pt normally, 176 pt for mid-length samples and 224 pt for the full alphabet
  preset (four lines). Above the base, the height is estimated from the measured
  preview width and sample size: one line gets 8 pt of padding, wrapped lines get
  12 pt, quantized to 8 pt steps. A single large line therefore does not carry a
  second line's empty space. The line budget is 2 lines up to 48 characters and
  4 above; it is not derived from the dynamic height. Each row has an `@State`
  `LoadedFont`, loaded through `FontLoader.shared`. A row's `.task(id:)` keys on
  path and face index only; size changes relayout but never reload the font.
- List rows wrap with a typesetter and measure line ink bounds, so display faces
  with ink past their metrics do not overlap. Text space is y-up: a line's ink
  ascent is `bounds.maxY`, descent is `-bounds.minY`. Getting that backwards
  makes text grow upward when the size increases.
- Wrapped text centers when it fits and pins to the top (6 pt) when it does not,
  so overflow clips at the bottom rather than above the row. Grid tiles stay
  single-line: they honor the sample size, shrink only when one line is taller
  than the tile, and truncate horizontally. Truncation uses ASCII `...` because
  some display fonts map U+2026 to a decorative or "NO GLYPH" stamp.
- `PreviewLine.Layout` is the only owner of line breaks and vertical placement.
  A row caches it per face, sample, size and measured width; the Canvas draws
  that layout. The family metadata's first text baseline is aligned to the first
  preview line through the `.previewBaseline` alignment guide, not by centering
  two independent stacks.
- Activation controls, hit targets and the VF badge all read
  `PreviewMetrics.controlScale`. Change that one value to resize them together;
  do not reintroduce size literals in `ActivationDot`, `FaceActivationControl`
  or row accessories.
- App appearance is a user setting (System default, Light, Dark) persisted as
  `urfonts.appearance`. `AppModel.applyAppearance` is the only writer to
  `NSApp.appearance`; per-window `preferredColorScheme` would leave open/save
  panels and menus on the system setting. The Settings scene is `SettingsView`
  (appearance section plus the ignored-folder section).
- The preview size slider spans 12-108 pt with the 42 pt default at the visual
  midpoint. `PreviewSizeScale` owns that mapping (12-42 lower half, 42-108 upper
  half); `AccentSlider` only renders it and rounds to whole points. A linear
  slider puts 42 at 31% travel, which reads as the low end.
- Sorting uses the displayed family name, after system dot stripping, not the
  raw grouping key. Otherwise Apple's dot-prefixed names sort before letters.
- Presets live in `PreviewPreset` and only change the sample text. Size is a
  separate control in the status bar and never tied to a preset; its range is
  12-108 pt. It cannot live in the toolbar: macOS 26/27 draws toolbar sliders
  untinted (gray) even with `.tint` or a native `trackFillColor`, while content
  sliders keep the accent.
- Previews never use CoreText font fallback. `PreviewLine` draws primary runs
  normally and replaces every fallback run with the primary font's glyph 0
  (`.notdef`) at the run's positions. An empty or self-only cascade list does not
  suppress CoreText fallback; do not rely on it. Custom text with unsupported
  characters shows tofu, never another font.
- `--headless browser` renders the real window offscreen, captures it with
  `cacheDisplay`, and proves the process never activates. Use it to check layout
  and glyph orientation; use a real window for frame timing. `--grid` and
  `--query` select the other view and a search term; `--warnings` opens the
  Warnings page and waits for its rows; `--active` selects the Active list;
  `--google` selects the Google Fonts host. `--family NAME` picks the detail
  page family; `--text TEXT` overrides the preview sample. `--headless add-files`
  exercises the individual file add against a temporary database,
  `--headless ignore-folder` exercises folder exclusion and missing-entry
  cleanup against a temporary database, `--headless settings` renders the
  Settings window with the real ignore list, and `--headless google-detail`
  renders a host family sheet from the cached Google catalog.
- Sidebar selection uses an enum, never an optional ID. A `nil` tag is SwiftUI's
  "no selection" and makes the All Fonts row unselectable.
- Detail content and the status bar are a pinned `VStack`. `safeAreaInset` lets
  the footer float above short states such as no search results. Footer status
  messages are sentence case; the right side holds only preview size.
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
- Grid tiles honor the sample size, shrink only for tile height and truncate
  horizontally. List rows wrap and truncate with ASCII periods. Both inset
  horizontally so italic overhangs survive.
- The family sheet renders the large preview through `PreviewLine.drawTruncated`
  at a fixed point size and derives axis variations with
  `CTFontDescriptorCreateCopyWithAttributes` + `kCTFontVariationAttribute`.
  `CTFontCreateCopyWithAttributes` takes a descriptor, not an attribute
  dictionary.
- Family detail lists every face's absolute path and marks a shared PostScript
  name with an orange triangle plus a note. Filenames are not identity: a
  mislabeled file still belongs to the family named in its `name` table.
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

- Read each font file once. The main parser reads `head`, `hhea`, `OS/2`, `name`
  and `fvar`. `STAT` is planned. `cmap` coverage is a separate manual pass;
  GSUB/GPOS feature tags are read on demand. Language filters wait for a
  language-level coverage pass.
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
  survives an offline volume. Counts are cached per collection. The collection
  menu activates or deactivates all stored faces in bulk. Collections are always
  listed alphabetically (`localizedStandardCompare`, creation time as the
  tie-break): the sidebar has no drag reordering, so name order is the contract.
- Active is a selection scope over the activation journal, not a folder. It
  lists families with any active face and counts active faces; changing the
  journal invalidates the visible cache. Installed system fonts never appear.
- Search uses a lowercased UTF-8 blob per family, not `String.contains`, so a
  keystroke scans bytes instead of graphemes.
- Settings export is `LibraryConfiguration`, versioned JSON. Collections store
  PostScript names, not face IDs, so a file survives a different folder layout.
  Version is checked on import; never silently accept a newer file. Ignored
  folder paths travel with the settings and are re-applied on import.
- Sidebar counts are fonts (faces), matching All Fonts. File counts belong in
  tooltips; file and face counts differ for TTC/OTC files.
- User-facing text says "fonts", never "faces". A face is the stored unit; a
  font is what the user selects and previews. "Face" stays in the schema and
  code. The window subtitle counts fonts: the denominator is the selected
  sidebar item's faces (library total only for All Fonts), and the numerator is
  the faces in visible rows after search, filters and the system toggle. The
  footer carries the latest action message and the preview size, not counts.
  Scope counts use paths and collection membership, never the sum of a family's
  faces, because a family can span folders.
- Status and warning copy separates a folder name or path from the sentence with
  a colon: `Scanning: Name…`, `Removed: /path`, `Ignored folder: Name`. The name
  is a value, not part of the prose.
- New user-facing UI copy goes through `Messages` in the app target. Keys are
  dotted feature names; defaults live beside the key so localization can be added
  without touching views.
- A saved sample is a snapshot of preview text, size and colors. Selecting one
  applies it; Update overwrites the selected sample; Save as Sample always
  creates a new one. Dirty state compares the current settings to the selected
  record, never to a shadow copy. The selected sample ID is remembered in
  `urfonts.selectedSampleID`, so the preview returns to that text on relaunch.
- A useful name must contain a letter or digit. Punctuation alone is not enough:
  some trial fonts use "." plus DEL or other control characters, which render as
  a bare dot. With the naming setting on, the snapshot substitutes the file
  stem, then full name, then PostScript name; punctuation-only styles become
  `Regular`. This happens at snapshot build, so the setting applies without a
  rescan.
- Families group by metadata, never by filename. A file can carry another font's
  name table; show each face's absolute path in the detail page and mark shared
  PostScript names. Do not treat differing filenames as a cache leak or rewrite
  the font.
- A family whose name has no Latin letters displays
  `<local name> (<Latin label>)` and sorts under the Latin label. The label is
  the PostScript family prefix, then the file stem. The grouping key stays the
  local name.
- The sidebar folder tree is built from indexed paths, not a directory walk.
  Roots are added folders; children exist only where a file lives. Selection is
  a path prefix, so a collapsed root and an expanded child stay consistent.
  Hosts precede Folders in the sidebar. Library rows are All Fonts, Active,
  Warnings. Ignored subtrees are kept as rows with an
  `eye.slash` icon so an exclusion is visible and reversible.
- Nested roots are allowed. The deepest indexed root owns each file: scanning a
  nested root adopts rows from every ancestor, and scanning a parent skips
  subtrees owned by a deeper root. Removing a nested root re-parents its rows to
  the deepest remaining ancestor, or deletes them if none. Adding a folder that
  is already covered, contained by, or overlapping another root warns first but
  still proceeds.
- Ignoring a folder stores its resolved path in `excluded_path`, deactivates and
  deletes the file rows under it, and makes the scanner skip that subtree. Font
  files are never touched. The row stays in the sidebar; Stop Ignoring rescans
  every affected root. This is how a manager cache nested inside a watched folder
  is hidden without special-casing a directory name. Like removal, the exclusion
  aborts if a deactivation is not confirmed.
- Settings → Ignored Folders is the global editor for the same list: add via
  panel, remove to restore, with help text. Font-manager caches come from
  `FontManagerCacheDetecting` implementations in `UrFontsCore/FontManagers`.
  FontBase detects its config folder plus `~/Library/Fonts/FontBase` and
  `/Library/Fonts/FontBase`, and the suggestion disappears once the cache is
  ignored or covered by an ignored parent. Add new managers by adding a detector
  to `FontManagerDetectors.all`; the settings UI stays manager-agnostic.
- The sidebar is a native `List` with `OutlineGroup`. Drag reordering was
  removed: `List`/`OutlineGroup` swallow row drag and drop on macOS. Folder
  reorder is the context-menu Move Up/Move Down actions over `sort_order`.
- Sidebar root order is `folder.sort_order`. New folders get `max + 1`, so they
  land at the bottom. The managed Google folder sits after the visible roots
  and stays hidden.
- A clean install seeds `/Library/Fonts`, `~/Library/Fonts` and
  `/System/Library/Fonts` in that order, watched. Existing installs promote those
  paths to the top and keep them watched until the user opts out.
- Individual file adds group by parent directory. Files already inside an
  indexed folder join that folder (longest matching path); other files get a
  one-time folder for their directory so the tree can reveal them. A Finder
  drop may contain folders and files.
- The Warnings page reports live duplicate PostScript names and files whose
  status is not `ok`. Duplicates only count `ok` files; a missing duplicate is
  noise. Warning types are collapsed `DisclosureGroup`s so the page reads as a
  summary. Remove Missing Entries deletes only the stale rows, after
  confirmation, because collection membership goes with them. No file on disk
  is deleted or moved.
- System fonts are faces under `/System/Library/Fonts`. `/Library/Fonts` and
  `~/Library/Fonts` are user-installed, not system. The `showSystemFonts`
  setting (default on) hides a family only when every face is a system font.
- Apple prefixes private system family names with a dot. Strip that leading dot
  for display only when the whole family is a system family; never change the
  grouping key.
- Coverage is a second, manual pass. `cmap` formats 4 and 12 produce a script
  mask, a full-sample preview mask, and exact codepoint ranges per face
  (`face.script_mask`, `face.preview_mask`, `face.coverage_ranges`; script/ranges
  NULL means pending). `preview_mask` is set only when every scalar of that
  script's sample is covered. It is not part of the main scan because reading the
  whole library again is expensive and cloud folders can block.
  `CoverageIndexer` batches it; the filter popover owns the Index Coverage
  action.
- Character filters load ranges lazily on first use and cache them; the cache is
  dropped when the library or coverage changes. Ranges are treated as coverage,
  so a sparse format 4 segment can over-report. Say so in the UI before
  promising exactness.
- Script-aware previews prefer a distinctive script (CJK, Hangul, Kana, Arabic,
  Hebrew, Devanagari, Thai) only when a readable face covers every character of
  that script's sample (`preview_mask`). Partial coverage keeps the user sample.
  The sample is chosen from the face being drawn, never from a family-wide union:
  a family can mix a Latin-only preferred file with an installed face that covers
  Devanagari, and the union would select a sample the preview file cannot render.
  Sample text enters the UI only through `CatalogFace.previewText(userText:)`.
  `script_mask` remains the any-coverage filter; missing faces contribute to
  neither mask. This prevents CoreText fallback from selecting an Arabic sample
  the font only partly covers.
- Cloud file providers are not ordinary folders. An online-only Dropbox root
  stalled indefinitely because reading a placeholder blocks on the provider.
  Before opening a font, check File Provider dataless metadata and iCloud
  download status. Skip placeholders with a `skippedCloud` scan count and never
  create a row for a file that was never indexed; online-only files are a normal
  provider state, not a warning. If an indexed file becomes online-only, keep its
  faces, set status `cloud` and show the style as unavailable in the font sheet;
  no Warnings entry and no badge. Cloud timeouts and network failures are
  classified by `CloudAccess` and surface as a retryable cloud error, never as a
  damaged font. A materialized file is indexed by the next event or sweep. Keep
  provider roots opt-in and never scan a provider root by default.
- Paths must be resolved before they are compared. Foundation does not resolve
  the `/var` firmlink (`resolvingSymlinksInPath` leaves it), but FileManager and
  FSEvents return `/private/var/...`. User boundaries (folder add, ignore list,
  settings import, CLI arguments) use `LibraryPath.resolve`, which expands `~`,
  trims whitespace and calls `realpath`. Scanner and watcher store canonical
  paths. `LibraryPath.relation` is the only owner of same/ancestor/descendant
  checks; do not compare with ad-hoc string prefixes. Without this every
  watched-file delta looks like a new file and `~/Fonts` duplicates `/Users/...`.
- The watcher reports `(root, changed path)` pairs. A file event triggers a
  delta scan of those paths only; a directory event triggers a folder scan. A
  five-minute sweep covers missed events. There is no event replay across app
  launches: the launch rescan is the recovery path.
- The toolbar reload is scope-aware. A selected folder scans that root; a
  selected subfolder scans only that subtree through `scan(subtree:)`; other
  scopes keep the all-folders action. A scan with no changed rows skips the
  snapshot rebuild entirely.
- AppModel owns exactly one `LibraryScanner` actor. Watcher deltas, sweeps,
  rescans, folder adds, font adds and Google indexing all go through it. Never
  create a scanner per call: two actors can read the same pre-insert state and
  race on `file.path`.
- `LibraryDatabase.apply` falls back to a global path lookup before inserting.
  A file already owned by another folder is moved and its activation rows are
  preserved, so an overlapping scan cannot raise a unique-constraint error.
- Raw errors never reach the UI. `AppModel.report` logs the real error and
  `LibraryErrorText` maps it to safe text; alerts and footers must never contain
  SQL, table names, bindings or `localizedDescription` from the database.
- Folder labels live in `folder.display_name`. Renaming is a label change and
  must never touch the directory on disk.
- Turning watching on is a full rescan and is confirmed by the user first.
  Turning it off stops the watcher and keeps every file and activation row.
- Removing a folder deactivates its active faces before deleting rows, and
  aborts if fontd does not confirm; otherwise fonts stay registered with no
  journal entry to turn them off.
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
- The catalog is the Hosts → Google Fonts sidebar selection, rendered inline.
  There is no toolbar globe or catalog sheet; a family sheet lists every style.
  Downloaded families join the same library and Active scopes as local fonts.
- Hosts use the global toolbar search and view picker, never a local field or
  header. The query persists across sidebar changes but is evaluated against the
  current context: the Google catalog in Hosts, the library snapshot everywhere
  else. Active still includes active Google downloads. Hosts render through the
  same `FamilyRow` / `FamilyTile` and grid layout as the library.
- Undownloaded host rows fetch a tiny TTF subset from the Google Fonts CSS API
  (`css2?...&text=<configured sample>`) into
  `Caches/Ur Fonts/HostPreviews`. This is preview-only: it never enters the
  managed library, activation journal or settings export. The subset includes
  the truncation period so clipped tiles do not show `.notdef`. Downloaded
  families use their real managed face instead.
- Host rows use the library activation controls, never a download-only button.
  An open square downloads and activates; a checked square deactivates. Styles
  are requested individually; variable styles share their owning file's state.
  `HostControlPhase` and `HostActivationControl` are provider-neutral so future
  hosts reuse the same rows, progress ring and state machine.
- The family sheet lists every Google style with the same
  `FaceActivationControl` and `FontFilePreview` as library files. Variable
  families map several weights to one Roman/Italic file, so those rows share
  activation state and say so in the tooltip. Previews are per-style CSS subsets
  fetched with the configured sample text. A style downloads, indexes and
  activates its owning file. Catalog faces are found by exact managed path, not
  family name, so local duplicates are never toggled by mistake. License labels
  come from `StandardLicense.detect`; the path is always shown next to the label.
- Download progress is a circular ring with a down arrow. The service writes
  each TTF atomically, skips an existing license, and reports `(done, total)`.
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
- CI runs `scripts/ci.sh` on `macos-15`; `scripts/test.sh` is the same gate plus
  the network-dependent Google render. The gate enforces the full-fixture
  cold-index and search budgets; scroll and grid stay real-window measurements.
  CI sets `URFONTS_LEGACY_ICON=1` because Xcode 26.3's asset agent crashes on the
  layered raster icon; release builds require `Assets.car`. The image default
  Xcode predates Swift 6.2, so the workflow selects the latest stable Xcode
  first. `act` cannot emulate macOS runners; validate workflow changes with
  `actionlint`.
- `AppModel` can be constructed before any `NSApplication` exists (the
  `ImageRenderer` path). Never touch `NSApp` from its initializer without a nil
  guard; `start()` applies the appearance once the app is up.

### Documents

Planned. Nothing in this section is implemented yet.

- Document reading is preflight only: read the file, list fonts, activate on user
  action. No app control, no Apple Events, no plug-ins.
- Sources of font names: IDML `Resources/Fonts.xml`, INDD and AI XMP `stFnt`,
  PDF `BaseFont`, PSD text layers.
- Preflight never writes into the document's folder.

### Packaging

- SwiftPM executable plus `scripts/build-app.sh`. No Xcode project.
- Bundle is `UrFonts.app`; executable is `UrFonts`; bundle ID
  `com.10k24.urfonts`. The dev build script assembles `build/UrFonts.app` and
  ad-hoc signs it; notarization comes at release. Local bundles get a timestamp
  `CFBundleVersion` and a development stamp in About; release builds set
  `URFONTS_BUILD_NUMBER`. Generated `Assets.car` and `UrFonts.icns` live in
  `macos/`, are ignored by git, and are rebuilt by `build-app.sh` when missing.
  `build-icons.sh` falls back to the legacy `.icns` when `actool` fails; CI uses
  that path, while release builds require `Assets.car`.
- A bare SwiftPM binary launches as `BackgroundOnly`; always package the bundle
  before judging activation, menus or focus.
- Developer ID, hardened runtime, notarized. GRDB is the only dependency today;
  Sparkle is planned for release. One dependency for updates, one for the
  database remains the target.
- Apache-2.0. MIT-derived code keeps its notice in `NOTICE`.

### Documentation

- `README.md` is for users: features, requirements, commands and where data
  lives. Update it for every user-visible behavior, command or path change.
- `docs/ARCHITECTURE.md` is the structural map and data flow. Update it when a
  module boundary, schema, command surface or data path changes.
- `docs/RELEASING.md` covers version bumps, signing, notarization and publishing.
  Update it when the release process or credentials change.
- `docs/PERF.md` is the real-window measurement protocol. Update it when the
  Instruments workflow or scripts change.
- `CONTRIBUTING.md` covers setup, the gate, style and support policy. Update it
  when requirements, scripts or review rules change.
- `CHANGELOG.md` records notable user-visible changes under `Unreleased`, grouped
  as Added, Changed, Fixed or Removed. Use release dates only when a version is
  tagged.
- `BENCH.md` records the method, environment and raw numbers from a Release run.
  Never add a number that was not measured, and re-measure before trusting an
  old row.
- `AGENTS.md` is the canonical record of invariants and measurement rules. Other
  docs link to its budgets instead of copying numbers.
- `OPEN_ISSUES.md` is a kanban; its heading is the only state marker.
- Update the affected docs in the same change as the behavior, not later. A
  behavior change that leaves the docs stale is an incomplete change.
- Docs never use line numbers, `file:line` references, generated counts,
  timestamps or copied benchmark numbers. Refer to symbols, file names, sections
  or the budgets in this file instead.

## Architecture / file layout

```
Sources/UrFontsCore          no UI, every public type Sendable
  FontKit/                   head, hhea, OS/2, name, fvar, cmap coverage,
                             GSUB/GPOS tags (STAT planned)
  Scanner/                   walk, stamps, parallel parse, delta sets
  Watch/                     FSEvents per folder, fallback sweep
  Catalog/                   GRDB store, migrations, snapshot, search index
  Activation/                engine, registrar protocol, journal, reconcile
  Coverage/                  batched cmap script index (manual)
  GoogleFonts/               catalog, styles, GitHub downloads,
                             CSS preview subsets
  FontManagers/              cache detectors (FontBase today)
  Preview/                   FontLoader LRU, CTLine and tile drawing
  Metrics/                   planned: contrast, classification
  Documents/                 planned: IDML, INDD, AI, PDF, PSD extraction
  Sync/                      planned: user-data export and merge
Sources/UrFonts              SwiftUI app, MainActor by default
  App/                       commands, model, folder tree, headless harness
  Settings/                  Settings scene, ignored folders
  Sidebar/ Browser/ FontPage/ Providers/ Components/ Spikes/
                             (Info, Windows planned)
Sources/urfonts-cli          index, search, folders, activation, headless
BENCH.md                     Release measurements, method and raw numbers
Tests/UrFontsCoreTests       parser, scanner, catalog, activation with fakes
Tests/UrFontsSnapshotTests   planned: ImageRenderer golden images
macos/                       Info.plist
Resources/                   planned: character sets, language data
scripts/                     build-icons.sh, build-app.sh, make-dmg.sh, ci.sh,
                             test.sh, bench.sh, perf-window.sh, register-spike.sh
design/icon/                 Icon Composer source plus legacy 1024 PNG
tools/                       fixture generator
docs/                        ARCHITECTURE.md, PERF.md, RELEASING.md
CONTRIBUTING.md              setup, gate, style, support policy
CHANGELOG.md                 Keep a Changelog, Unreleased until first release
README.md                    user-facing overview and data locations
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
excluded_path(path, added_at)
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
- Code must compile with the oldest supported toolchain (Swift 6.2), not only the
  local Xcode. Swift 6.4 accepts `CFError as NSError`; 6.2 does not. Prefer CF
  APIs that need no bridge, such as `CFErrorCopyUserInfo`.
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
- The scanner and catalog unit tests use generated fixtures; the large fixture
  drives the headless benchmarks and manual cold-index checks. A tiny fixture
  does not prove the full-scale path.
- Activation has two layers: a fake registrar for state machine tests, and an
  opt-in real test that registers and unregisters one known font.
- Headless scenarios cover the app wiring. A scenario must fail when the command
  seam is sabotaged.
- Golden-image previews at fixed scale, light/dark and Latin/CJK are planned in
  `Tests/UrFontsSnapshotTests`; they do not run yet.

### Traps that produce false green

- A focus test that asserts nothing about focus proves nothing. Assert
  `NSApp.isActive == false` explicitly.
- A benchmark that runs in Debug is not the build users run. Measure Release.
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
