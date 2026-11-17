import AppKit
import SwiftUI

/// The ⌘? help window. Short answers for the workflows that are not obvious from
/// the browser: read-only files, global activation, cloud folders and warnings.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(Messages.Help.title)
                    .font(.largeTitle.weight(.semibold))
                Text(Messages.Help.intro)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                section(
                    title: Messages.Help.libraryTitle,
                    body: Messages.Help.libraryBody
                )
                section(
                    title: Messages.Help.activationTitle,
                    body: Messages.Help.activationBody
                )
                section(
                    title: Messages.Help.previewTitle,
                    body: Messages.Help.previewBody
                )
                section(
                    title: Messages.Help.warningsTitle,
                    body: Messages.Help.warningsBody
                )
                section(
                    title: Messages.Help.googleTitle,
                    body: Messages.Help.googleBody
                )
                section(
                    title: Messages.Help.limitsTitle,
                    body: Messages.Help.limitsBody
                )
            }
            .padding(24)
        }
        .frame(width: 560, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Replaces the default Help menu item, which has no help book to open.
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button(Messages.Help.menuItem) {
                openWindow(id: "help")
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}
