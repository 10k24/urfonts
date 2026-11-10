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
