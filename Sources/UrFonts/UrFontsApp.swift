import SwiftUI

struct UrFontsApp: App {
    var body: some Scene {
        WindowGroup("Ur Fonts") {
            ContentView()
        }
        .defaultSize(width: 1150, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
