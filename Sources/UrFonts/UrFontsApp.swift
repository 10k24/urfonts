import SwiftUI

struct UrFontsApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Ur Fonts") {
            ContentView(model: model)
        }
        .defaultSize(width: 1150, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
            AboutCommands()
            HelpCommands()
        }

        Window(Messages.Help.title, id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(model: model)
        }
    }
}
