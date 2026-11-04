import AppKit
import SwiftUI
import UrFontsCore

struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var pendingRemoval: LibraryFolder?

    var body: some View {
        List(selection: $model.selection) {
            Section("Library") {
                row(
                    title: "All Fonts",
                    systemImage: "textformat",
                    count: model.snapshot.familyCount
                )
                .tag(SidebarSelection.all)
            }

            Section("Folders") {
                ForEach(model.folders) { folder in
                    row(
                        title: model.folderTitles[folder.id] ?? folder.displayPath,
                        systemImage: folder.kind == .watched ? "eye" : "folder",
                        count: folder.fileCount
                    )
                    .help("\(folder.path)\n\(folder.kind == .watched ? "Watched" : "One-time scan")")
                    .tag(SidebarSelection.folder(folder.id))
                    .contextMenu {
                        Button("Rescan") {
                            Task {
                                await model.addFolder(
                                    URL(fileURLWithPath: folder.path),
                                    kind: folder.kind
                                )
                            }
                        }
                        if folder.kind == .watched {
                            Button("Stop Watching") {
                                Task { await model.setWatched(folder, false) }
                            }
                        } else {
                            Button("Watch for Changes") {
                                Task { await model.setWatched(folder, true) }
                            }
                        }
                        Divider()
                        Button("Remove from Library…", role: .destructive) {
                            pendingRemoval = folder
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                chooseFolder(using: model)
            } label: {
                Label("Add Folder…", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.displayPath ?? "") from the library?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let folder = pendingRemoval {
                    Task { await model.removeFolder(folder) }
                }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            Text("Font files stay on disk. Only the library entries are removed.")
        }
    }

    private func row(title: String, systemImage: String, count: Int) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

@MainActor
func chooseFolder(using model: AppModel) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    panel.prompt = "Add"
    panel.message = "Choose a folder of font files. Files are read, never moved."

    let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 25))
    popup.addItems(withTitles: ["Watch for Changes", "One-time Scan"])
    panel.accessoryView = popup

    panel.begin { response in
        guard response == .OK else { return }
        let kind: FolderKind = popup.indexOfSelectedItem == 0 ? .watched : .staticFolder
        let urls = panel.urls
        Task { @MainActor in
            for url in urls {
                await model.addFolder(url, kind: kind)
            }
        }
    }
}
