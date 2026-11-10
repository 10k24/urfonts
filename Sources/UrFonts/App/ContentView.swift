import SwiftUI

struct ContentView: View {
    @State private var model: AppModel

    init(model: AppModel = AppModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            BrowserView(model: model)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .task { await model.start() }
        .confirmationDialog(
            "Folder overlaps the library",
            isPresented: Binding(
                get: { model.pendingFolderAdd != nil },
                set: { if !$0 { model.cancelPendingFolderAdd() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Add Anyway") {
                Task { await model.confirmPendingFolderAdd() }
            }
            Button("Cancel", role: .cancel) {
                model.cancelPendingFolderAdd()
            }
        } message: {
            Text(
                model.pendingFolderAdd?.warnings
                    .joined(separator: "\n\n") ?? ""
            )
        }
    }
}
