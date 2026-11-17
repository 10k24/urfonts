import SwiftUI

/// First-run guidance. Shown once from `ContentView`; the Help window covers
/// the same material later.
struct WelcomeView: View {
    let addFolder: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(Messages.Welcome.title)
                .font(.largeTitle.weight(.semibold))
            Text(Messages.Welcome.intro)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            point(
                title: Messages.Welcome.filesTitle,
                body: Messages.Welcome.filesBody
            )
            point(
                title: Messages.Welcome.foldersTitle,
                body: Messages.Welcome.foldersBody
            )
            point(
                title: Messages.Welcome.activationTitle,
                body: Messages.Welcome.activationBody
            )

            HStack(spacing: 12) {
                Button(Messages.Welcome.addFolder) {
                    addFolder()
                }
                .keyboardShortcut(.defaultAction)

                Button(Messages.Welcome.explore) {
                    done()
                }

                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func point(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
