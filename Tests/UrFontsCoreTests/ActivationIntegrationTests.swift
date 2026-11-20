import Foundation
import Testing
import UrFontsCore
import UrFontsFixtures

/// Opt-in: touches the real font registry. Run with
/// `URFONTS_REAL_ACTIVATION=1 swift test --filter realFontdRoundTrip`.
@Suite("Activation integration")
struct ActivationIntegrationTests {
    @Test(
        "real fontd round trip",
        .enabled(if: ProcessInfo.processInfo.environment["URFONTS_REAL_ACTIVATION"] == "1")
    )
    func realFontdRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-real-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<4 {
            let spec = MinimalFontSpec(index: index)
            try MinimalFont.data(for: spec).write(
                to: root.appendingPathComponent("\(spec.postscriptName).ttf")
            )
        }

        let database = try LibraryDatabase(inMemory: true)
        _ = try await LibraryScanner(database: database).scan(folder: root)
        let engine = ActivationEngine(database: database)
        let snapshot = try database.snapshot()
        let family = try #require(snapshot.families.first)
        let targets = snapshot.faces(in: family).map {
            ActivationTarget(faceID: $0.id, path: $0.path, postscriptName: $0.postscriptName)
        }

        let on = await engine.activate(targets)
        #expect(on.activated == 4)
        #expect(on.failures.isEmpty)
        #expect(try database.activeFaceIDs().count == 4)

        for target in targets {
            let scope = CoreTextRegistrar().scope(of: URL(fileURLWithPath: target.path))
            #expect(scope == .user)
        }

        let off = await engine.deactivate(targets)
        #expect(off.deactivated == 4)
        #expect(try database.activeFaceIDs().isEmpty)

        for target in targets {
            let scope = CoreTextRegistrar().scope(of: URL(fileURLWithPath: target.path))
            #expect(scope == .none)
        }
    }

    @Test(
        "duplicate PostScript names register together",
        .enabled(if: ProcessInfo.processInfo.environment["URFONTS_REAL_ACTIVATION"] == "1")
    )
    func duplicatePostScriptRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-real-duplicate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let specs = [
            MinimalFontSpec(
                family: "UrFonts Duplicate Fixture",
                style: "Regular",
                postscriptName: "UrFontsDuplicateFixture-Shared",
                weightClass: 400,
                isItalic: false,
                isBold: false
            ),
            MinimalFontSpec(
                family: "UrFonts Duplicate Fixture",
                style: "Bold",
                postscriptName: "UrFontsDuplicateFixture-Shared",
                weightClass: 700,
                isItalic: false,
                isBold: true
            ),
        ]
        for spec in specs {
            try MinimalFont.data(for: spec).write(
                to: root.appendingPathComponent("\(spec.style).ttf")
            )
        }

        let database = try LibraryDatabase(inMemory: true)
        _ = try await LibraryScanner(database: database).scan(folder: root)
        let engine = ActivationEngine(database: database)
        let snapshot = try database.snapshot()
        let targets = snapshot.faces.map {
            ActivationTarget(faceID: $0.id, path: $0.path, postscriptName: $0.postscriptName)
        }

        let on = await engine.activate(targets)
        #expect(on.activated == 2)
        #expect(on.failures.isEmpty)

        let off = await engine.deactivate(targets)
        #expect(off.deactivated == 2)
        #expect(try database.activeFaceIDs().isEmpty)
    }
}
