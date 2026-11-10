import Foundation

public struct ScanReport: Sendable, Equatable {
    public let folder: String
    public let scannedFiles: Int
    public let newFiles: Int
    public let changedFiles: Int
    public let unchangedFiles: Int
    public let removedFiles: Int
    public let failedFiles: Int
    public let faces: Int
    public let seconds: Double

    public var summary: String {
        String(
            format: "scanned %d files, new %d, changed %d, unchanged %d, removed %d, failed %d, fonts %d, %.2f s",
            scannedFiles, newFiles, changedFiles, unchangedFiles,
            removedFiles, failedFiles, faces, seconds
        )
    }
}

public enum ScanError: Error, Equatable {
    case unreadableFolder
}

/// Walks a folder, parses only what changed, commits in one transaction.
///
/// The stamp map makes a rescan of an unchanged large library mostly stat calls.
/// Parsing runs in bounded task groups; each file is read once.
public actor LibraryScanner {
    private let database: LibraryDatabase
    private let fontExtensions: Set<String> = ["ttf", "otf", "ttc", "otc", "dfont"]

    public init(database: LibraryDatabase) {
        self.database = database
    }

    public func scan(
        folder url: URL,
        kind: FolderKind = .staticFolder,
        force: Bool = false
    ) async throws -> ScanReport {
        let started = Date()
        // FileManager and FSEvents return `/private/var/...` for `/var/...`.
        // Foundation's URL helpers do not normalize that firmlink; realpath does.
        let folderPath = canonicalPath(url.path)
        let folderID = try database.upsertFolder(path: folderPath, kind: kind)
        let roots = try database.folders()
        let skip = try skipPrefixes(for: folderPath, roots: roots)
        try adoptFromAncestors(folderID: folderID, path: folderPath, roots: roots)
        let existing = try database.existingFiles(folderID: folderID)

        guard let candidates = enumerate(
            folder: URL(fileURLWithPath: folderPath),
            ignoring: skip
        ) else {
            throw ScanError.unreadableFolder
        }

        let currentVersion = FontFileParser.version
        var pending: [(url: URL, stamp: FileStamp)] = []
        var seen = Set<String>()
        seen.reserveCapacity(candidates.count)
        var unchanged = 0
        var newFiles = 0
        var changedFiles = 0

        for candidate in candidates {
            guard seen.insert(candidate.url.path).inserted else { continue }
            if let known = existing[candidate.url.path],
               !force,
               known.stamp.status == "ok",
               known.stamp.size == candidate.stamp.size,
               known.stamp.modifiedNs == candidate.stamp.modifiedNs,
               known.stamp.inode == candidate.stamp.inode,
               known.stamp.parseVersion == currentVersion {
                unchanged += 1
                continue
            }
            pending.append(candidate)
            if existing[candidate.url.path] == nil {
                newFiles += 1
            } else {
                changedFiles += 1
            }
        }

        let removed = existing.compactMap { path, file in
            seen.contains(path) || file.stamp.status != "ok" ? nil : path
        }

        let parsed = await parse(candidates: pending)
        let failed = pending.count - parsed.count

        try database.apply(
            folderID: folderID,
            parsed: parsed,
            removed: removed,
            existing: existing
        )
        try database.finishScan(folderID: folderID)

        return ScanReport(
            folder: folderPath,
            scannedFiles: candidates.count,
            newFiles: newFiles,
            changedFiles: changedFiles,
            unchangedFiles: unchanged,
            removedFiles: removed.count,
            failedFiles: failed,
            faces: parsed.reduce(0) { $0 + $1.faces.count },
            seconds: Date().timeIntervalSince(started)
        )
    }

    /// Delta scan driven by watcher paths. Only those files are statted and,
    /// when changed, parsed. A directory event is the caller's cue to do a full
    /// scan of that folder.
    public func scan(
        changes paths: [String],
        folder url: URL,
        kind: FolderKind = .watched
    ) async throws -> ScanReport {
        let started = Date()
        let folderPath = canonicalPath(url.path)
        let folderID = try database.upsertFolder(path: folderPath, kind: kind)
        let roots = try database.folders()
        let skip = try skipPrefixes(for: folderPath, roots: roots)
        try adoptFromAncestors(folderID: folderID, path: folderPath, roots: roots)
        let existing = try database.existingFiles(folderID: folderID)
        let manager = FileManager.default

        var pending: [(url: URL, stamp: FileStamp)] = []
        var removed: [String] = []
        var unchanged = 0
        var newFiles = 0
        var changedFiles = 0
        var seen = 0

        for rawPath in Set(paths) {
            let path = canonicalPath(rawPath)
            guard !skip.contains(where: { LibraryPath.isInside(path, root: $0) }) else {
                continue
            }
            let fileURL = URL(fileURLWithPath: path)
            guard fontExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            seen += 1

            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: path, isDirectory: &isDirectory) else {
                if existing[path] != nil { removed.append(path) }
                continue
            }
            guard !isDirectory.boolValue else { continue }
            guard let stamp = stamp(for: fileURL) else { continue }

            if let known = existing[path],
               known.stamp.status == "ok",
               known.stamp.size == stamp.size,
               known.stamp.modifiedNs == stamp.modifiedNs,
               known.stamp.inode == stamp.inode,
               known.stamp.parseVersion == stamp.parseVersion {
                unchanged += 1
                continue
            }
            pending.append((fileURL, stamp))
            if existing[path] == nil {
                newFiles += 1
            } else {
                changedFiles += 1
            }
        }

        let parsed = await parse(candidates: pending)
        let failed = pending.count - parsed.count
        try database.apply(
            folderID: folderID,
            parsed: parsed,
            removed: removed,
            existing: existing
        )
        try database.finishScan(folderID: folderID)

        return ScanReport(
            folder: folderPath,
            scannedFiles: seen,
            newFiles: newFiles,
            changedFiles: changedFiles,
            unchangedFiles: unchanged,
            removedFiles: removed.count,
            failedFiles: failed,
            faces: parsed.reduce(0) { $0 + $1.faces.count },
            seconds: Date().timeIntervalSince(started)
        )
    }

    // MARK: - Internals

    /// Kept as a private seam so scanner call sites stay short.
    private func canonicalPath(_ path: String) -> String {
        LibraryPath.canonical(path)
    }

    private func resourceKeys() -> Set<URLResourceKey> {
        [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
        ]
    }

    private func stamp(for url: URL) -> FileStamp? {
        guard let values = try? url.resourceValues(forKeys: resourceKeys()),
              values.isRegularFile == true else {
            return nil
        }
        let size = Int64(values.fileSize ?? 0)
        let seconds = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return FileStamp(
            inode: (values.fileResourceIdentifier as? NSNumber)?.int64Value,
            size: size,
            modifiedNs: Int64((seconds * 1_000_000_000).rounded()),
            parseVersion: FontFileParser.version,
            status: "ok"
        )
    }

    private func enumerate(
        folder: URL,
        ignoring ignored: [String]
    ) -> [(url: URL, stamp: FileStamp)]? {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return nil
        }

        var result: [(url: URL, stamp: FileStamp)] = []
        while let item = enumerator.nextObject() as? URL {
            let path = item.path
            if ignored.contains(where: { LibraryPath.isInside(path, root: $0) }) {
                // Skip the whole subtree; an ignored folder can hold many files.
                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory ?? false
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard fontExtensions.contains(item.pathExtension.lowercased()) else { continue }
            guard let stamp = stamp(for: item) else { continue }
            result.append((item, stamp))
        }
        return result
    }

    /// Ignored subtrees plus subtrees owned by a deeper indexed root. A parent
    /// scan must not touch files that belong to a nested root.
    private func skipPrefixes(
        for folderPath: String,
        roots: [LibraryFolder]
    ) throws -> [String] {
        let deeper = roots
            .map(\.path)
            .filter { $0 != folderPath && LibraryPath.isInside($0, root: folderPath) }
        return Array(Set(try ignoredPrefixes()).union(deeper))
    }

    /// The deepest root owns each file. When a nested root starts scanning it
    /// takes over rows from every ancestor instead of failing on the unique
    /// file path.
    private func adoptFromAncestors(
        folderID: String,
        path folderPath: String,
        roots: [LibraryFolder]
    ) throws {
        let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        for root in roots
        where root.id != folderID && LibraryPath.isInside(folderPath, root: root.path) {
            try database.adoptFiles(
                fromFolderID: root.id,
                toFolderID: folderID,
                pathPrefix: prefix
            )
        }
    }

    /// Canonical ignored prefixes with no trailing slash.
    private func ignoredPrefixes() throws -> [String] {
        try database.ignoredPaths().map {
            $0.hasSuffix("/") ? String($0.dropLast()) : $0
        }
    }

    private func parse(candidates: [(url: URL, stamp: FileStamp)]) async -> [ScannedFile] {
        guard !candidates.isEmpty else { return [] }

        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let chunkSize = max(1, candidates.count / (cores * 2))
        var chunks: [[(url: URL, stamp: FileStamp)]] = []
        var index = 0
        while index < candidates.count {
            let end = min(index + chunkSize, candidates.count)
            chunks.append(Array(candidates[index..<end]))
            index = end
        }

        return await withTaskGroup(of: [ScannedFile].self) { group in
            for chunk in chunks {
                group.addTask {
                    chunk.compactMap { candidate in
                        guard let faces = try? FontFileParser.parse(url: candidate.url) else {
                            return nil
                        }
                        return ScannedFile(
                            url: candidate.url,
                            stamp: candidate.stamp,
                            faces: faces
                        )
                    }
                }
            }
            var parsed: [ScannedFile] = []
            parsed.reserveCapacity(candidates.count)
            for await chunk in group {
                parsed.append(contentsOf: chunk)
            }
            return parsed
        }
    }
}
