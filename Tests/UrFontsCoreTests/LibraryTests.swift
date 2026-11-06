import Foundation
import Testing
import UrFontsCore
import UrFontsFixtures

@Suite("Library scan and catalog")
struct LibraryTests {
    private func makeLibrary(count: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-library-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<count {
            let spec = MinimalFontSpec(index: index)
            let url = root.appendingPathComponent("\(spec.postscriptName).ttf")
            try MinimalFont.data(for: spec).write(to: url)
        }
        return root
    }

    @Test("first scan inserts, second scan skips unchanged")
    func scanAndRescan() async throws {
        let root = try makeLibrary(count: 40)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try LibraryDatabase(inMemory: true)
        let scanner = LibraryScanner(database: database)

        let first = try await scanner.scan(folder: root)
        #expect(first.scannedFiles == 40)
        #expect(first.newFiles == 40)
        #expect(first.faces == 40)
        #expect(first.failedFiles == 0)

        let second = try await scanner.scan(folder: root)
        #expect(second.newFiles == 0)
        #expect(second.changedFiles == 0)
        #expect(second.unchangedFiles == 40)

        let counts = try database.counts()
        #expect(counts.files == 40)
        #expect(counts.faces == 40)
        #expect(counts.missing == 0)
    }

    @Test("families group four styles")
    func families() async throws {
        let root = try makeLibrary(count: 40)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try LibraryDatabase(inMemory: true)
        _ = try await LibraryScanner(database: database).scan(folder: root)
        let snapshot = try database.snapshot()

        #expect(snapshot.faceCount == 40)
        #expect(snapshot.familyCount == 10)
        let first = try #require(snapshot.families.first)
        #expect(first.faceCount == 4)
        #expect(first.name == "Fixture Family 00001")
        #expect(snapshot.faces(in: first).map(\.style).sorted()
            == ["Bold", "Bold Italic", "Italic", "Regular"])
    }

    @Test("search matches family, style and postscript")
    func search() async throws {
        let root = try makeLibrary(count: 8)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try LibraryDatabase(inMemory: true)
        _ = try await LibraryScanner(database: database).scan(folder: root)
        let snapshot = try database.snapshot()

        #expect(snapshot.families(matching: "family 00002").map(\.name)
            == ["Fixture Family 00002"])
        #expect(snapshot.families(matching: "bold italic").count == 2)
        #expect(snapshot.families(matching: "FixtureFamily00001-Regular").map(\.name)
            == ["Fixture Family 00001"])
        #expect(snapshot.families(matching: "").count == 2)
    }

    @Test("punctuation-only names fall back to the file name")
    func fallbackNames() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-names-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let spec = MinimalFontSpec(
            family: ".",
            style: ".",
            postscriptName: "Dot-Regular",
            weightClass: 400,
            isItalic: false,
            isBold: false
        )
        try MinimalFont.data(for: spec)
            .write(to: root.appendingPathComponent("ABCWhyte-Variable.ttf"))

        let database = try LibraryDatabase(inMemory: true)
        _ = try await LibraryScanner(database: database).scan(folder: root)

        let raw = try database.snapshot()
        #expect(raw.families.first?.name == ".")
        #expect(CatalogSnapshot.isUselessName("."))
        #expect(CatalogSnapshot.isUselessName(".\u{7F}"))
        #expect(!CatalogSnapshot.isUselessName("TWK Everett"))

        let fallback = try database.snapshot(fallbackFileNames: true)
        let family = try #require(fallback.families.first)
        #expect(family.name == "ABCWhyte-Variable")
        #expect(fallback.faces.first?.style == "Regular")
    }

    @Test("folder labels rename without touching the path")
    func folderLabel() async throws {
        let root = try makeLibrary(count: 4)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try LibraryDatabase(inMemory: true)
        _ = try await LibraryScanner(database: database).scan(folder: root)

        let folder = try #require(try database.folders().first)
        #expect(folder.name == (root.path as NSString).lastPathComponent)

        try database.setDisplayName(folderID: folder.id, name: "Client Fonts")
        let renamed = try #require(try database.folders().first)
        #expect(renamed.name == "Client Fonts")
        #expect(renamed.path == folder.path)
        #expect(FileManager.default.fileExists(atPath: renamed.path))

        try database.setDisplayName(folderID: folder.id, name: "  ")
        let cleared = try #require(try database.folders().first)
        #expect(cleared.name == (root.path as NSString).lastPathComponent)

        try database.setKind(folderID: folder.id, kind: .watched)
        #expect(try database.folders().first?.kind == .watched)
    }

    @Test("non-Latin names get a Latin label and sort under it")
    func nonLatinNames() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-nonlatin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let specs = [
            MinimalFontSpec(
                family: "Alpha",
                style: "Regular",
                postscriptName: "Alpha-Regular",
                weightClass: 400,
                isItalic: false,
                isBold: false
            ),
            MinimalFontSpec(
                family: "بغداد",
                style: "Regular",
                postscriptName: "Baghdad-Regular",
                weightClass: 400,
                isItalic: false,
                isBold: false
            ),
        ]
        for spec in specs {
            try MinimalFont.data(for: spec)
                .write(to: root.appendingPathComponent("\(spec.postscriptName).ttf"))
        }

        let database = try LibraryDatabase(inMemory: true)
        _ = try await LibraryScanner(database: database).scan(folder: root)
        let snapshot = try database.snapshot(fallbackFileNames: true)
        let family = try #require(snapshot.families.first {
            $0.name.contains("بغداد")
        })
        #expect(family.name == "بغداد (Baghdad)")
        #expect(snapshot.families.first?.name == "Alpha")
        #expect(snapshot.families.last?.name == "بغداد (Baghdad)")
        #expect(snapshot.families(matching: "baghdad").count == 1)
    }

    @Test("delta scan touches only the paths it is given")
    func deltaScan() async throws {
        let root = try makeLibrary(count: 40)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try LibraryDatabase(inMemory: true)
        let scanner = LibraryScanner(database: database)
        _ = try await scanner.scan(folder: root)

        let changedURL = root.appendingPathComponent("FixtureFamily00001-Regular.ttf")
        try MinimalFont.data(for: MinimalFontSpec(index: 0))
            .write(to: changedURL)

        let delta = try await scanner.scan(
            changes: [changedURL.path],
            folder: root,
            kind: .staticFolder
        )
        #expect(delta.scannedFiles == 1)
        #expect(delta.changedFiles == 1)
        #expect(delta.unchangedFiles == 0)
        #expect(delta.seconds < 1)

        let removedURL = root.appendingPathComponent("FixtureFamily00002-Regular.ttf")
        try FileManager.default.removeItem(at: removedURL)
        let removal = try await scanner.scan(
            changes: [removedURL.path],
            folder: root,
            kind: .staticFolder
        )
        #expect(removal.removedFiles == 1)
        #expect(try database.counts().missing == 1)
    }

    @Test("problems report duplicate PostScript names and missing files")
    func problems() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-problems-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = MinimalFontSpec(
            family: "Alpha",
            style: "Regular",
            postscriptName: "SharedName-Regular",
            weightClass: 400,
            isItalic: false,
            isBold: false
        )
        let second = MinimalFontSpec(
            family: "Beta",
            style: "Regular",
            postscriptName: "SharedName-Regular",
            weightClass: 400,
            isItalic: false,
            isBold: false
        )
        try MinimalFont.data(for: first)
            .write(to: root.appendingPathComponent("Alpha.ttf"))
        let secondURL = root.appendingPathComponent("Beta.ttf")
        try MinimalFont.data(for: second).write(to: secondURL)

        let database = try LibraryDatabase(inMemory: true)
        let scanner = LibraryScanner(database: database)
        _ = try await scanner.scan(folder: root)

        let counts = try database.problemCounts()
        #expect(counts.duplicates == 1)
        #expect(counts.missing == 0)

        let duplicates = try database.duplicatePostScriptNames()
        #expect(duplicates.count == 1)
        #expect(duplicates.first?.name == "SharedName-Regular")
        #expect(duplicates.first?.paths.count == 2)

        try FileManager.default.removeItem(at: secondURL)
        _ = try await scanner.scan(folder: root)

        let after = try database.problemCounts()
        #expect(after.duplicates == 0)
        #expect(after.missing == 1)
        #expect(try database.problemFiles().map {
            ($0.path as NSString).lastPathComponent
        } == ["Beta.ttf"])
    }

    @Test("changed file re-parses, deleted file becomes missing")
    func changes() async throws {
        let root = try makeLibrary(count: 8)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try LibraryDatabase(inMemory: true)
        let scanner = LibraryScanner(database: database)
        _ = try await scanner.scan(folder: root)

        let firstURL = root.appendingPathComponent("FixtureFamily00001-Regular.ttf")
        try FileManager.default.removeItem(at: firstURL)
        let replacement = MinimalFont.data(for: MinimalFontSpec(index: 0))
        try replacement.write(to: firstURL)

        let second = try await scanner.scan(folder: root)
        #expect(second.changedFiles == 1)
        #expect(second.removedFiles == 0)

        try FileManager.default.removeItem(at: firstURL)
        let third = try await scanner.scan(folder: root)
        #expect(third.removedFiles == 1)

        let counts = try database.counts()
        #expect(counts.files == 8)
        #expect(counts.missing == 1)

        let snapshot = try database.snapshot()
        #expect(snapshot.faces.contains { $0.fileStatus == "missing" })
    }
}
