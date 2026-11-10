import Foundation

public enum LibraryLocation {
    /// `~/Library/Application Support/Ur Fonts/library.sqlite3`
    public static func defaultDatabaseURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Ur Fonts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("library.sqlite3")
    }

    /// Standard macOS font folders, in sidebar order. Missing folders are
    /// skipped, so a clean install only seeds what actually exists.
    public static func defaultFontFolders() -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return [
            URL(fileURLWithPath: "/Library/Fonts", isDirectory: true),
            home.appendingPathComponent("Library/Fonts", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/Fonts", isDirectory: true),
        ].filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }
}
