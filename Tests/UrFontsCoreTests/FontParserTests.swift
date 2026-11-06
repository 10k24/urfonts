import Foundation
import Testing
import UrFontsCore
import UrFontsFixtures

@Suite("Font parser")
struct FontParserTests {
    private func fixture(_ index: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-parse-\(UUID().uuidString).ttf")
        try MinimalFont.data(for: MinimalFontSpec(index: index)).write(to: url)
        return url
    }

    @Test("reads names, weight and normalized metrics")
    func fixtureFace() throws {
        let url = try fixture(0)
        defer { try? FileManager.default.removeItem(at: url) }

        let faces = try FontFileParser.parse(url: url)
        #expect(faces.count == 1)
        let face = try #require(faces.first)
        #expect(face.family == "Fixture Family 00001")
        #expect(face.style == "Regular")
        #expect(face.postscriptName == "FixtureFamily00001-Regular")
        #expect(face.weightClass == 400)
        #expect(face.isBold == false)
        #expect(face.isItalic == false)
        #expect(face.unitsPerEm == 1000)
        #expect(face.xHeight == 0.5)
        #expect(face.capHeight == 0.7)
        #expect(face.ascender == 0.8)
        #expect(face.descender == -0.2)
        #expect(face.vendorID == "URFT")
        #expect(face.isVariable == false)
    }

    @Test("bold and italic come from OS/2 and head")
    func boldItalic() throws {
        let url = try fixture(3)
        defer { try? FileManager.default.removeItem(at: url) }
        let face = try #require(try FontFileParser.parse(url: url).first)
        #expect(face.weightClass == 700)
        #expect(face.isBold)
        #expect(face.isItalic)
        #expect(face.style == "Bold Italic")
    }

    @Test("non-font data throws")
    func garbage() {
        #expect(throws: FontParseError.self) {
            _ = try FontFileParser.parse(data: Data("not a font".utf8))
        }
    }

    @Test("truncated font yields no faces")
    func truncated() throws {
        let full = MinimalFont.data(for: MinimalFontSpec(index: 0))
        let cut = full.prefix(120)
        #expect(throws: FontParseError.self) {
            _ = try FontFileParser.parse(data: Data(cut))
        }
    }

    @Test("OpenType feature tags are read safely")
    func openTypeFeatures() throws {
        let fixture = try fixture(0)
        defer { try? FileManager.default.removeItem(at: fixture) }
        #expect(try FontFileParser.featureTags(url: fixture).isEmpty)

        let candidates = [
            "/System/Library/Fonts/Supplemental/Times New Roman.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
            "/System/Library/Fonts/Apple Color Emoji.ttc",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            let tags = try FontFileParser.featureTags(url: URL(fileURLWithPath: path))
            #expect(tags.allSatisfy { $0.tag.count == 4 })
            #expect(tags.allSatisfy { !$0.name.isEmpty })
        }
    }

    @Test("system collection parses every face")
    func systemCollection() throws {
        let url = URL(fileURLWithPath: "/System/Library/Fonts/Helvetica.ttc")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let faces = try FontFileParser.parse(url: url)
        #expect(faces.count > 1)
        #expect(faces.allSatisfy { !$0.postscriptName.isEmpty })
        #expect(faces.allSatisfy { $0.unitsPerEm > 0 })
    }
}
