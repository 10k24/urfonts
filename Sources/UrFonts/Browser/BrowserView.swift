import AppKit
import SwiftUI
import UrFontsCore

struct BrowserView: View {
    @Bindable var model: AppModel
    @State private var showSettings = false
    @State private var detail: CatalogFamily?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if model.isLoading {
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

            Divider()
            statusBar
        }
        .background(model.backgroundColor)
        .toolbar { toolbar }
        .sheet(item: $detail) { family in
            FamilyDetailView(model: model, family: family)
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
                            sampleText: model.sampleText,
                            sampleSize: model.sampleSize,
                            textColor: model.textColor,
                            backgroundColor: model.backgroundColor,
                            activation: model.familyActivation(family),
                            onToggle: { Task { await model.toggle(family) } }
                        )
                        .equatable()
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { detail = family }
                        .contextMenu { contextMenu(for: family) }
                    }
                }
                .padding(.vertical, 4)
            }
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
                            sampleText: model.sampleText,
                            sampleSize: model.sampleSize,
                            textColor: model.textColor,
                            backgroundColor: model.backgroundColor,
                            activation: model.familyActivation(family),
                            onToggle: { Task { await model.toggle(family) } }
                        )
                        .equatable()
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { detail = family }
                        .contextMenu { contextMenu(for: family) }
                    }
                }
                .padding(16)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No fonts yet", systemImage: "textformat")
        } description: {
            Text("Add a folder to index your font library. Files stay where they are.")
        } actions: {
            Button("Add Folder…") { chooseFolder(using: model) }
                .buttonStyle(.borderedProminent)
            if !model.folders.isEmpty {
                Button("Rescan Folders") { Task { await model.rescanAll() } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatches: some View {
        ContentUnavailableView.search(text: model.query)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { chooseFolder(using: model) } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .help("Add a font folder")
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
            Button { showSettings = true } label: {
                Label("Preview", systemImage: "slider.horizontal.3")
            }
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                PreviewSettingsView(model: model)
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for family: CatalogFamily) -> some View {
        Button("Show Details") { detail = family }
        Button(model.familyActivation(family) == .all ? "Deactivate" : "Activate") {
            Task { await model.toggle(family) }
        }
        .disabled(model.familyActivation(family) == .installed)
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
            Text(model.status.isEmpty ? model.visibleStatus : model.status)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(model.visibleStatus)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

// MARK: - Preview settings

struct PreviewSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preview")
                .font(.headline)

            TextField("Sample text", text: $model.sampleText)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Text("Size")
                    .frame(width: 36, alignment: .leading)
                Slider(value: $model.sampleSize, in: 12...72)
                Text("\(Int(model.sampleSize))")
                    .monospacedDigit()
                    .frame(width: 24, alignment: .trailing)
            }

            ColorPicker("Text color", selection: $model.textColor)
            ColorPicker("Background", selection: $model.backgroundColor)

            Text("Applied to every row and tile.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 320)
    }
}
