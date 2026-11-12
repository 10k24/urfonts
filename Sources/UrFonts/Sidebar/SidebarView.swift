import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UrFontsCore

struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var pendingRemoval: LibraryFolder?
    @State private var pendingWatch: LibraryFolder?
    @State private var pendingIgnore: String?
    @State private var renameTarget: LibraryFolder?
    @State private var renameText = ""
    @State private var collectionToRename: FontCollection?
    @State private var collectionToDelete: FontCollection?
    @State private var collectionName = ""
    @State private var newCollectionName = ""
    @State private var showNewCollection = false

    var body: some View {
        List(selection: $model.selection) {
            Section(Messages.Sidebar.library) {
                row(
                    title: Messages.Sidebar.allFonts,
                    systemImage: "textformat",
                    count: model.snapshot.faceCount
                )
                .tag(SidebarSelection.all)
                .help(
                    Messages.Sidebar.allFontsHelp(
                        families: model.snapshot.familyCount,
                        fonts: model.snapshot.faceCount
                    )
                )

                row(
                    title: Messages.Sidebar.active,
                    systemImage: "circle.fill",
                    count: model.activeFaceIDs.count
                )
                .tag(SidebarSelection.active)
                .help(Messages.Sidebar.activeHelp(model.activeFaceIDs.count))

                row(
                    title: Messages.Sidebar.warnings,
                    systemImage: "exclamationmark.triangle",
                    count: model.problemCount
                )
                .tag(SidebarSelection.problems)
                .help(Messages.Sidebar.warningsHelp)
            }

            Section(Messages.Sidebar.hosts) {
                HStack {
                    sidebarLabel(Messages.Sidebar.googleFonts, systemImage: "globe")
                    Spacer()
                }
                .tag(SidebarSelection.googleFonts)
                .help(Messages.Sidebar.googleFontsHelp)
            }

            Section(Messages.Sidebar.folders) {
                OutlineGroup(model.folderTreeRoots, children: \.children) { node in
                    folderNodeRow(node)
                        .tag(selectionTag(for: node))
                        .help(help(for: node))
                        .contextMenu { nodeMenu(for: node) }
                }
            }

            Section(Messages.Sidebar.collections) {
                ForEach(model.collections) { collection in
                    row(
                        title: collection.name,
                        systemImage: "rectangle.stack",
                        count: model.collectionFontCounts[collection.id] ?? 0
                    )
                    .tag(SidebarSelection.collection(collection.id))
                    .contextMenu {
                        let count = model.collectionFontCounts[collection.id] ?? 0
                        Button("Activate All") {
                            Task { await model.setCollectionActive(collection, active: true) }
                        }
                        .disabled(count == 0)
                        Button("Deactivate All") {
                            Task { await model.setCollectionActive(collection, active: false) }
                        }
                        .disabled(count == 0)
                        Divider()
                        Button("Rename…") {
                            collectionToRename = collection
                            collectionName = collection.name
                        }
                        Button("Delete…", role: .destructive) {
                            collectionToDelete = collection
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                addButton(
                    "Add Folder",
                    systemImage: "folder.badge.plus",
                    watched: false
                )
                addButton(
                    "Add Watched Folder",
                    systemImage: "magnifyingglass",
                    watched: true
                )
                Button {
                    chooseFontFiles(using: model)
                } label: {
                    Label("Add Fonts", systemImage: "character")
                        .labelStyle(.iconOnly)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Add Fonts")
                .accessibilityLabel("Add Fonts")
                Button {
                    newCollectionName = ""
                    showNewCollection = true
                } label: {
                    Label("New Collection", systemImage: "rectangle.stack.badge.plus")
                        .labelStyle(.iconOnly)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("New Collection")
                .accessibilityLabel("New Collection")
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(
            removalTitle,
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Folder", role: .destructive) {
                if let folder = pendingRemoval {
                    Task { await model.removeFolder(folder) }
                }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            Text(removalMessage)
        }
        .confirmationDialog(
            "Watch \(pendingWatch?.name ?? "") for changes?",
            isPresented: Binding(
                get: { pendingWatch != nil },
                set: { if !$0 { pendingWatch = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Watch and Rescan") {
                if let folder = pendingWatch {
                    Task { await model.setWatched(folder, true) }
                }
                pendingWatch = nil
            }
            Button("Cancel", role: .cancel) {
                pendingWatch = nil
            }
        } message: {
            Text("Watching rescans the folder and keeps it in sync from then on.")
        }
        .confirmationDialog(
            "Ignore \(pendingIgnore.map { ($0 as NSString).lastPathComponent } ?? "")?",
            isPresented: Binding(
                get: { pendingIgnore != nil },
                set: { if !$0 { pendingIgnore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Ignore Folder", role: .destructive) {
                if let path = pendingIgnore {
                    Task { await model.ignoreFolder(path: path) }
                }
                pendingIgnore = nil
            }
            Button("Cancel", role: .cancel) { pendingIgnore = nil }
        } message: {
            Text("Its fonts leave the library and active ones are deactivated. "
                + "The folder and its files stay on disk. Stop ignoring it from "
                + "the sidebar to index it again.")
        }
        .alert(
            "New Collection",
            isPresented: $showNewCollection
        ) {
            TextField("Name", text: $newCollectionName)
            Button("Create") {
                model.createCollection(named: newCollectionName)
                newCollectionName = ""
            }
            Button("Cancel", role: .cancel) { newCollectionName = "" }
        }
        .alert(
            "Rename Collection",
            isPresented: Binding(
                get: { collectionToRename != nil },
                set: { if !$0 { collectionToRename = nil } }
            )
        ) {
            TextField("Name", text: $collectionName)
            Button("Rename") {
                if let collection = collectionToRename {
                    model.renameCollection(collection, to: collectionName)
                }
                collectionToRename = nil
            }
            Button("Cancel", role: .cancel) { collectionToRename = nil }
        }
        .confirmationDialog(
            "Delete \(collectionToDelete?.name ?? "")?",
            isPresented: Binding(
                get: { collectionToDelete != nil },
                set: { if !$0 { collectionToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Collection", role: .destructive) {
                if let collection = collectionToDelete {
                    model.deleteCollection(collection)
                }
                collectionToDelete = nil
            }
            Button("Cancel", role: .cancel) { collectionToDelete = nil }
        } message: {
            Text("Fonts stay in the library. Only the collection is removed.")
        }
        .alert(
            "Rename Folder",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let folder = renameTarget {
                    Task { await model.renameFolder(folder, to: renameText) }
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) {
                renameTarget = nil
            }
        } message: {
            Text("Changes the label in Ur Fonts only. The folder on disk keeps its name.")
        }
    }

    @ViewBuilder
    private func menu(for folder: LibraryFolder) -> some View {
        let index = model.displayFolders.firstIndex(where: { $0.id == folder.id }) ?? 0
        let count = model.displayFolders.count

        Toggle(
            "Watched",
            isOn: Binding(
                get: { folder.kind == .watched },
                set: { watched in
                    if watched {
                        pendingWatch = folder
                    } else {
                        Task { await model.setWatched(folder, false) }
                    }
                }
            )
        )

        Button("Move Up") {
            model.moveFolder(id: folder.id, by: -1)
        }
        .disabled(index == 0)

        Button("Move Down") {
            model.moveFolder(id: folder.id, by: 1)
        }
        .disabled(index >= count - 1)

        Button("Rename…") {
            renameText = folder.name
            renameTarget = folder
        }

        Button("Reveal in Finder") {
            model.revealFolder(folder)
        }

        Divider()

        Button("Rescan") {
            Task {
                await model.addFolder(
                    URL(fileURLWithPath: folder.path),
                    kind: folder.kind
                )
            }
        }

        Button("Ignore This Folder…") {
            pendingIgnore = folder.path
        }

        Button("Remove from Library…", role: .destructive) {
            pendingRemoval = folder
        }
    }

    /// Icon-only buttons keep a predictable hover target so `.help` shows.
    private func addButton(
        _ title: String,
        systemImage: String,
        watched: Bool
    ) -> some View {
        Button {
            chooseFolder(using: model, watched: watched)
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }

    private func folderNodeRow(_ node: FolderNode) -> some View {
        HStack {
            sidebarLabel(
                node.name,
                systemImage: node.isIgnored
                    ? "eye.slash"
                    : (node.folderID != nil && node.isWatched ? "magnifyingglass" : "folder")
            )
            Spacer()
            if !node.isIgnored {
                Text("\(node.fontCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func selectionTag(for node: FolderNode) -> SidebarSelection {
        if let folderID = node.folderID {
            return .folder(folderID)
        }
        return .subfolder(node.id)
    }

    private func help(for node: FolderNode) -> String {
        if node.isIgnored {
            return "\(node.id)\nIgnored · not indexed"
        }
        if let folderID = node.folderID,
           let folder = model.folders.first(where: { $0.id == folderID }) {
            return help(for: folder)
        }
        return "\(node.id)\n\(node.fontCount) fonts"
    }

    @ViewBuilder
    private func nodeMenu(for node: FolderNode) -> some View {
        if node.isIgnored {
            Button("Stop Ignoring") {
                Task { await model.unignoreFolder(path: node.id) }
            }
            Button("Reveal in Finder") { model.revealPath(node.id) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.id, forType: .string)
            }
        } else if let folderID = node.folderID,
                  let folder = model.folders.first(where: { $0.id == folderID }) {
            menu(for: folder)
        } else {
            Button("Reveal in Finder") { model.revealPath(node.id) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.id, forType: .string)
            }
            Divider()
            Button("Ignore This Folder…") { pendingIgnore = node.id }
        }
    }

    private func row(title: String, systemImage: String, count: Int) -> some View {
        HStack {
            sidebarLabel(title, systemImage: systemImage)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// SF Symbols in sidebar rows are slightly smaller than the label default,
    /// with a little more space between icon and text.
    private func sidebarLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .regular))
                .frame(width: 16, alignment: .center)
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func help(for folder: LibraryFolder) -> String {
        let fonts = model.folderFontCounts[folder.id] ?? 0
        return "\(folder.path)\n\(folder.kind == .watched ? "Watched" : "One-time scan")\n\(fonts) fonts · \(folder.fileCount) files"
    }

    private var removalTitle: String {
        "Remove \(pendingRemoval?.name ?? "") from the library?"
    }

    private var removalMessage: String {
        guard let folder = pendingRemoval else { return "" }
        let active = model.activeFaceCount(in: folder)
        if active > 0 {
            return "\(active) active \(active == 1 ? "font" : "fonts") in this folder will be deactivated. Font files stay on disk."
        }
        return "Font files stay on disk. Only the library entries are removed."
    }
}

@MainActor
func chooseFontFiles(using model: AppModel) {
    var types: [UTType] = [.font]
    if let dfont = UTType(filenameExtension: "dfont") {
        types.append(dfont)
    }
    FilePicker.shared.open(
        title: "Add Fonts",
        message: "Choose font files to add. Files are read, never moved.",
        prompt: "Add Fonts",
        directories: false,
        multiple: true,
        types: types
    ) { urls in
        Task { @MainActor in
            await model.addFontFiles(urls)
        }
    }
}

@MainActor
func chooseFolder(using model: AppModel, watched: Bool) {
    FilePicker.shared.open(
        title: watched ? "Add and Watch" : "Add Folder",
        message: watched
            ? "Choose a folder to scan now and keep in sync. Files are read, never moved."
            : "Choose a folder to scan once. Files are read, never moved.",
        prompt: watched ? "Add and Watch" : "Add",
        directories: true,
        multiple: true
    ) { urls in
        let kind: FolderKind = watched ? .watched : .staticFolder
        Task { @MainActor in
            model.requestAddFolders(
                urls.map { FolderAddEntry(url: $0, kind: kind) }
            )
        }
    }
}
