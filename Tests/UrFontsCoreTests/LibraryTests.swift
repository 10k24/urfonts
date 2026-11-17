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

    @Test("folders keep insertion order and reorder by id")
    func folderOrder() throws {
        let database = try LibraryDatabase(inMemory: true)
        let first = try database.upsertFolder(path: "/A", kind: .staticFolder)
        let second = try database.upsertFolder(path: "/B", kind: .staticFolder)
        let third = try database.upsertFolder(path: "/C", kind: .staticFolder)
        #expect(try database.folders().map(\.path) == ["/A", "/B", "/C"])

        try database.setFolderOrder([third, second, first])
        #expect(try database.folders().map(\.path) == ["/C", "/B", "/A"])

        _ = try database.upsertFolder(path: "/D", kind: .watched)
        #expect(try database.folders().map(\.path) == ["/C", "/B", "/A", "/D"])
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

    @Test("families expose duplicate PostScript and missing file counts")
    func duplicateMetadata() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-duplicates-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let spec = MinimalFontSpec(
            family: "Referential Test",
            style: "Regular",
            postscriptName: "ReferentialTest-Regular",
            weightClass: 400,
            isItalic: false,
            isBold: false
        )
        let first = root.appendingPathComponent("ReferentialTest-A.otf")
        let second = root.appendingPathComponent("ReferentialTest-B.otf")
        try MinimalFont.data(for: spec).write(to: first)
        try MinimalFont.data(for: spec).write(to: second)

        let database = try LibraryDatabase(inMemory: true)
        let scanner = LibraryScanner(database: database)
        _ = try await scanner.scan(folder: root)

        let family = try #require(try database.snapshot().families.first)
        #expect(family.faceCount == 2)
        #expect(family.hasDuplicatePostScriptNames)
        #expect(family.missingFaceCount == 0)

        try FileManager.default.removeItem(at: second)
        _ = try await scanner.scan(folder: root)
        let after = try #require(try database.snapshot().families.first)
        #expect(after.faceCount == 2)
        #expect(!after.hasDuplicatePostScriptNames)
        #expect(after.missingFaceCount == 1)
    }

    @Test("placeholder PostScript names are not faces or warnings")
    func placeholderNames() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-placeholder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let spec = MinimalFontSpec(
            family: "Placeholder Test",
            style: "Regular",
            postscriptName: "false",
            weightClass: 400,
            isItalic: false,
            isBold: false
        )
        try MinimalFont.data(for: spec)
            .write(to: root.appendingPathComponent("Placeholder-A.ttf"))
        try MinimalFont.data(for: spec)
            .write(to: root.appendingPathComponent("Placeholder-B.ttf"))

        let database = try LibraryDatabase(inMemory: true)
        _ = try await LibraryScanner(database: database).scan(folder: root)

        #expect(try database.counts().files == 2)
        #expect(try database.snapshot().faceCount == 0)
        #expect(try database.problemCounts().duplicates == 0)
        #expect(try database.problemFiles().isEmpty)
    }

    @Test("scoped subtree scan removes only files under that subtree")
    func subtreeScan() async throws {
        let root = try makeLibrary(count: 0)
        defer { try? FileManager.default.removeItem(at: root) }
        let keep = root.appendingPathComponent("Keep", isDirectory: true)
        let drop = root.appendingPathComponent("Drop", isDirectory: true)
        try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: drop, withIntermediateDirectories: true)

        let keepSpec = MinimalFontSpec(index: 0)
        let dropSpec = MinimalFontSpec(index: 1)
        try MinimalFont.data(for: keepSpec)
            .write(to: keep.appendingPathComponent("Keep.ttf"))
        let dropURL = drop.appendingPathComponent("Drop.ttf")
        try MinimalFont.data(for: dropSpec).write(to: dropURL)

        let database = try LibraryDatabase(inMemory: true)
        let scanner = LibraryScanner(database: database)
        _ = try await scanner.scan(folder: root)
        #expect(try database.counts().files == 2)

        try FileManager.default.removeItem(at: dropURL)
        let report = try await scanner.scan(
            subtree: drop.path,
            folder: root,
            kind: .staticFolder
        )
        #expect(report.hasChanges)
        #expect(report.removedFiles == 1)
        #expect(try database.counts().files == 2)
        #expect(try database.counts().missing == 1)
        #expect(try database.folders().count == 1)

        let again = try await scanner.scan(
            subtree: drop.path,
            folder: root,
            kind: .staticFolder
        )
        #expect(!again.hasChanges)
    }

    @Test("canonical paths resolve the /var firmlink")
    func canonicalPaths() {
        let path = FileManager.default.temporaryDirectory.path
        let canonical = LibraryPath.canonical(path)
        #expect(canonical.hasPrefix("/private/var/"))
        #expect(LibraryPath.canonical(canonical) == canonical)
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
            postscriptName: "sharedname-regular",
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

    @Test("ignored folders leave scans and rows, and return when unignored")
    func ignoredFolders() async throws {
        let root = try makeLibrary(count: 4)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("Caché", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        for index in 4..<6 {
            let spec = MinimalFontSpec(index: index)
            try MinimalFont.data(for: spec)
                .write(to: cache.appendingPathComponent("\(spec.postscriptName).ttf"))
        }

        let database = try LibraryDatabase(inMemory: true)
        let scanner = LibraryScanner(database: database)
        let first = try await scanner.scan(folder: root)
        #expect(first.scannedFiles == 6)

        let canonicalCache = LibraryPath.canonical(cache.path)
        try database.ignorePath(canonicalCache)
        #expect(try database.deleteFiles(under: canonicalCache) == 2)
        #expect(try database.ignoredPaths() == [canonicalCache])

        let rescan = try await scanner.scan(folder: root)
        #expect(rescan.scannedFiles == 4)
        #expect(try database.counts().files == 4)

        let ignoredFile = cache.appendingPathComponent("FixtureFamily00005-Regular.ttf")
        let delta = try await scanner.scan(
            changes: [ignoredFile.path],
            folder: root,
            kind: .staticFolder
        )
        #expect(delta.scannedFiles == 0)
        #expect(try database.counts().files == 4)

        try database.unignorePath(canonicalCache)
        _ = try await scanner.scan(folder: root)
        #expect(try database.counts().files == 6)
    }

    @Test("ignored folders survive reopening the database")
    func ignoredFoldersPersist() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.sqlite3")
        let ignored = directory.appendingPathComponent("Cache").path

        do {
            let database = try LibraryDatabase(url: url)
            try database.ignorePath(ignored)
        }

        let reopened = try LibraryDatabase(url: url)
        #expect(try reopened.ignoredPaths() == [ignored])
    }

    @Test("collections are listed alphabetically")
    func collectionsAlphabetical() throws {
        let database = try LibraryDatabase(inMemory: true)
        _ = try database.createCollection(name: "zebra")
        _ = try database.createCollection(name: "Alpha")
        _ = try database.createCollection(name: "beta")

        #expect(try database.collections().map(\.name) == ["Alpha", "beta", "zebra"])
    }

    @Test("missing cleanup deletes only unavailable rows")
    func removeMissing() async throws {
        let root = try makeLibrary(count: 4)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try LibraryDatabase(inMemory: true)
        let scanner = LibraryScanner(database: database)
        _ = try await scanner.scan(folder: root)
        let collectionID = try database.createCollection(name: "Keep")
        try database.addFaces(
            try database.snapshot().faces.map(\.id),
            toCollection: collectionID
        )

        let removedFile = root.appendingPathComponent("FixtureFamily00001-Regular.ttf")
        try FileManager.default.removeItem(at: removedFile)
        _ = try await scanner.scan(folder: root)
        #expect(try database.counts().missing == 1)

        #expect(try database.deleteMissingFiles() == 1)
        let counts = try database.counts()
        #expect(counts.files == 3)
        #expect(counts.missing == 0)
        #expect(try database.problemFiles().isEmpty)
        #expect(try database.faceIDs(inCollection: collectionID).count == 3)
    }

    @Test("cloud placeholders are skipped without warning rows")
    func cloudPlaceholders() async throws {
        let root = try makeLibrary(count: 1)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try LibraryDatabase(inMemory: true)
        let placeholderScanner = LibraryScanner(
            database: database,
            cloudPlaceholderCheck: { _, _ in true }
        )

        // A file that was never indexed gets no row and no warning.
        let unseen = try await placeholderScanner.scan(folder: root)
        #expect(unseen.skippedCloud == 1)
        #expect(try database.counts().files == 0)
        #expect(try database.counts().missing == 0)
        #expect(try database.problemFiles().isEmpty)
        #expect(try database.problemCounts().missing == 0)

        // An indexed file that becomes online-only keeps its faces.
        _ = try await LibraryScanner(database: database).scan(folder: root)
        let report = try await placeholderScanner.scan(folder: root)
        #expect(report.skippedCloud == 1)
        #expect(report.removedFiles == 0)
        #expect(try database.counts().files == 1)
        #expect(try database.counts().missing == 0)
        #expect(try database.problemFiles().isEmpty)
        #expect(try database.problemCounts().missing == 0)
        let family = try #require(try database.snapshot().families.first)
        #expect(family.missingFaceCount == 0)
        #expect(!family.countLabel.contains("cloud"))
        #expect(try database.deleteMissingFiles() == 0)

        // Materialized files return to normal on the next scan.
        _ = try await LibraryScanner(database: database).scan(folder: root)
        #expect(try database.counts().files == 1)
        #expect(try database.counts().missing == 0)
    }

    @Test("concurrent scans of one new file do not collide")
    func concurrentDeltaScan() async throws {
        let root = try makeLibrary(count: 0)
        defer { try? FileManager.default.removeItem(at: root) }
        let spec = MinimalFontSpec(index: 0)
        let url = root.appendingPathComponent("\(spec.postscriptName).ttf")
        try MinimalFont.data(for: spec).write(to: url)

        let database = try LibraryDatabase(inMemory: true)
        async let first = LibraryScanner(database: database).scan(
            changes: [url.path],
            folder: root,
            kind: .staticFolder
        )
        async let second = LibraryScanner(database: database).scan(
            changes: [url.path],
            folder: root,
            kind: .staticFolder
        )
        _ = try await (first, second)

        let counts = try database.counts()
        #expect(counts.files == 1)
        #expect(counts.faces == 1)
    }

    @Test("canonical paths resolve the ~ and trailing slash")
    func resolvedPaths() {
        let home = LibraryPath.resolve("~")
        #expect(home == LibraryPath.canonical(NSHomeDirectory()))
        let temp = FileManager.default.temporaryDirectory.path
        #expect(LibraryPath.resolve(temp + "/") == LibraryPath.canonical(temp))
        #expect(LibraryPath.relation(temp + "/a", temp) == .descendant)
        #expect(LibraryPath.relation(temp, temp + "/a") == .ancestor)
        #expect(LibraryPath.relation(temp, temp) == .same)
        #expect(LibraryPath.relation(temp, "/") == .descendant)
        #expect(LibraryPath.relation("/a/b", "/a/bc") == .unrelated)
    }

    @Test("nested roots: the deepest root owns each file")
    func nestedRoots() async throws {
        let root = try makeLibrary(count: 2)
        defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        for index in 2..<4 {
            let spec = MinimalFontSpec(index: index)
            try MinimalFont.data(for: spec)
                .write(to: child.appendingPathComponent("\(spec.postscriptName).ttf"))
        }

        let database = try LibraryDatabase(inMemory: true)
        let scanner = LibraryScanner(database: database)

        // Child first, then parent: the parent must not steal the child rows.
        _ = try await scanner.scan(folder: child)
        _ = try await scanner.scan(folder: root)
        var folders = try database.folders()
        let childFolder = try #require(folders.first { $0.path == LibraryPath.resolve(child.path) })
        let rootFolder = try #require(folders.first { $0.path == LibraryPath.resolve(root.path) })
        #expect(try database.existingFiles(folderID: childFolder.id).count == 2)
        #expect(try database.existingFiles(folderID: rootFolder.id).count == 2)

        // Rescanning the parent still leaves the child rows alone.
        _ = try await scanner.scan(folder: root)
        folders = try database.folders()
        #expect(try database.existingFiles(folderID: childFolder.id).count == 2)
        #expect(try database.existingFiles(folderID: rootFolder.id).count == 2)

        // Adding the child after the parent adopts the rows from the parent.
        let otherRoot = try makeLibrary(count: 2)
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let otherChild = otherRoot.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(
            at: otherChild,
            withIntermediateDirectories: true
        )
        for index in 4..<6 {
            let spec = MinimalFontSpec(index: index)
            try MinimalFont.data(for: spec)
                .write(to: otherChild.appendingPathComponent("\(spec.postscriptName).ttf"))
        }
        _ = try await scanner.scan(folder: otherRoot)
        _ = try await scanner.scan(folder: otherChild)
        folders = try database.folders()
        let adoptedChild = try #require(
            folders.first { $0.path == LibraryPath.resolve(otherChild.path) }
        )
        let adoptedRoot = try #require(
            folders.first { $0.path == LibraryPath.resolve(otherRoot.path) }
        )
        #expect(try database.existingFiles(folderID: adoptedChild.id).count == 2)
        #expect(try database.existingFiles(folderID: adoptedRoot.id).count == 2)
    }
}
