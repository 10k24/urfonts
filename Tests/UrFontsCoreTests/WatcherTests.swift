import Foundation
import Testing
import UrFontsCore

/// FSEvents is timing-dependent, so this is opt-in:
/// `URFONTS_WATCH_TEST=1 swift test --filter folderWatcher`.
@Suite("Watcher")
struct WatcherTests {
    @Test(
        "reports the watched root when a file appears",
        .enabled(if: ProcessInfo.processInfo.environment["URFONTS_WATCH_TEST"] == "1")
    )
    func folderWatcher() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // FSEvents reports the directory and the file, often in two callbacks.
        // The watcher may report the same root twice; confirm once.
        final class Flag: @unchecked Sendable {
            private let lock = NSLock()
            private var taken = false

            func take() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if taken { return false }
                taken = true
                return true
            }
        }
        let first = Flag()

        let watcher = FolderWatcher()
        try await confirmation("change reported", expectedCount: 1) { confirm in
            watcher.start(roots: [root.path]) { changes in
                if changes.contains(where: { $0.root == root.path }), first.take() {
                    confirm()
                }
            }
            // FSEvents needs a moment to arm before the first write.
            try? await Task.sleep(for: .milliseconds(500))
            try Data("fixture".utf8).write(to: root.appendingPathComponent("appeared.ttf"))
            try? await Task.sleep(for: .seconds(3))
        }
        watcher.stop()
    }
}
