import Foundation
import Testing
import UrFontsCore
import UrFontsFixtures

@Suite("Coverage")
struct CoverageTests {
    private func makeLibrary(count: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-coverage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<count {
            let spec = MinimalFontSpec(index: index)
            try MinimalFont.data(for: spec)
                .write(to: root.appendingPathComponent("\(spec.postscriptName).ttf"))
        }
        return root
    }

    @Test("cmap reports Latin and the indexer fills pending faces")
    func fixtureCoverage() async throws {
        let root = try makeLibrary(count: 4)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("FixtureFamily00001-Regular.ttf")
        let masks = try FontFileParser.coverage(url: url).mapValues(\.mask)
        let mask = try #require(masks[0])
        #expect(mask & FontScript.latin.rawValue != 0)
        #expect(mask & FontScript.greek.rawValue == 0)

        let database = try LibraryDatabase(inMemory: true)
        _ = try await LibraryScanner(database: database).scan(folder: root)
        #expect(try database.pendingCoverage(limit: 100).count == 4)

        let indexer = CoverageIndexer(database: database)
        let indexed = try await indexer.index()
        #expect(indexed == 4)
        #expect(try database.pendingCoverage(limit: 100).isEmpty)

        let snapshot = try database.snapshot()
        let family = try #require(snapshot.families.first)
        #expect(family.scriptMask & FontScript.latin.rawValue != 0)
        #expect(family.previewText(userText: "Sample") == "Sample")
    }

    @Test("script samples prefer distinctive scripts")
    func samples() {
        let cjk = FontScript.cjk.rawValue | FontScript.latin.rawValue
        #expect(FontScript.preferredSample(in: cjk) == .cjk)
        #expect(FontScript.preferredSample(in: FontScript.hangul.rawValue) == .hangul)
        #expect(FontScript.preferredSample(in: FontScript.arabic.rawValue) == .arabic)
        #expect(FontScript.preferredSample(in: FontScript.latin.rawValue) == nil)
        #expect(FontScript.preferredSample(
            in: FontScript.latin.rawValue | FontScript.greek.rawValue
        ) == nil)
        #expect(FontScript.previewText(
            mask: cjk,
            userText: "Sample"
        ) == FontScript.cjk.sampleText)
    }

    @Test("codepoint ranges are exact and round-trip through data")
    func ranges() {
        let coverage = CoverageRanges(ranges: [
            0x0041...0x005A,
            0x0061...0x007A,
            0x4E00...0x9FFF,
        ])
        #expect(coverage.contains(0x0041))
        #expect(coverage.contains(0x007A))
        #expect(!coverage.contains(0x0040))
        #expect(!coverage.contains(0x0100))
        #expect(coverage.containsAll([0x41, 0x61, 0x4E00]))
        #expect(!coverage.containsAll([0x41, 0x100]))

        let decoded = CoverageRanges(data: coverage.data)
        #expect(decoded == coverage)
    }

    @Test("preview mask requires complete sample coverage")
    func previewMask() {
        let arabic = FontScript.arabic.sampleText.unicodeScalars.map(\.value)
        let full = CoverageRanges(ranges: [
            (arabic.min() ?? 0)...(arabic.max() ?? 0)
        ])
        #expect(FontScript.previewMask(for: full) & FontScript.arabic.rawValue != 0)

        let partial = CoverageRanges(ranges: arabic.dropLast().map { $0...$0 })
        #expect(FontScript.previewMask(for: partial) & FontScript.arabic.rawValue == 0)

        let latin = FontScript.latin.sampleText.unicodeScalars.map(\.value)
        let latinCoverage = CoverageRanges(ranges: latin.map { $0...$0 })
        #expect(FontScript.previewMask(for: latinCoverage) & FontScript.latin.rawValue != 0)
    }

    @Test("indexed ranges answer family character filters")
    func characterFilter() async throws {
        let root = try makeLibrary(count: 4)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try LibraryDatabase(inMemory: true)
        _ = try await LibraryScanner(database: database).scan(folder: root)
        _ = try await CoverageIndexer(database: database).index()

        let snapshot = try database.snapshot()
        let family = try #require(snapshot.families.first)
        let coverage = try database.coverageRanges()

        #expect(snapshot.family(family, covers: [0x41], coverage: coverage))
        #expect(!snapshot.family(family, covers: [0x100], coverage: coverage))
        #expect(snapshot.family(family, covers: [], coverage: coverage))
    }

    @Test("a system Korean collection reports Hangul")
    func systemKorean() throws {
        let url = URL(fileURLWithPath: "/System/Library/Fonts/AppleSDGothicNeo.ttc")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let masks = try FontFileParser.coverage(url: url).mapValues(\.mask)
        #expect(masks.values.contains { $0 & FontScript.hangul.rawValue != 0 })
    }
}
