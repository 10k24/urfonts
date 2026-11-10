import Foundation
import GRDB

public enum FolderKind: String, Sendable, CaseIterable {
    case staticFolder = "static"
    case watched = "watched"
    /// App-managed downloads (Google Fonts). Hidden from the sidebar.
    case managed = "managed"
}

public struct FileStamp: Sendable, Equatable {
    public let inode: Int64?
    public let size: Int64
    public let modifiedNs: Int64
    public let parseVersion: Int
    public let status: String
}

public struct ExistingFile: Sendable, Equatable {
    public let id: String
    public let stamp: FileStamp
}

/// One parsed file ready to commit.
public struct FontCollection: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let sort: Int
    public let createdAt: Double
    public let faceCount: Int
}

public struct SavedSample: Sendable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var text: String
    public var size: Double
    public var textColor: String
    public var backgroundColor: String
    public var alignment: String
    public var sort: Int
    public var createdAt: Double

    public init(
        id: String,
        name: String,
        text: String,
        size: Double,
        textColor: String,
        backgroundColor: String,
        alignment: String = "left",
        sort: Int = 0,
        createdAt: Double = 0
    ) {
        self.id = id
        self.name = name
        self.text = text
        self.size = size
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.alignment = alignment
        self.sort = sort
        self.createdAt = createdAt
    }
}

public struct PendingCoverage: Sendable, Equatable {
    public let faceID: String
    public let faceIndex: Int
    public let path: String
}

public struct ActivationRecord: Sendable, Equatable {
    public let faceID: String
    public let path: String
    public let postscriptName: String
    public let scope: FontRegistrationScope
    public let source: String
}

/// One PostScript name shared by more than one file. Activating both is unsafe:
/// a running app may keep only one of them.
public struct DuplicatePostScriptName: Sendable, Equatable, Identifiable {
    public let name: String
    public let paths: [String]

    public var id: String { name }
}

public struct ProblemFile: Sendable, Equatable, Identifiable {
    public let path: String
    public let status: String
    public let familyName: String?

    public var id: String { path }
}

public struct LibraryFolder: Sendable, Identifiable, Equatable {
    public let id: String
    public let path: String
    public let kind: FolderKind
    public let available: Bool
    public let fileCount: Int
    public let displayName: String?

    /// Label only. Renaming never touches the folder on disk.
    public var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return (path as NSString).lastPathComponent
    }

    /// Three folders can all be called "Fonts". Show enough path to tell them
    /// apart, with the home directory abbreviated.
    public var displayPath: String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

public struct ScannedFile: Sendable {
    public let url: URL
    public let stamp: FileStamp
    public let faces: [ParsedFace]

    public init(url: URL, stamp: FileStamp, faces: [ParsedFace]) {
        self.url = url
        self.stamp = stamp
        self.faces = faces
    }
}

