import Foundation
import Testing
import UrFontsCore

@Suite("Google Fonts")
struct GoogleFontsTests {
    @Test("folder names are filesystem safe and stable")
    func folderName() {
        #expect(GoogleFontFamily.folderName(for: family("Open Sans")) == "Open Sans")
        #expect(GoogleFontFamily.folderName(for: family("Roboto Slab")) == "Roboto Slab")
        #expect(GoogleFontFamily.folderName(for: family("IBM Plex Sans")) == "IBM Plex Sans")
    }

    @Test("downloaded detection requires a TTF")
    func downloaded() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-gf-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("Open Sans", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = GoogleFontsService()
        let openSans = family("Open Sans")
        #expect(!service.isDownloaded(openSans, in: root))

        try Data("license".utf8).write(to: directory.appendingPathComponent("LICENSE.txt"))
        #expect(!service.isDownloaded(openSans, in: root))

        try Data("font".utf8).write(to: directory.appendingPathComponent("OpenSans.ttf"))
        #expect(service.isDownloaded(openSans, in: root))
    }

    private func family(_ name: String) -> GoogleFontFamily {
        GoogleFontFamily(
            name: name,
            category: "Sans Serif",
            variants: ["regular"],
            popularity: 1,
            files: [],
            licensePath: nil
        )
    }
}
