import Foundation
import GRDB

public enum FolderKind: String, Sendable, CaseIterable {
    case staticFolder = "static"
    case watched = "watched"
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
public struct ActivationRecord: Sendable, Equatable {
    public let faceID: String
    public let path: String
    public let postscriptName: String
    public let scope: FontRegistrationScope
    public let source: String
}

public struct LibraryFolder: Sendable, Identifiable, Equatable {
    public let id: String
    public let path: String
    public let kind: FolderKind
    public let available: Bool
    public let fileCount: Int

    public var name: String {
        (path as NSString).lastPathComponent
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
                    INSERT INTO folder (id, path, kind, added_at, available)
                    VALUES (?, ?, ?, ?, 1)
                    """,
                arguments: [id, path, kind.rawValue, Date().timeIntervalSince1970]
            )
            return id
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
                    WHERE folder_id = ? AND substr(path, 1, ?) = ?
                    """,
                arguments: [toFolderID, fromFolderID, pathPrefix.count, pathPrefix]
            )
            return db.changesCount
        }
    }

    public func removeFolder(id: String) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM folder WHERE id = ?", arguments: [id])
        }
    }

    public func folders() throws -> [LibraryFolder] {
        try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT folder.id, folder.path, folder.kind, folder.available,
                       (SELECT COUNT(*) FROM file WHERE file.folder_id = folder.id) AS file_count
                FROM folder
                ORDER BY folder.path COLLATE NOCASE
                """)
            return rows.map { row in
                LibraryFolder(
                    id: row[0],
                    path: row[1],
                    kind: FolderKind(rawValue: row[2]) ?? .staticFolder,
                    available: row[3],
                    fileCount: row[4]
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

    // MARK: - Reads

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

    public func snapshot() throws -> CatalogSnapshot {
        try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT f.id AS face_id, f.file_id, f.face_index, f.postscript_name,
                       f.family_name, f.style_name, f.full_name, f.weight_class,
                       f.width_class, f.is_italic, f.is_variable, f.axes_json,
                       f.units_per_em, f.x_height, f.cap_height, f.ascender,
                       f.descender, f.vendor_id, f.embedding,
                       file.path, file.status
                FROM face f
                JOIN file ON file.id = f.file_id
                """)

            var faces: [CatalogFace] = []
            faces.reserveCapacity(rows.count)
            let decoder = JSONDecoder()
            var familyKeys: [String: String] = [:]
            familyKeys.reserveCapacity(rows.count / 4 + 1)
            for row in rows {
                // Positional reads: 23,000 rows times 21 columns is worth it.
                let family: String = row[4]
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
                    path: row[19],
                    fileStatus: row[20],
                    index: row[2],
                    family: family,
                    familyKey: familyKey,
                    style: row[5],
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
                    embedding: row[18]
                ))
            }
            return CatalogSnapshot.build(faces: faces)
        }
    }
}
