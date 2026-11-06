import CoreText
import Foundation
import Testing
import UrFontsFixtures

@Suite("Preview glyphs")
struct PreviewGlyphTests {
    @Test("missing characters map to .notdef instead of failing")
    func missingGlyphs() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-notdef-\(UUID().uuidString).ttf")
        try MinimalFont.data(for: MinimalFontSpec(index: 0)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
            as? [CTFontDescriptor], let descriptor = descriptors.first else {
            Issue.record("no descriptor")
            return
        }
        let font = CTFontCreateWithFontDescriptor(descriptor, 24, nil)

        var missing = Array("0123456789".utf16)
        var missingGlyphs = [CGGlyph](repeating: 1, count: missing.count)
        _ = CTFontGetGlyphsForCharacters(font, &missing, &missingGlyphs, missing.count)
        #expect(missingGlyphs.allSatisfy { $0 == 0 })

        var present = Array("ABC".utf16)
        var presentGlyphs = [CGGlyph](repeating: 0, count: present.count)
        let complete = CTFontGetGlyphsForCharacters(
            font,
            &present,
            &presentGlyphs,
            present.count
        )
        #expect(complete)
        #expect(presentGlyphs.allSatisfy { $0 != 0 })
    }
}
