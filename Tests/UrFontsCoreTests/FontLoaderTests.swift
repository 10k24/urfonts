import CoreText
import Foundation
import Testing
import UrFontsCore
import UrFontsFixtures

@Suite("Font loader")
struct FontLoaderTests {
    @Test("falls back to the face index for a single-face file")
    func indexFallback() async throws {
        let spec = MinimalFontSpec(index: 0)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-loader-\(UUID().uuidString).ttf")
        try MinimalFont.data(for: spec).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = await FontLoader().font(path: url.path, faceIndex: 0)
        let font = try #require(loaded)
        #expect(CTFontCopyPostScriptName(font.ctFont) as String == spec.postscriptName)
    }

    @Test("PostScript name resolves an SFNT face in a variable collection")
    func namedFace() async throws {
        let path = "/System/Library/Fonts/SFIndia.ttc"
        guard FileManager.default.fileExists(atPath: path) else { return }

        // Descriptor index 1 is the second Bangla named instance, not the
        // second SFNT face. The name must win over the index.
        let loaded = await FontLoader().font(
            path: path,
            faceIndex: 1,
            postscriptName: ".SFDevanagari-Regular"
        )
        let font = try #require(loaded)
        #expect(
            CTFontCopyPostScriptName(font.ctFont) as String
                == ".SFDevanagari-Regular"
        )
    }
}
