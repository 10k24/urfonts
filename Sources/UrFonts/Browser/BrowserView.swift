import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UrFontsCore

struct BrowserView: View {
    @Bindable var model: AppModel
    @State private var showSettings = false
    @State private var showFilters = false
    @State private var detail: CatalogFamily?
    @State private var collectionFamily: CatalogFamily?
    @State private var newCollectionName = ""
    @State private var showNewCollection = false
    @State private var showGoogleFonts = false

    // Scroll position is cached per sidebar item and view mode. Restoring by
    // family id survives row heights, but never shares an offset between
    // folders or between list and grid.
    private struct ScrollKey: Hashable {
        let selection: SidebarSelection
        let mode: BrowserViewMode
    }

    /// Session only. `@State`, never UserDefaults: relaunch starts at the top.
    /// Reference storage so per-scroll bookkeeping does not invalidate the
    /// view. Writing @State on every scroll tick was the source of the lag.
    private final class ScrollMemory {
        var topByKey: [ScrollKey: String] = [:]
        var activeKey: ScrollKey?
    }

    @State private var scrollMemory = ScrollMemory()
    @State private var topFamilyID: String?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if model.selection == .problems {
                    ProblemsView(model: model)
                } else if model.isLoading {
                    ProgressView("Loading library…")
                } else if model.snapshot.familyCount == 0 {
                    emptyState
                } else if model.visibleFamilies.isEmpty {
                    noMatches
                } else {
                    browser
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dropDestination(for: URL.self) { urls, _ in
                Task { await model.importURLs(urls) }
                return true
            }

            Divider()
            statusBar
        }
        .background(model.backgroundColor)
        .toolbar { toolbar }
        .sheet(item: $detail) { family in
            FamilyDetailView(model: model, family: family)
        }
        .sheet(isPresented: $showGoogleFonts) {
            GoogleFontsView(model: model)
        }
        .alert("New Collection", isPresented: $showNewCollection) {
            TextField("Name", text: $newCollectionName)
            Button("Create") {
                model.createCollection(named: newCollectionName, family: collectionFamily)
                newCollectionName = ""
                collectionFamily = nil
            }
            Button("Cancel", role: .cancel) {
                newCollectionName = ""
                collectionFamily = nil
            }
        } message: {
            Text("Adds this family to a new collection.")
        }
        .onAppear {
            scrollMemory.activeKey = currentScrollKey
        }
        .onChange(of: model.selection) { _, _ in
            scrollContextChanged()
        }
        .onChange(of: model.viewMode) { _, _ in
            scrollContextChanged()
        }
        .onChange(of: topFamilyID) { _, newValue in
            guard scrollMemory.activeKey == currentScrollKey else { return }
            if let newValue {
                scrollMemory.topByKey[currentScrollKey] = newValue
            } else {
                scrollMemory.topByKey.removeValue(forKey: currentScrollKey)
            }
        }
        .navigationTitle("Ur Fonts")
        .navigationSubtitle(model.visibleStatus)
        .alert(
            "Library error",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var browser: some View {
        switch model.viewMode {
        case .list:
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.visibleFamilies) { family in
                        FamilyRow(
                            family: family,
                            face: model.representativeFace(for: family),
                            sampleText: model.sampleText(for: family),
                            sampleSize: model.sampleSize,
                            textColor: model.textColor,
                            backgroundColor: model.backgroundColor,
                            activation: model.familyActivation(family),
                            onToggle: { Task { await model.toggle(family) } },
                            maxLines: model.previewMaxLines,
                            rowHeight: model.previewRowHeight
                        )
                        .equatable()
                        .contentShape(Rectangle())
                        .onTapGesture { detail = family }
                        .contextMenu { contextMenu(for: family) }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 4)
            }
            .scrollPosition(id: $topFamilyID, anchor: .top)
        case .grid:
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(model.visibleFamilies) { family in
                        FamilyTile(
                            family: family,
                            face: model.representativeFace(for: family),
                            sampleText: model.sampleText(for: family),
                            sampleSize: model.sampleSize,
                            textColor: model.textColor,
                            backgroundColor: model.backgroundColor,
                            activation: model.familyActivation(family),
                            onToggle: { Task { await model.toggle(family) } }
                        )
                        .equatable()
                        .contentShape(Rectangle())
                        .onTapGesture { detail = family }
                        .contextMenu { contextMenu(for: family) }
                    }
                }
                .scrollTargetLayout()
                .padding(16)
            }
            .scrollPosition(id: $topFamilyID, anchor: .top)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No fonts yet", systemImage: "textformat")
        } description: {
            Text("Add a folder to index your font library. Files stay where they are.")
        } actions: {
            HStack {
                Button("Add Folder…") { chooseFolder(using: model, watched: false) }
                    .buttonStyle(.borderedProminent)
                Button("Add Fonts…") { chooseFontFiles(using: model) }
                Button("Add Watched Folder…") { chooseFolder(using: model, watched: true) }
            }
            if !model.folders.isEmpty {
                Button("Rescan Folders") { Task { await model.rescanAll() } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var noMatches: some View {
        if model.selection == .active {
            let narrowed = !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || model.filter.isActive
                || !model.showSystemFonts
            ContentUnavailableView {
                Label("No active fonts", systemImage: "circle")
            } description: {
                Text(
                    narrowed
                        ? "No active fonts match the current search and filters."
                        : "Activate a family from All Fonts to see it here."
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView {
                Label("No fonts match these filters", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Adjust or clear the filters in the toolbar.")
            } actions: {
                Button("Clear Filters") { model.filter = CatalogFilter() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView.search(text: model.query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showGoogleFonts = true } label: {
                Label("Google Fonts", systemImage: "globe")
            }
            .help("Browse and download Google Fonts")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await model.rescanAll() } } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .help("Rescan every folder")
        }
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $model.query)
                    .textFieldStyle(.plain)
                    .frame(width: 180)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        ToolbarItem(placement: .primaryAction) {
            Picker("View", selection: $model.viewMode) {
                Image(systemName: "list.bullet").tag(BrowserViewMode.list)
                Image(systemName: "square.grid.2x2").tag(BrowserViewMode.grid)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 90)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showFilters = true } label: {
                Label(
                    "Filters",
                    systemImage: model.filter.isActive || !model.showSystemFonts
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
            .help("Filter fonts")
            .popover(isPresented: $showFilters, arrowEdge: .bottom) {
                FilterView(model: model)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showSettings = true } label: {
                Label("Preview", systemImage: "slider.horizontal.3")
            }
            .help("Edit preview text (⌘E)")
            .keyboardShortcut("e", modifiers: .command)
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                PreviewSettingsView(model: model)
            }
        }
    }

    private var currentScrollKey: ScrollKey {
        ScrollKey(selection: model.selection, mode: model.viewMode)
    }

    /// Remember the outgoing view's top family, then restore the incoming one.
    /// A nil entry means that view was at the top.
    private func scrollContextChanged() {
        let key = currentScrollKey
        // Stop recording until the new content has restored its position, so
        // transient nil writes from the incoming list do not erase the cache.
        scrollMemory.activeKey = nil
        topFamilyID = scrollMemory.topByKey[key]
        DispatchQueue.main.async {
            scrollMemory.activeKey = key
        }
    }

    @ViewBuilder
    private func contextMenu(for family: CatalogFamily) -> some View {
        Button("Show Details") { detail = family }
        Button(model.familyActivation(family) == .all ? "Deactivate" : "Activate") {
            Task { await model.toggle(family) }
        }
        .disabled(model.familyActivation(family) == .installed)
        Menu("Add to Collection") {
            ForEach(model.collections) { collection in
                Button(
                    model.isInCollection(family, collection.id)
                        ? "✓ \(collection.name)"
                        : collection.name
                ) {
                    model.toggleCollection(collection.id, family: family)
                }
            }
            if !model.collections.isEmpty {
                Divider()
            }
            Button("New Collection…") {
                collectionFamily = family
                newCollectionName = ""
                showNewCollection = true
            }
        }
        if let face = model.representativeFace(for: family) {
            Divider()
            Button("Reveal in Finder") { model.revealInFinder(face) }
            Button("Copy PostScript name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(face.postscriptName, forType: .string)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if !model.status.isEmpty {
                Text(model.status)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("Aa")
                AccentSlider(value: $model.sampleSize, range: 12...72)
                    .frame(width: 100)
                    .accessibilityLabel("Preview size")
                Text("\(Int(model.sampleSize))")
                    .monospacedDigit()
                    .frame(width: 22, alignment: .trailing)
            }
            .help("Preview size")
            Text(model.visibleStatus)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

// MARK: - Filters

struct FilterView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Filters")
                    .font(.headline)
                Spacer()
                if model.filter.isActive {
                    Button("Clear") { model.filter = CatalogFilter() }
                        .font(.caption)
                }
            }

            Picker("Kind", selection: $model.filter.kind) {
                Text("All").tag(FontKindFilter.any)
                Text("Variable").tag(FontKindFilter.variable)
                Text("Static").tag(FontKindFilter.staticFont)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Toggle("Show system fonts", isOn: $model.showSystemFonts)

            Toggle("Has italic", isOn: $model.filter.requiresItalic)
            Toggle("Has bold", isOn: $model.filter.requiresBold)

            Picker("Script", selection: $model.filter.script) {
                Text("Any script").tag(FontScript?.none)
                ForEach(FontScript.allCases, id: \.self) { script in
                    Text(script.displayName).tag(Optional(script))
                }
            }

            TextField("Contains characters", text: $model.filter.characters)
                .textFieldStyle(.roundedBorder)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Coverage")
                    Spacer()
                    Text("\(model.coverageIndexed.formatted()) / \(model.coverageTotal.formatted()) fonts")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                if model.isIndexingCoverage {
                    ProgressView(
                        value: Double(model.coverageIndexed),
                        total: Double(max(1, model.coverageTotal))
                    )
                } else if model.coverageIndexed < model.coverageTotal {
                    Button("Index Coverage") {
                        Task { await model.indexCoverage() }
                    }
                    .font(.caption)
                }

                Text("Script and character filters and script-aware previews need this index. Characters not yet indexed are skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

// MARK: - Preview settings

struct PreviewSettingsView: View {
    @Bindable var model: AppModel
    @State private var showSaveSample = false
    @State private var saveSampleName = ""
    @FocusState private var previewTextFocused: Bool

    private var presetBinding: Binding<PreviewPreset> {
        Binding(
            get: { PreviewPreset.matching(model.sampleText) },
            set: { preset in
                if let text = preset.text {
                    model.sampleText = text
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preview")
                .font(.headline)

            Picker("Preset", selection: presetBinding) {
                ForEach(PreviewPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            TextField("Preview text", text: $model.sampleText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .focused($previewTextFocused)

            HStack(spacing: 12) {
                ColorPicker("Text color", selection: $model.textColor)
                ColorPicker("Background", selection: $model.backgroundColor)
                Button {
                    let previous = model.textColor
                    model.textColor = model.backgroundColor
                    model.backgroundColor = previous
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .buttonStyle(.borderless)
                .help("Swap text and background colors")
            }

            Divider()

            Picker("Saved sample", selection: $model.selectedSampleID) {
                Text("Unsaved").tag(String?.none)
                ForEach(model.samples) { sample in
                    Text(sample.name).tag(Optional(sample.id))
                }
            }

            HStack(spacing: 8) {
                Button("Save as Sample…") {
                    saveSampleName = model.selectedSample?.name ?? ""
                    showSaveSample = true
                }

                if model.selectedSampleID != nil {
                    Button("Update") {
                        model.saveCurrentSample(named: model.selectedSample?.name ?? "")
                    }
                    .disabled(!model.sampleIsDirty)

                    Button("Delete", role: .destructive) {
                        model.deleteSelectedSample()
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                if model.sampleIsDirty {
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Saved samples keep the text, size and colors. Selecting one applies it; Update stores edits.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 8) {
                Button("Export Settings…") { exportSettings(using: model) }
                Button("Import Settings…") { importSettings(using: model) }
            }
            Text("Versioned JSON with folders, collections, samples and preview settings.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Use filename if font name missing", isOn: $model.fallbackFileNames)
                .toggleStyle(.switch)
            Text("Trial fonts sometimes report \".\" as their family name. This uses the file name instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 340)
        .alert("Save Sample", isPresented: $showSaveSample) {
            TextField("Name", text: $saveSampleName)
            Button("Save") {
                model.saveCurrentSample(named: saveSampleName, asNew: true)
                saveSampleName = ""
            }
            Button("Cancel", role: .cancel) { saveSampleName = "" }
        } message: {
            Text("Saves the current preview text, size and colors.")
        }
        .onChange(of: model.selectedSampleID) { _, id in
            guard let id, let sample = model.samples.first(where: { $0.id == id }) else {
                return
            }
            model.applySample(sample)
        }
        .onAppear {
            previewTextFocused = true
        }
    }
}

@MainActor
func exportSettings(using model: AppModel) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = LibraryConfiguration.fileName
    panel.allowedContentTypes = [.json]
    panel.canCreateDirectories = true
    panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        do {
            try model.exportSettings(to: url)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

@MainActor
func importSettings(using model: AppModel) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                try await model.importSettings(from: url)
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }
}
