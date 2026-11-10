import AppKit
import SwiftUI
import UrFontsCore

/// Global folder exclusions and suggestions from detected font managers.
struct IgnoredFoldersSettingsView: View {
    @Bindable var model: AppModel
    @State private var suggestions: [DetectedFontCache] = []
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Ignored Folders")
                    .font(.title3.weight(.semibold))
                Text("Add folders here to omit them from your library, including re-scans. "
                    + "The files stay on disk.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ignoredList

                HStack {
                    Button("Add Folder…") { chooseFolders() }
                    Spacer()
                }

                if !visibleSuggestions.isEmpty {
                    Divider()
                    Text("Detected Font Managers")
                        .font(.headline)
                    ForEach(visibleSuggestions) { suggestion in
                        suggestionRow(suggestion)
                    }
                }

                if let notice {
                    Text(notice)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .frame(width: 600, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await model.start()
            await loadSuggestions()
        }
    }

    private var ignoredList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.ignoredPaths.isEmpty {
                Text("No ignored folders.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            }
            ForEach(model.ignoredPaths, id: \.self) { path in
                ignoredRow(path)
                if path != model.ignoredPaths.last {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func ignoredRow(_ path: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text((path as NSString).lastPathComponent)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            Button {
                Task { await removeIgnored(path) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Stop ignoring this folder")
        }
        .padding(.vertical, 6)
    }

    private func suggestionRow(_ suggestion: DetectedFontCache) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.label)
                Text(suggestion.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Add to Ignore List") {
                Task { await addIgnored(suggestion.path) }
            }
        }
    }

    private var visibleSuggestions: [DetectedFontCache] {
        suggestions.filter { !model.isPathIgnored($0.path) }
    }

    private func loadSuggestions() async {
        suggestions = await Task.detached(priority: .utility) {
            FontManagerDetectors.detectedCaches()
        }.value
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Ignore"
        panel.message = "Choose folders to omit from the library. Files stay on disk."
        panel.begin { response in
            guard response == .OK else { return }
            let paths = panel.urls.map(\.path)
            Task { @MainActor in
                for path in paths {
                    await addIgnored(path)
                }
            }
        }
    }

    private func addIgnored(_ path: String) async {
        let resolved = LibraryPath.resolve(path)
        guard !resolved.isEmpty else { return }
        if model.isPathIgnored(resolved) {
            notice = "Already ignored: \(resolved)"
            return
        }
        notice = nil
        await model.ignoreFolder(path: resolved)
    }

    private func removeIgnored(_ path: String) async {
        notice = nil
        await model.unignoreFolder(path: path)
    }
}
