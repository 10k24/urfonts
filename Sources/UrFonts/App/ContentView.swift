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
    }
}
