import Foundation
import UrFontsCore

/// Small command line surface. Phase 0 uses it to validate fixtures and fontd
/// behaviour outside the app; later phases reuse it for automation.

let registrar = CoreTextRegistrar()

func expand(_ paths: [String]) -> [URL] {
    let manager = FileManager.default
    var urls: [URL] = []
    let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "otc", "dfont"]
    for path in paths {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            FileHandle.standardError.write(Data("missing: \(path)\n".utf8))
            continue
        }
        if !isDirectory.boolValue {
            urls.append(url)
            continue
        }
        guard let enumerator = manager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { continue }
        for case let child as URL in enumerator where fontExtensions.contains(child.pathExtension.lowercased()) {
            urls.append(child)
        }
    }
    return urls
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func argumentValue(_ name: String, in arguments: inout [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return value
}

func databaseURL(_ arguments: inout [String]) throws -> URL {
    if let path = argumentValue("--db", in: &arguments) {
        return URL(fileURLWithPath: path)
    }
    return try LibraryLocation.defaultDatabaseURL()
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print("usage: urfonts-cli <index|search|stats|inspect|activate|deactivate|scope> [options] <path>...")
    exit(1)
}
arguments.removeFirst()

switch command {
case "index":
    let database = try LibraryDatabase(url: databaseURL(&arguments))
    let kind = FolderKind(rawValue: argumentValue("--kind", in: &arguments) ?? "static") ?? .staticFolder
    let force = arguments.contains("--force")
    arguments.removeAll { $0 == "--force" }
    guard !arguments.isEmpty else { fail("index needs at least one folder") }

    let scanner = LibraryScanner(database: database)
    for path in arguments {
        let report = try await scanner.scan(
            folder: URL(fileURLWithPath: path),
            kind: kind,
            force: force
        )
        print(report.summary)
    }
    let counts = try database.counts()
    print("database: \(counts.files) files, \(counts.faces) fonts, \(counts.missing) missing")
    exit(0)

case "search":
    let database = try LibraryDatabase(url: databaseURL(&arguments))
    let limit = Int(argumentValue("--limit", in: &arguments) ?? "20") ?? 20
    let query = arguments.joined(separator: " ")
    let started = Date()
    let snapshot = try database.snapshot()
    let loadMs = Date().timeIntervalSince(started) * 1000
    let matches = snapshot.families(matching: query, limit: limit)

    for family in matches {
        let faces = snapshot.faces(in: family)
        let styles = faces.map(\.style).joined(separator: ", ")
        print("\(family.name)\t\(family.faceCount) styles\t\(styles)")
    }
    print(String(
        format: "%d families, %d fonts, snapshot %.1f ms, %d matches",
        snapshot.familyCount, snapshot.faceCount, loadMs, matches.count
    ))
    exit(0)

case "stats":
    let database = try LibraryDatabase(url: databaseURL(&arguments))
    let started = Date()
    let snapshot = try database.snapshot()
    let loadMs = Date().timeIntervalSince(started) * 1000
    let counts = try database.counts()
    print("files \(counts.files), fonts \(counts.faces), missing \(counts.missing)")
    print(String(
        format: "families %d, snapshot %.1f ms",
        snapshot.familyCount, loadMs
    ))
    exit(0)

case "google-catalog":
    let families = try await GoogleFontsService.shared.catalog()
    let withFiles = families.filter { !$0.files.isEmpty }
    print("\(families.count) families, \(withFiles.count) with files")
    for family in families.prefix(5) {
        print("\(family.name)\t\(family.category)\t\(family.files.count) files")
    }
    exit(0)

case "google-download":
    guard let name = arguments.first else {
        fail("google-download needs a family name")
    }
    let families = try await GoogleFontsService.shared.catalog()
    guard let family = families.first(where: {
        $0.name.caseInsensitiveCompare(name) == .orderedSame
    }) else {
        fail("not in the Google Fonts catalog: \(name)")
    }
    let base = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let root = base
        .appendingPathComponent("Ur Fonts", isDirectory: true)
        .appendingPathComponent("GoogleFonts", isDirectory: true)
        .appendingPathComponent("Fonts", isDirectory: true)
    let directory = root.appendingPathComponent(
        GoogleFontFamily.folderName(for: family),
        isDirectory: true
    )
    let urls = try await GoogleFontsService.shared.download(family, to: directory)
    print("downloaded \(urls.count) files to \(directory.path)")
    exit(0)

case "index-coverage":
    let database = try LibraryDatabase(url: databaseURL(&arguments))
    let batch = Int(argumentValue("--batch", in: &arguments) ?? "200") ?? 200
    let indexer = CoverageIndexer(database: database)
    let indexed = try await indexer.index(batchSize: batch) { progress in
        print("indexed \(progress.indexed) / \(progress.total)")
    }
    print("coverage indexed \(indexed) fonts")
    exit(0)

case "folders":
    let database = try LibraryDatabase(url: databaseURL(&arguments))
    for folder in try database.folders() {
        print("\(folder.fileCount)\t\(folder.kind.rawValue)\t\(folder.path)")
    }
    exit(0)

case "split-folder":
    let url = try databaseURL(&arguments)
    guard let oldPath = arguments.first, arguments.count > 1 else {
        fail("usage: split-folder <old-folder> <child-folder>...")
    }
    arguments.removeFirst()
    let standardizedOld = URL(fileURLWithPath: oldPath).standardizedFileURL.path
    let database = try LibraryDatabase(url: url)
    guard let oldID = try database.folderID(path: standardizedOld) else {
        fail("not in library: \(standardizedOld)")
    }
    for child in arguments {
        let standardizedChild = URL(fileURLWithPath: child).standardizedFileURL.path
        guard standardizedChild.hasPrefix(standardizedOld + "/") else {
            fail("not inside \(standardizedOld): \(standardizedChild)")
        }
        let childID = try database.upsertFolder(path: standardizedChild, kind: .staticFolder)
        let moved = try database.adoptFiles(
            fromFolderID: oldID,
            toFolderID: childID,
            pathPrefix: standardizedChild + "/"
        )
        print("\(moved)\t\(standardizedChild)")
    }
    try database.removeFolder(id: oldID)
    print("removed \(standardizedOld)")
    exit(0)

case "remove-folder":
    let url = try databaseURL(&arguments)
    guard let path = arguments.first else { fail("remove-folder needs a path") }
    let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
    let database = try LibraryDatabase(url: url)
    guard let id = try database.folderID(path: standardized) else {
        fail("not in library: \(standardized)")
    }
    try database.removeFolder(id: id)
    print("removed \(standardized)")
    exit(0)

case "inspect":
    var failed = false
    for url in expand(arguments) {
        let faces = FontFileReader.faces(at: url)
        if faces.isEmpty {
            print("\(url.path)\tno fonts")
            failed = true
            continue
        }
        for face in faces {
            print("\(face.postscriptName)\t\(face.family)\t\(face.style)\tindex \(face.index)\t\(url.path)")
        }
    }
    exit(failed ? 1 : 0)

case "activate", "deactivate":
    let temporary = arguments.contains("--temp")
    arguments.removeAll { $0 == "--temp" }
    let timing = arguments.contains("--timing")
    arguments.removeAll { $0 == "--timing" }
    var limit: Int?
    if let value = argumentValue("--limit", in: &arguments) {
        guard let parsed = Int(value), parsed > 0 else { fail("--limit needs a positive integer") }
        limit = parsed
    }
    var urls = expand(arguments)
    if let limit { urls = Array(urls.prefix(limit)) }
    guard !urls.isEmpty else { fail("no font files") }

    let started = Date()
    let report = command == "activate"
        ? registrar.register(urls, scope: temporary ? .session : .user)
        : registrar.unregister(urls, scope: temporary ? .session : .user)
    let elapsed = Date().timeIntervalSince(started) * 1000

    if timing {
        print(String(format: "%@ %d files in %.0f ms", command, urls.count, elapsed))
    }
    print("confirmed \(report.confirmedCount) of \(report.requestedCount)")
    for failure in report.failures {
        print("failure: \(failure.message)")
        for url in failure.urls.prefix(5) {
            print("  \(url.lastPathComponent)")
        }
    }
    exit(report.succeeded ? 0 : 1)

case "scope":
    var registered = 0
    for url in expand(arguments) {
        let scope = registrar.scope(of: url)
        if scope.isRegistered { registered += 1 }
        print("\(scope.rawValue)\t\(url.path)")
    }
    exit(registered > 0 ? 0 : 1)

case "version":
    print("urfonts-cli 0.1")
    exit(0)

default:
    fail("unknown command: \(command)")
}
