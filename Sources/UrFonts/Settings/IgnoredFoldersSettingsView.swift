import AppKit
import SwiftUI
import UrFontsCore

/// Global folder exclusions and suggestions from detected font managers.
struct IgnoredFoldersSettingsView: View {
    @Bindable var model: AppModel
    @State private var suggestions: [DetectedFontCache] = []
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Messages.Settings.ignoredFolders)
                .font(.title3.weight(.semibold))
            Text(Messages.Settings.ignoredFoldersHelp)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ignoredList

            HStack {
                Button(Messages.Settings.addFolder) { chooseFolders() }
                Spacer()
            }

            if !visibleSuggestions.isEmpty {
                Divider()
                Text(Messages.Settings.detectedManagers)
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
        .task {
            await model.start()
            await loadSuggestions()
        }
    }

    private var ignoredList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.ignoredPaths.isEmpty {
                Text(Messages.Settings.noIgnoredFolders)
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
            Button(Messages.Settings.addToIgnoreList) {
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
        FilePicker.shared.open(
            title: "Ignore Folders",
            message: "Choose folders to omit from the library. Files stay on disk.",
            prompt: "Ignore",
            directories: true,
            multiple: true
        ) { urls in
            Task { @MainActor in
                for url in urls {
                    await addIgnored(url.path)
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
