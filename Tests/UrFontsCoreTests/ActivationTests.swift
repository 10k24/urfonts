import Foundation
import Testing
import UrFontsCore
import UrFontsFixtures

@Suite("Activation")
struct ActivationTests {
    private final class FakeRegistrar: FontRegistrar, @unchecked Sendable {
        private let lock = NSLock()
        private var scopes: [String: FontRegistrationScope] = [:]
        private var registrations = 0

        var registerCalls: Int {
            lock.lock()
            defer { lock.unlock() }
            return registrations
        }

        func register(_ urls: [URL], scope: FontRegistrationScope) -> RegistrationReport {
            lock.lock()
            for url in urls { scopes[url.path] = scope }
            registrations += 1
            lock.unlock()
            return RegistrationReport(
                requestedCount: urls.count,
                confirmedCount: urls.count,
                failures: []
            )
        }

        func unregister(_ urls: [URL], scope: FontRegistrationScope) -> RegistrationReport {
            lock.lock()
            for url in urls { scopes[url.path] = .none }
            lock.unlock()
            return RegistrationReport(
                requestedCount: urls.count,
                confirmedCount: urls.count,
                failures: []
            )
        }

        func scope(of url: URL) -> FontRegistrationScope {
            lock.lock()
            defer { lock.unlock() }
            return scopes[url.path] ?? .none
        }

        func forgetEverything() {
            lock.lock()
            scopes.removeAll()
            lock.unlock()
        }
    }

    private func makeLibrary(count: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-activation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<count {
            let spec = MinimalFontSpec(index: index)
            try MinimalFont.data(for: spec).write(
                to: root.appendingPathComponent("\(spec.postscriptName).ttf")
            )
        }
        return root
    }

    private func targets(
        for family: CatalogFamily,
        in snapshot: CatalogSnapshot
    ) -> [ActivationTarget] {
        snapshot.faces(in: family).map {
            ActivationTarget(faceID: $0.id, path: $0.path, postscriptName: $0.postscriptName)
        }
    }

    @Test("activate, deactivate and journal survive a re-parse")
    func lifecycle() async throws {
        let root = try makeLibrary(count: 8)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try LibraryDatabase(inMemory: true)
        let scanner = LibraryScanner(database: database)
        _ = try await scanner.scan(folder: root)
        let registrar = FakeRegistrar()
        let engine = ActivationEngine(database: database, registrar: registrar)

        let snapshot = try database.snapshot()
        let family = try #require(snapshot.families.first { $0.name == "Fixture Family 00001" })
        let familyTargets = targets(for: family, in: snapshot)

        let activated = await engine.activate(familyTargets)
        #expect(activated.activated == 4)
        #expect(activated.failures.isEmpty)
        #expect(try database.activeFaceIDs().count == 4)
        #expect(registrar.registerCalls == 1)

        // A second activation is a no-op on fontd.
        let again = await engine.activate(familyTargets)
        #expect(again.activated == 4)
        #expect(registrar.registerCalls == 1)

        // Reparse a file with an active face; the journal must survive.
        let one = familyTargets[0]
        try MinimalFont.data(for: MinimalFontSpec(index: 0)).write(to: URL(fileURLWithPath: one.path))
        _ = try await scanner.scan(folder: root)
        #expect(try database.activeFaceIDs().count == 4)

        let deactivated = await engine.deactivate(familyTargets)
        #expect(deactivated.deactivated == 4)
        #expect(try database.activeFaceIDs().isEmpty)
    }

    @Test("reconcile drops rows fontd no longer knows")
    func reconcile() async throws {
        let root = try makeLibrary(count: 4)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try LibraryDatabase(inMemory: true)
        _ = try await LibraryScanner(database: database).scan(folder: root)
        let registrar = FakeRegistrar()
        let engine = ActivationEngine(database: database, registrar: registrar)
        let snapshot = try database.snapshot()
        let family = try #require(snapshot.families.first)

        _ = await engine.activate(targets(for: family, in: snapshot))
        #expect(try database.activeFaceIDs().count == 4)

        registrar.forgetEverything()
        let outcome = await engine.reconcile()
        #expect(outcome.dropped == 4)
        #expect(try database.activeFaceIDs().isEmpty)
    }

    @Test("system Fonts folders are never toggled")
    func installedFonts() async throws {
        let root = try makeLibrary(count: 4)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try LibraryDatabase(inMemory: true)
        _ = try await LibraryScanner(database: database).scan(folder: root)
        let registrar = FakeRegistrar()
        let engine = ActivationEngine(database: database, registrar: registrar)
        let snapshot = try database.snapshot()
        let face = try #require(snapshot.faces.first)

        let installed = ActivationTarget(
            faceID: face.id,
            path: "/System/Library/Fonts/Fixture.ttf",
            postscriptName: face.postscriptName
        )
        let outcome = await engine.activate([installed])
        #expect(outcome.installedSkipped == 1)
        #expect(outcome.activated == 0)
        #expect(registrar.registerCalls == 0)
    }

    @Test("duplicate PostScript names activate together")
    func duplicates() async throws {
        let root = try makeLibrary(count: 8)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try LibraryDatabase(inMemory: true)
        _ = try await LibraryScanner(database: database).scan(folder: root)
        let registrar = FakeRegistrar()
        let engine = ActivationEngine(database: database, registrar: registrar)
        let snapshot = try database.snapshot()
        let faces = Array(snapshot.faces.prefix(2))

        let targets = [
            ActivationTarget(faceID: faces[0].id, path: faces[0].path, postscriptName: "Duplicate"),
            ActivationTarget(faceID: faces[1].id, path: faces[1].path, postscriptName: "Duplicate"),
        ]
        let outcome = await engine.activate(targets)
        #expect(outcome.activated == 2)
        #expect(outcome.failures.isEmpty)
        #expect(try database.activeFaceIDs().count == 2)
    }
}
