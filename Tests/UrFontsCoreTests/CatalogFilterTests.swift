import Foundation
import Testing
import UrFontsCore
import UrFontsFixtures

@Suite("Catalog filters")
struct CatalogFilterTests {
    private func makeLibrary() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-filter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let fonts: [MinimalFontSpec] = [
            MinimalFontSpec(
                family: "Alpha",
                style: "Regular",
                postscriptName: "Alpha-Regular",
                weightClass: 400,
                isItalic: false,
                isBold: false
            ),
            MinimalFontSpec(
                family: "Beta",
                style: "Regular",
                postscriptName: "Beta-Regular",
                weightClass: 400,
                isItalic: false,
                isBold: false
            ),
            MinimalFontSpec(
                family: "Beta",
                style: "Italic",
                postscriptName: "Beta-Italic",
                weightClass: 400,
                isItalic: true,
                isBold: false
            ),
            MinimalFontSpec(
                family: "Beta",
                style: "Bold",
                postscriptName: "Beta-Bold",
                weightClass: 700,
                isItalic: false,
                isBold: true
            ),
        ]
        for spec in fonts {
            try MinimalFont.data(for: spec)
                .write(to: root.appendingPathComponent("\(spec.postscriptName).ttf"))
        }
        return root
    }

    @Test("kind, italic and bold facets")
    func facets() async throws {
        let root = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try LibraryDatabase(inMemory: true)
        _ = try await LibraryScanner(database: database).scan(folder: root)
        let snapshot = try database.snapshot()

        var filter = CatalogFilter()
        #expect(snapshot.families(matching: "", filter: filter).count == 2)

        filter.kind = .staticFont
        #expect(snapshot.families(matching: "", filter: filter).count == 2)

        filter.kind = .variable
        #expect(snapshot.families(matching: "", filter: filter).isEmpty)

        filter = CatalogFilter()
        filter.requiresItalic = true
        #expect(snapshot.families(matching: "", filter: filter).map(\.name) == ["Beta"])

        filter = CatalogFilter()
        filter.requiresBold = true
        #expect(snapshot.families(matching: "", filter: filter).map(\.name) == ["Beta"])

        filter.requiresItalic = true
        #expect(snapshot.families(matching: "", filter: filter).map(\.name) == ["Beta"])
        #expect(snapshot.families(matching: "alpha", filter: filter).isEmpty)
    }
}
