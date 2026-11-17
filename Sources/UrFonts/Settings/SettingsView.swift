import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UrFontsCore

/// The ⌘, window. Appearance is app-wide; folder exclusions are library-wide.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                appearanceSection
                Divider()
                librarySection
                Divider()
                settingsFileSection
                Divider()
                IgnoredFoldersSettingsView(model: model)
            }
            .padding(20)
        }
        .frame(width: 600, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await model.start() }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Messages.Settings.appearance)
                .font(.title3.weight(.semibold))
            Picker(
                Messages.Settings.appearance,
                selection: $model.appearanceMode
            ) {
                Text(Messages.Settings.appearanceSystem)
                    .tag(AppearanceMode.system)
                Text(Messages.Settings.appearanceLight)
                    .tag(AppearanceMode.light)
                Text(Messages.Settings.appearanceDark)
                    .tag(AppearanceMode.dark)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            Text(Messages.Settings.appearanceHelp)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Library")
                .font(.title3.weight(.semibold))
            Toggle(
                "Use filename if font name missing",
                isOn: $model.fallbackFileNames
            )
            .toggleStyle(.switch)
            Text("Trial fonts sometimes report \".\" as their family name. "
                + "This uses the file name instead.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var settingsFileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings File")
                .font(.title3.weight(.semibold))
            HStack(spacing: 8) {
                Button("Export Settings…") { exportSettings(using: model) }
                Button("Import Settings…") { importSettings(using: model) }
            }
            Text("Versioned JSON with folders, collections, samples and preview settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
func exportSettings(using model: AppModel) {
    FilePicker.shared.save(
        title: "Export Settings",
        name: LibraryConfiguration.fileName,
        types: [.json]
    ) { url in
        do {
            try model.exportSettings(to: url)
        } catch {
            model.report(error, context: "settings export")
        }
    }
}

@MainActor
func importSettings(using model: AppModel) {
    FilePicker.shared.open(
        title: "Import Settings",
        message: "Choose an Ur Fonts settings JSON file.",
        prompt: "Import",
        directories: false,
        multiple: false,
        types: [.json]
    ) { urls in
        guard let url = urls.first else { return }
        Task { @MainActor in
            do {
                try await model.importSettings(from: url)
            } catch {
                model.report(error, context: "settings import")
            }
        }
    }
}