/// SQLite store. WAL, one writer, short transactions.
public final class LibraryDatabase: Sendable {
    private let queue: DatabaseQueue

    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var configuration = Configuration()
        configuration.journalMode = .wal
        queue = try DatabaseQueue(path: url.path, configuration: configuration)
        try Self.migrate(queue)
    }

    public init(inMemory: Bool = true) throws {
        queue = try DatabaseQueue()
        try Self.migrate(queue)
    }

    private static func migrate(_ queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE folder (
                    id TEXT PRIMARY KEY NOT NULL,
                    path TEXT NOT NULL UNIQUE,
                    kind TEXT NOT NULL,
                    added_at REAL NOT NULL,
                    last_scan_at REAL,
                    last_event_id INTEGER,
                    available INTEGER NOT NULL DEFAULT 1
                );
                CREATE TABLE file (
                    id TEXT PRIMARY KEY NOT NULL,
                    folder_id TEXT NOT NULL REFERENCES folder(id) ON DELETE CASCADE,
                    path TEXT NOT NULL UNIQUE,
                    inode INTEGER,
                    size INTEGER NOT NULL,
                    mtime_ns INTEGER NOT NULL,
                    parse_version INTEGER NOT NULL,
                    face_count INTEGER NOT NULL DEFAULT 0,
                    status TEXT NOT NULL,
                    first_seen REAL NOT NULL,
                    last_seen REAL NOT NULL
                );
                CREATE TABLE face (
                    id TEXT PRIMARY KEY NOT NULL,
                    file_id TEXT NOT NULL REFERENCES file(id) ON DELETE CASCADE,
                    face_index INTEGER NOT NULL,
                    postscript_name TEXT NOT NULL,
                    family_name TEXT NOT NULL,
                    style_name TEXT NOT NULL,
                    full_name TEXT NOT NULL,
                    weight_class INTEGER NOT NULL,
                    width_class INTEGER NOT NULL,
                    is_italic INTEGER NOT NULL,
                    is_variable INTEGER NOT NULL,
                    axes_json TEXT,
                    units_per_em INTEGER NOT NULL,
                    x_height REAL,
                    cap_height REAL,
                    ascender REAL,
                    descender REAL,
                    vendor_id TEXT,
                    embedding INTEGER,
                    UNIQUE(file_id, face_index)
                );
                CREATE INDEX idx_face_family ON face(family_name COLLATE NOCASE);
                CREATE INDEX idx_face_postscript ON face(postscript_name COLLATE NOCASE);
                CREATE INDEX idx_file_folder ON file(folder_id);
                CREATE INDEX idx_file_status ON file(status);
                """)
        }
        migrator.registerMigration("v2") { db in
            try db.execute(sql: """
                CREATE TABLE activation (
                    face_id TEXT PRIMARY KEY NOT NULL REFERENCES face(id) ON DELETE CASCADE,
                    scope TEXT NOT NULL,
                    source TEXT NOT NULL,
                    activated_at REAL NOT NULL
                );
                CREATE INDEX idx_activation_scope ON activation(scope);
                """)
        }
        migrator.registerMigration("v3") { db in
            try db.execute(sql: "ALTER TABLE folder ADD COLUMN display_name TEXT")
        }
        migrator.registerMigration("v4") { db in
            try db.execute(sql: "ALTER TABLE face ADD COLUMN script_mask INTEGER")
        }
        migrator.registerMigration("v5") { db in
            try db.execute(sql: """
                CREATE TABLE sample (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    text TEXT NOT NULL,
                    size REAL NOT NULL,
                    text_color TEXT NOT NULL,
                    background_color TEXT NOT NULL,
                    alignment TEXT NOT NULL DEFAULT 'left',
                    sort INTEGER NOT NULL DEFAULT 0,
                    created_at REAL NOT NULL
                );
                """)
        }
        migrator.registerMigration("v6") { db in
            try db.execute(sql: "ALTER TABLE face ADD COLUMN coverage_ranges BLOB")
        }
        migrator.registerMigration("v7") { db in
            try db.execute(sql: """
                CREATE TABLE collection (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    sort INTEGER NOT NULL DEFAULT 0,
                    created_at REAL NOT NULL
                );
                CREATE TABLE collection_item (
                    collection_id TEXT NOT NULL REFERENCES collection(id) ON DELETE CASCADE,
                    face_id TEXT NOT NULL REFERENCES face(id) ON DELETE CASCADE,
                    PRIMARY KEY (collection_id, face_id)
                );
                CREATE INDEX idx_collection_item_face ON collection_item(face_id);
                """)
        }
        migrator.registerMigration("v8") { db in
            try db.execute(sql: """
                ALTER TABLE folder ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0
                """)
            // System font folders lead by default. Everything else keeps path
            // order until the user drags it.
            let systemPaths = LibraryLocation.defaultFontFolders().map(\.path)
            let rows = try Row.fetchAll(db, sql: "SELECT id, path FROM folder")
            var idByPath: [String: String] = [:]
            for row in rows {
                idByPath[row["path"] as String] = row["id"] as String
            }
            var orderedIDs = systemPaths.compactMap { idByPath[$0] }
            let otherIDs = rows
                .map { $0["path"] as String }
                .filter { !systemPaths.contains($0) }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .compactMap { idByPath[$0] }
            orderedIDs.append(contentsOf: otherIDs)
            for (index, id) in orderedIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE folder SET sort_order = ? WHERE id = ?",
                    arguments: [index, id]
                )
            }
            // System folders are watched from now on. Users can still switch
            // them back to one-time scans from the context menu.
            for path in systemPaths {
                try db.execute(
                    sql: "UPDATE folder SET kind = ? WHERE path = ?",
                    arguments: [FolderKind.watched.rawValue, path]
                )
            }
        }
        migrator.registerMigration("v9") { db in
            try db.execute(sql: "ALTER TABLE face ADD COLUMN preview_mask INTEGER")
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, coverage_ranges FROM face WHERE coverage_ranges IS NOT NULL"
            )
            for row in rows {
                guard let data: Data = row["coverage_ranges"],
                      let ranges = CoverageRanges(data: data) else {
                    continue
                }
                let mask = FontScript.previewMask(for: ranges)
                try db.execute(
                    sql: "UPDATE face SET preview_mask = ? WHERE id = ?",
                    arguments: [Int64(bitPattern: mask), row["id"] as String]
                )
            }
        }
        migrator.registerMigration("v10") { db in
            // Paths the user chose not to index. A prefix excludes the whole
            // subtree; rows are deleted but files are never touched.
            try db.execute(sql: """
                CREATE TABLE excluded_path (
                    path TEXT PRIMARY KEY NOT NULL,
                    added_at REAL NOT NULL
                );
                """)
        }
        try migrator.migrate(queue)
    }

    // MARK: - Folders

    public func upsertFolder(path: String, kind: FolderKind) throws -> String {
        try queue.write { db in
            if let row = try Row.fetchOne(
                db,
                sql: "SELECT id FROM folder WHERE path = ?",
                arguments: [path]
            ) {
                let id: String = row["id"]
                try db.execute(
                    sql: "UPDATE folder SET kind = ?, available = 1 WHERE id = ?",
                    arguments: [kind.rawValue, id]
                )
                return id
            }
            let id = UUID().uuidString
            try db.execute(
                sql: """
                    INSERT INTO folder (id, path, kind, added_at, available, sort_order)
                    VALUES (?, ?, ?, ?, 1,
                        (SELECT COALESCE(MAX(sort_order) + 1, 0) FROM folder))
                    """,
                arguments: [id, path, kind.rawValue, Date().timeIntervalSince1970]
            )
            return id
        }
    }

    public func setFolderOrder(_ ids: [String]) throws {
        try queue.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(
                    sql: "UPDATE folder SET sort_order = ? WHERE id = ?",
                    arguments: [index, id]
                )
            }
        }
    }

    public func setDisplayName(folderID: String, name: String?) throws {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        try queue.write { db in
            try db.execute(
                sql: "UPDATE folder SET display_name = ? WHERE id = ?",
                arguments: [value, folderID]
            )
        }
    }

    public func setKind(folderID: String, kind: FolderKind) throws {
        try queue.write { db in
            try db.execute(
                sql: "UPDATE folder SET kind = ? WHERE id = ?",
                arguments: [kind.rawValue, folderID]
            )
        }
    }

    public func folderID(path: String) throws -> String? {
        try queue.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM folder WHERE path = ?", arguments: [path])
        }
    }

    /// Moves file rows whose path starts with `pathPrefix` into another folder,
    /// keeping their parsed faces. Used when a root folder should become its
    /// subfolders without re-reading every font.
    @discardableResult
    public func adoptFiles(
        fromFolderID: String,
        toFolderID: String,
        pathPrefix: String
    ) throws -> Int {
        try queue.write { db in
            try db.execute(
                sql: """
                    UPDATE file SET folder_id = ?
                    WHERE folder_id = ? AND substr(path, 1, length(?)) = ?
                    """,
                arguments: [toFolderID, fromFolderID, pathPrefix, pathPrefix]
            )
            return db.changesCount
        }
    }

    public func removeFolder(id: String) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM folder WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Excluded paths

    /// Canonical paths the user has excluded from indexing. A path excludes its
    /// whole subtree.
    public func ignoredPaths() throws -> [String] {
        try queue.read { db in
            try String.fetchAll(db, sql: "SELECT path FROM excluded_path ORDER BY path")
        }
    }

    public func ignorePath(_ path: String) throws {
        try queue.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO excluded_path (path, added_at) VALUES (?, ?)",
                arguments: [path, Date().timeIntervalSince1970]
            )
        }
    }

    public func unignorePath(_ path: String) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM excluded_path WHERE path = ?", arguments: [path])
        }
    }

    /// Deletes the file rows under a path prefix. The font files stay on disk;
    /// faces, activation rows and collection items cascade.
    @discardableResult
    public func deleteFiles(under path: String) throws -> Int {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return try queue.write { db in
            try db.execute(
                sql: "DELETE FROM file WHERE substr(path, 1, length(?)) = ?",
                arguments: [prefix, prefix]
            )
            return db.changesCount
        }
    }

    /// Deletes every file row that is not `ok`. Missing rows otherwise persist
    /// by design so collection membership and warnings survive an offline
    /// volume; this is the explicit cleanup.
    @discardableResult
    public func deleteMissingFiles() throws -> Int {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM file WHERE status <> 'ok'")
            return db.changesCount
        }
    }

    public func folders() throws -> [LibraryFolder] {
        try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT folder.id, folder.path, folder.kind, folder.available,
                       (SELECT COUNT(*) FROM file
                        WHERE substr(file.path, 1, length(folder.path) + 1)
                            = folder.path || '/') AS file_count,
                       folder.display_name
                FROM folder
                ORDER BY folder.sort_order ASC, folder.path COLLATE NOCASE ASC
                """)
            return rows.map { row in
                LibraryFolder(
                    id: row[0],
                    path: row[1],
                    kind: FolderKind(rawValue: row[2]) ?? .staticFolder,
                    available: row[3],
                    fileCount: row[4],
                    displayName: row[5]
                )
            }
        }
    }

    public func finishScan(folderID: String, at date: Date = Date()) throws {
        try queue.write { db in
            try db.execute(
                sql: "UPDATE folder SET last_scan_at = ?, available = 1 WHERE id = ?",
                arguments: [date.timeIntervalSince1970, folderID]
            )
        }
    }

    // MARK: - Change detection

    public func existingFiles(folderID: String) throws -> [String: ExistingFile] {
        try queue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, path, inode, size, mtime_ns, parse_version, status
                    FROM file WHERE folder_id = ?
                    """,
                arguments: [folderID]
            )
            var result: [String: ExistingFile] = [:]
            result.reserveCapacity(rows.count)
            for row in rows {
                let path: String = row["path"]
                result[path] = ExistingFile(
                    id: row["id"],
                    stamp: FileStamp(
                        inode: row["inode"],
                        size: row["size"],
                        modifiedNs: row["mtime_ns"],
                        parseVersion: row["parse_version"],
                        status: row["status"]
                    )
                )
            }
            return result
        }
    }

    // MARK: - Commit

    public func apply(
        folderID: String,
        parsed: [ScannedFile],
        removed: [String],
        existing: [String: ExistingFile]
    ) throws {
        guard !parsed.isEmpty || !removed.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        let encoder = JSONEncoder()

        try queue.write { db in
            for file in parsed {
                let path = file.url.path
                let fileID = existing[path]?.id ?? UUID().uuidString
                var priorActivations: [Row] = []

                if existing[path] != nil {
                    // Face IDs are stable, so activation rows can and must
                    // survive a re-parse. Deleting faces cascades them away.
                    priorActivations = try Row.fetchAll(db, sql: """
                        SELECT a.face_id, a.scope, a.source, a.activated_at
                        FROM activation a JOIN face f ON f.id = a.face_id
                        WHERE f.file_id = ?
                        """, arguments: [fileID])
                    try db.execute(sql: "DELETE FROM face WHERE file_id = ?", arguments: [fileID])
                    try db.execute(
                        sql: """
                            UPDATE file SET inode = ?, size = ?, mtime_ns = ?,
                                parse_version = ?, face_count = ?, status = 'ok',
                                last_seen = ?
                            WHERE id = ?
                            """,
                        arguments: [
                            file.stamp.inode,
                            file.stamp.size,
                            file.stamp.modifiedNs,
                            file.stamp.parseVersion,
                            file.faces.count,
                            now,
                            fileID,
                        ]
                    )
                } else {
                    try db.execute(
                        sql: """
                            INSERT INTO file (id, folder_id, path, inode, size, mtime_ns,
                                parse_version, face_count, status, first_seen, last_seen)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'ok', ?, ?)
                            """,
                        arguments: [
                            fileID,
                            folderID,
                            path,
                            file.stamp.inode,
                            file.stamp.size,
                            file.stamp.modifiedNs,
                            file.stamp.parseVersion,
                            file.faces.count,
                            now,
                            now,
                        ]
                    )
                }

                for face in file.faces {
                    let axes = face.axes.isEmpty
                        ? nil
                        : String(data: try encoder.encode(face.axes), encoding: .utf8)
                    try db.execute(
                        sql: """
                            INSERT INTO face (id, file_id, face_index, postscript_name,
                                family_name, style_name, full_name, weight_class, width_class,
                                is_italic, is_variable, axes_json, units_per_em, x_height,
                                cap_height, ascender, descender, vendor_id, embedding)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            "\(fileID):\(face.index)",
                            fileID,
                            face.index,
                            face.postscriptName,
                            face.family,
                            face.style,
                            face.fullName,
                            face.weightClass,
                            face.widthClass,
                            face.isItalic,
                            face.isVariable,
                            axes,
                            face.unitsPerEm,
                            face.xHeight,
                            face.capHeight,
                            face.ascender,
                            face.descender,
                            face.vendorID,
                            face.embedding,
                        ]
                    )
                }

                let newFaceIDs = Set(file.faces.map { "\(fileID):\($0.index)" })
                for prior in priorActivations {
                    let faceID: String = prior["face_id"]
                    guard newFaceIDs.contains(faceID) else { continue }
                    try db.execute(sql: """
                        INSERT OR REPLACE INTO activation (face_id, scope, source, activated_at)
                        VALUES (?, ?, ?, ?)
                        """, arguments: [
                            faceID,
                            prior["scope"] as String,
                            prior["source"] as String,
                            prior["activated_at"] as Double,
                        ])
                }
            }

            for path in removed {
                try db.execute(
                    sql: "UPDATE file SET status = 'missing', last_seen = ? WHERE path = ?",
                    arguments: [now, path]
                )
            }
        }
    }

    // MARK: - Activation journal

    public func activationRecords() throws -> [ActivationRecord] {
        try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT a.face_id, a.scope, a.source, file.path, f.postscript_name
                FROM activation a
                JOIN face f ON f.id = a.face_id
                JOIN file ON file.id = f.file_id
                """)
            return rows.compactMap { row in
                let scopeRaw: String = row["scope"]
                guard let scope = FontRegistrationScope(rawValue: scopeRaw) else { return nil }
                return ActivationRecord(
                    faceID: row["face_id"],
                    path: row["path"],
                    postscriptName: row["postscript_name"],
                    scope: scope,
                    source: row["source"]
                )
            }
        }
    }

    public func activeFaceIDs() throws -> Set<String> {
        try queue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT face_id FROM activation"))
        }
    }

    public func insertActivations(
        faceIDs: [String],
        scope: FontRegistrationScope,
        source: String
    ) throws {
        guard !faceIDs.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        try queue.write { db in
            for faceID in faceIDs {
                try db.execute(sql: """
                    INSERT OR REPLACE INTO activation (face_id, scope, source, activated_at)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [faceID, scope.rawValue, source, now])
            }
        }
    }

    public func deleteActivations(faceIDs: [String]) throws {
        guard !faceIDs.isEmpty else { return }
        try queue.write { db in
            let placeholders = Array(repeating: "?", count: faceIDs.count).joined(separator: ",")
            try db.execute(
                sql: "DELETE FROM activation WHERE face_id IN (\(placeholders))",
                arguments: StatementArguments(faceIDs)
            )
        }
    }

    // MARK: - Collections

    public func collections() throws -> [FontCollection] {
        try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.id, c.name, c.sort, c.created_at,
                       (SELECT COUNT(*) FROM collection_item WHERE collection_id = c.id)
                FROM collection c
                ORDER BY c.sort, c.name COLLATE NOCASE
                """)
            return rows.map {
                FontCollection(
                    id: $0[0],
                    name: $0[1],
                    sort: $0[2],
                    createdAt: $0[3],
                    faceCount: $0[4]
                )
            }
        }
    }

    public func createCollection(name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUID().uuidString
        try queue.write { db in
            let sort = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(sort), -1) + 1 FROM collection"
            ) ?? 0
            try db.execute(sql: """
                INSERT INTO collection (id, name, sort, created_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [
                    id,
                    trimmed.isEmpty ? "Untitled" : trimmed,
                    sort,
                    Date().timeIntervalSince1970,
                ])
        }
        return id
    }

    public func renameCollection(id: String, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try queue.write { db in
            try db.execute(
                sql: "UPDATE collection SET name = ? WHERE id = ?",
                arguments: [trimmed, id]
            )
        }
    }

    public func deleteCollection(id: String) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM collection WHERE id = ?", arguments: [id])
        }
    }

    public func addFaces(_ faceIDs: [String], toCollection collectionID: String) throws {
        guard !faceIDs.isEmpty else { return }
        try queue.write { db in
            for faceID in faceIDs {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO collection_item (collection_id, face_id)
                    VALUES (?, ?)
                    """, arguments: [collectionID, faceID])
            }
        }
    }

    public func removeFaces(_ faceIDs: [String], fromCollection collectionID: String) throws {
        guard !faceIDs.isEmpty else { return }
        try queue.write { db in
            for faceID in faceIDs {
                try db.execute(sql: """
                    DELETE FROM collection_item
                    WHERE collection_id = ? AND face_id = ?
                    """, arguments: [collectionID, faceID])
            }
        }
    }

    public func faceIDs(inCollection collectionID: String) throws -> Set<String> {
        try queue.read { db in
            Set(try String.fetchAll(
                db,
                sql: "SELECT face_id FROM collection_item WHERE collection_id = ?",
                arguments: [collectionID]
            ))
        }
    }

    /// faceID -> collection IDs, for checkmarks and menu state.
    public func collectionMembership() throws -> [String: Set<String>] {
        try queue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT collection_id, face_id FROM collection_item"
            )
            var result: [String: Set<String>] = [:]
            for row in rows {
                result[row[1], default: []].insert(row[0])
            }
            return result
        }
    }

    // MARK: - Samples

    public func samples() throws -> [SavedSample] {
        try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, name, text, size, text_color, background_color,
                       alignment, sort, created_at
                FROM sample
                ORDER BY sort, created_at
                """)
            return rows.map { row in
                SavedSample(
                    id: row[0],
                    name: row[1],
                    text: row[2],
                    size: row[3],
                    textColor: row[4],
                    backgroundColor: row[5],
                    alignment: row[6],
                    sort: row[7],
                    createdAt: row[8]
                )
            }
        }
    }

    public func upsertSample(_ sample: SavedSample) throws {
        try queue.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO sample
                    (id, name, text, size, text_color, background_color,
                     alignment, sort, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    sample.id,
                    sample.name,
                    sample.text,
                    sample.size,
                    sample.textColor,
                    sample.backgroundColor,
                    sample.alignment,
                    sample.sort,
                    sample.createdAt,
                ])
        }
    }

    public func deleteSample(id: String) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM sample WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Coverage index

    public func pendingCoverage(limit: Int) throws -> [PendingCoverage] {
        try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT f.id, f.face_index, file.path
                FROM face f
                JOIN file ON file.id = f.file_id
                WHERE (f.script_mask IS NULL OR f.coverage_ranges IS NULL)
                  AND file.status = 'ok'
                LIMIT ?
                """, arguments: [limit])
            return rows.map {
                PendingCoverage(faceID: $0[0], faceIndex: $0[1], path: $0[2])
            }
        }
    }

    public func setCoverage(_ values: [String: ScriptCoverage]) throws {
        guard !values.isEmpty else { return }
        try queue.write { db in
            for (faceID, coverage) in values {
                try db.execute(
                    sql: """
                        UPDATE face
                        SET script_mask = ?, preview_mask = ?, coverage_ranges = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        Int64(bitPattern: coverage.mask),
                        Int64(bitPattern: coverage.previewMask),
                        coverage.ranges.data,
                        faceID,
                    ]
                )
            }
        }
    }

    public func coverageRanges() throws -> [String: CoverageRanges] {
        try queue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, coverage_ranges FROM face WHERE coverage_ranges IS NOT NULL"
            )
            var result: [String: CoverageRanges] = [:]
            result.reserveCapacity(rows.count)
            for row in rows {
                let data: Data = row[1]
                if let ranges = CoverageRanges(data: data) {
                    result[row[0]] = ranges
                }
            }
            return result
        }
    }

    public func coverageCounts() throws -> (indexed: Int, total: Int) {
        try queue.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM face") ?? 0
            let indexed = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM face
                    WHERE script_mask IS NOT NULL AND coverage_ranges IS NOT NULL
                    """
            ) ?? 0
            return (indexed, total)
        }
    }

    // MARK: - Reads

    /// Cheap counts for the sidebar badge. The full path list is loaded only
    /// when the Problems page opens.
    public func problemCounts() throws -> (duplicates: Int, missing: Int) {
        try queue.read { db in
            let duplicates = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM (
                    SELECT lower(f.postscript_name)
                    FROM face f JOIN file ON file.id = f.file_id
                    WHERE f.postscript_name != '' AND file.status = 'ok'
                    GROUP BY lower(f.postscript_name)
                    HAVING COUNT(DISTINCT f.file_id) > 1
                )
                """) ?? 0
            let missing = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM file WHERE status != 'ok'"
            ) ?? 0
            return (duplicates, missing)
        }
    }

    public func duplicatePostScriptNames() throws -> [DuplicatePostScriptName] {
        try queue.read { db in
            // Group case-insensitively to match the catalog's duplicate check.
            // PostScript names are ASCII, so SQLite's lower() is enough.
            let rows = try Row.fetchAll(db, sql: """
                SELECT f.postscript_name, file.path
                FROM face f
                JOIN file ON file.id = f.file_id
                WHERE f.postscript_name != ''
                  AND file.status = 'ok'
                  AND lower(f.postscript_name) IN (
                      SELECT lower(f2.postscript_name)
                      FROM face f2 JOIN file file2 ON file2.id = f2.file_id
                      WHERE file2.status = 'ok'
                        AND f2.postscript_name != ''
                      GROUP BY lower(f2.postscript_name)
                      HAVING COUNT(DISTINCT f2.file_id) > 1
                  )
                GROUP BY lower(f.postscript_name), file.path
                ORDER BY lower(f.postscript_name), file.path
                """)
            var order: [String] = []
            var names: [String: String] = [:]
            var paths: [String: [String]] = [:]
            for row in rows {
                let name: String = row[0]
                let path: String = row[1]
                let key = name.lowercased()
                if paths[key] == nil {
                    order.append(key)
                    names[key] = name
                    paths[key] = []
                }
                paths[key]?.append(path)
            }
            return order.map {
                DuplicatePostScriptName(name: names[$0] ?? $0, paths: paths[$0] ?? [])
            }
        }
    }

    public func problemFiles() throws -> [ProblemFile] {
        try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT file.path, file.status,
                       (SELECT family_name FROM face WHERE file_id = file.id LIMIT 1)
                FROM file
                WHERE file.status != 'ok'
                ORDER BY file.path
                """)
            return rows.map { row in
                ProblemFile(
                    path: row[0],
                    status: row[1],
                    familyName: row[2]
                )
            }
        }
    }

    public func counts() throws -> (files: Int, faces: Int, missing: Int) {
        try queue.read { db in
            let files = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM file") ?? 0
            let faces = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM face") ?? 0
            let missing = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM file WHERE status != 'ok'"
            ) ?? 0
            return (files, faces, missing)
        }
    }

    public func snapshot(fallbackFileNames: Bool = false) throws -> CatalogSnapshot {
        try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT f.id AS face_id, f.file_id, f.face_index, f.postscript_name,
                       f.family_name, f.style_name, f.full_name, f.weight_class,
                       f.width_class, f.is_italic, f.is_variable, f.axes_json,
                       f.units_per_em, f.x_height, f.cap_height, f.ascender,
                       f.descender, f.vendor_id, f.embedding,
                       file.path, file.status, f.script_mask, f.preview_mask
                FROM face f
                JOIN file ON file.id = f.file_id
                """)

            var faces: [CatalogFace] = []
            faces.reserveCapacity(rows.count)
            let decoder = JSONDecoder()
            var familyKeys: [String: String] = [:]
            familyKeys.reserveCapacity(rows.count / 4 + 1)
            for row in rows {
                // Positional reads: tens of thousands of rows times 22 columns
                // is worth it.
                let path: String = row[19]
                let scriptMaskValue: Int64? = row[21]
                let scriptMask = UInt64(max(0, scriptMaskValue ?? 0))
                let previewMaskValue: Int64? = row[22]
                let previewMask = UInt64(max(0, previewMaskValue ?? 0))
                var family: String = row[4]
                var style: String = row[5]
                if fallbackFileNames {
                    if CatalogSnapshot.isUselessName(family) {
                        // Prefer a filename, then the font's own full name, then
                        // its PostScript name. Only leave punctuation if every
                        // source is useless.
                        let fullName: String = row[6]
                        let postscript: String = row[3]
                        let candidates = [
                            CatalogSnapshot.fileStem(path),
                            fullName,
                            postscript,
                        ]
                        if let replacement = candidates.first(
                            where: { !CatalogSnapshot.isUselessName($0) }
                        ) {
                            family = replacement
                        }
                    }
                    if CatalogSnapshot.isUselessName(style) {
                        style = "Regular"
                    }
                }
                let familyKey = familyKeys[family] ?? {
                    let key = CatalogSnapshot.familyKey(family)
                    familyKeys[family] = key
                    return key
                }()
                let axesJSON: String? = row[11]
                let axes = axesJSON
                    .flatMap { $0.data(using: .utf8) }
                    .flatMap { try? decoder.decode([FontAxis].self, from: $0) } ?? []
                faces.append(CatalogFace(
                    id: row[0],
                    fileID: row[1],
                    path: path,
                    fileStatus: row[20],
                    index: row[2],
                    family: family,
                    familyKey: familyKey,
                    style: style,
                    fullName: row[6],
                    postscriptName: row[3],
                    weightClass: row[7],
                    widthClass: row[8],
                    isItalic: row[9],
                    isVariable: row[10],
                    axes: axes,
                    unitsPerEm: row[12],
                    xHeight: row[13],
                    capHeight: row[14],
                    ascender: row[15],
                    descender: row[16],
                    vendorID: row[17],
                    embedding: row[18],
                    scriptMask: scriptMask,
                    previewMask: previewMask
                ))
            }
            return CatalogSnapshot.build(faces: faces)
        }
    }
}
