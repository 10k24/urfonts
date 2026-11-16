import AppKit
import SwiftUI

/// The ⌘, window. Appearance is app-wide; folder exclusions are library-wide.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                appearanceSection
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
}
