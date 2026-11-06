import Foundation
import Testing
import UrFontsCore
import UrFontsFixtures

@Suite("Collections")
struct CollectionTests {
    private func makeLibrary(count: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-collection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<count {
            let spec = MinimalFontSpec(index: index)
            try MinimalFont.data(for: spec)
                .write(to: root.appendingPathComponent("\(spec.postscriptName).ttf"))
        }
        return root
    }

    @Test("create, add, rename and delete a collection")
    func lifecycle() async throws {
        let root = try makeLibrary(count: 8)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try LibraryDatabase(inMemory: true)
        _ = try await LibraryScanner(database: database).scan(folder: root)
        let snapshot = try database.snapshot()
        let family = try #require(snapshot.families.first)
        let faceIDs = snapshot.faces(in: family).map(\.id)

        let id = try database.createCollection(name: "Client A")
        try database.addFaces(faceIDs, toCollection: id)

        var collections = try database.collections()
        #expect(collections.count == 1)
        #expect(collections[0].name == "Client A")
        #expect(collections[0].faceCount == faceIDs.count)

        let storedFaces = try database.faceIDs(inCollection: id)
        #expect(storedFaces == Set(faceIDs))
        #expect(try database.collectionMembership()[faceIDs[0]]?.contains(id) == true)

        let contained = snapshot.families(containingAny: storedFaces)
        #expect(contained.map(\.id) == [family.id])
        #expect(snapshot.families(containingAny: []).isEmpty)

        try database.renameCollection(id: id, name: "Client B")
        #expect(try database.collections()[0].name == "Client B")

        try database.removeFaces([faceIDs[0]], fromCollection: id)
        #expect(try database.faceIDs(inCollection: id).count == faceIDs.count - 1)

        try database.deleteCollection(id: id)
        #expect(try database.collections().isEmpty)
        #expect(try database.collectionMembership().isEmpty)
    }

    @Test("a missing file keeps its collection membership")
    func missingFile() async throws {
        let root = try makeLibrary(count: 4)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try LibraryDatabase(inMemory: true)
        let scanner = LibraryScanner(database: database)
        _ = try await scanner.scan(folder: root)
        let snapshot = try database.snapshot()
        let face = try #require(snapshot.faces.first)

        let id = try database.createCollection(name: "Temp")
        try database.addFaces([face.id], toCollection: id)

        try FileManager.default.removeItem(at: URL(fileURLWithPath: face.path))
        _ = try await scanner.scan(folder: root)
        _ = try database.snapshot()

        // Faces are retained as missing so the collection survives a volume
        // being offline or a file moving back.
        #expect(try database.faceIDs(inCollection: id) == [face.id])
    }
}
