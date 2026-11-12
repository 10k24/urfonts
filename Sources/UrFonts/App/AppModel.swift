import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI
import UrFontsCore

enum BrowserViewMode: String, CaseIterable {
    case list
    case grid
}

/// `nil` selection would make the All Fonts row unselectable: SwiftUI reads a
/// nil tag as "no selection". A real enum gives every row an identity.
enum SidebarSelection: Hashable {
    case active
    case all
    case folder(String)
    case subfolder(String)
    case collection(String)
    case problems
    case googleFonts
}

enum FamilyActivation: Equatable {
    case none
    case partial
    case all
    case installed
    case missing
    case blocked(ownerPath: String)

    var canToggle: Bool {
        switch self {
        case .installed, .missing, .blocked:
            return false
        case .none, .partial, .all:
            return true
        }
    }
}

/// Per-file state shown in the font sheet. A duplicate PostScript name is
/// blocked, not merely rejected after the click.
enum FaceActivationState: Equatable {
    case available
    case active
    case installed
    case missing
    case blocked(ownerPath: String)
}

struct FolderAddEntry: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let kind: FolderKind
}

/// A user add that overlaps the library or ignored list. The warning is shown
/// once, then the add proceeds if the user confirms.
struct PendingFolderAdd: Identifiable {
    let id = UUID()
    let entries: [FolderAddEntry]
    let warnings: [String]
}

@MainActor
@Observable
final class AppModel {
    var snapshot: CatalogSnapshot = .empty
    var folders: [LibraryFolder] = [] {
        didSet {
            rebuildVisible()
            rebuildFolderCounts()
            rebuildFolderTrees()
        }
    }
    var selection: SidebarSelection = .all {
        didSet {
            rebuildVisible()
            if selection == .problems {
                isLoadingProblems = true
                Task { await loadProblems() }
            }
        }
    }
    var query: String = "" {
        didSet { rebuildVisible() }
    }
    var filter = CatalogFilter() {
        didSet { rebuildVisible() }
    }
    var visibleFamilies: [CatalogFamily] = []
    var selectionFontCount = 0
    var visibleFontCount = 0
    var collections: [FontCollection] = []
    var collectionFontCounts: [String: Int] = [:]
    var folderFontCounts: [String: Int] = [:]
    var folderTreeRoots: [FolderNode] = []
    /// Canonical directories excluded from indexing. The sidebar keeps a row so
    /// the exclusion stays reversible.
    var ignoredPaths: [String] = [] {
        didSet { rebuildFolderTrees() }
    }
    var viewMode: BrowserViewMode = .list

    var showSystemFonts: Bool =
        UserDefaults.standard.object(forKey: AppModel.showSystemFontsKey) as? Bool ?? true {
        didSet {
            if !suppressSystemFontPersistence {
                UserDefaults.standard.set(showSystemFonts, forKey: AppModel.showSystemFontsKey)
            }
            rebuildVisible()
        }
    }

    private static let showSystemFontsKey = "urfonts.showSystemFonts"

    /// Headless runs must not rewrite the user's saved preference.
    func setShowSystemFonts(_ value: Bool, persist: Bool) {
        suppressSystemFontPersistence = !persist
        showSystemFonts = value
        suppressSystemFontPersistence = false
    }
    var isLoading = true
    var status = ""
    var errorMessage: String?
    var pendingFolderAdd: PendingFolderAdd?
    var googleRefreshRequest = 0

    private static let log = Logger(
        subsystem: "com.10k24.urfonts",
        category: "library"
    )

    /// Raw errors go to the log. The UI gets only safe, mapped text.
    func report(_ error: Error, context: String = "library") {
        errorMessage = userMessage(for: error, context: context)
    }

    func userMessage(for error: Error, context: String = "library") -> String {
        Self.log.error(
            "\(context, privacy: .public): \(String(describing: error), privacy: .public)"
        )
        if let settings = error as? SettingsError,
           let text = settings.errorDescription {
            return text
        }
        return LibraryErrorText.message(for: error)
    }
    var activeFaceIDs: Set<String> = []
    var activePostScriptOwners: [String: String] = [:]
    var duplicateCount = 0
    var missingFileCount = 0
    var duplicates: [DuplicatePostScriptName] = []
    var problemFiles: [ProblemFile] = []
    var isLoadingProblems = false

    var problemCount: Int { duplicateCount + missingFileCount }
    var coverageIndexed = 0
    var coverageTotal = 0
    var isIndexingCoverage = false
    var samples: [SavedSample] = []
    var selectedSampleID: String?

    var selectedSample: SavedSample? {
        guard let selectedSampleID else { return nil }
        return samples.first { $0.id == selectedSampleID }
    }

    var sampleIsDirty: Bool {
        guard let baseline = selectedSample else { return false }
        return baseline.text != sampleText
            || baseline.size != sampleSize
            || baseline.textColor != textColor.hexRGBA
            || baseline.backgroundColor != backgroundColor.hexRGBA
    }

    // Preview settings. Persisted later with the rest of the user data.
    var sampleText = "Hamburgefonstiv"
    var sampleSize: Double = 42
    var textColor: Color = Color(nsColor: .labelColor)
    var backgroundColor: Color = Color(nsColor: .textBackgroundColor)

    /// Trial fonts sometimes carry a bare "." as their family name. When this
    /// is on, the snapshot falls back to the file name instead.
    var fallbackFileNames: Bool =
        UserDefaults.standard.object(forKey: AppModel.fallbackNamesKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(fallbackFileNames, forKey: AppModel.fallbackNamesKey)
            Task { await reload() }
        }
    }

    private static let fallbackNamesKey = "urfonts.fallbackFileNames"

    @ObservationIgnored private var database: LibraryDatabase?
    @ObservationIgnored private var scanner: LibraryScanner?
    @ObservationIgnored private var activationEngine: ActivationEngine?
    @ObservationIgnored private var coverageIndexer: CoverageIndexer?
    @ObservationIgnored private var coverageRangesByFace: [String: CoverageRanges]?
    @ObservationIgnored private var catalogRevision = 0
    @ObservationIgnored private var suppressSystemFontPersistence = false
    @ObservationIgnored private var visibleCache: VisibleResult?
    @ObservationIgnored private var collectionFaceIDsCache: [String: Set<String>] = [:]
    @ObservationIgnored private var collectionMembershipCache: [String: Set<String>]?
    @ObservationIgnored private var googleFacesCache: (
        revision: Int,
        byFolder: [String: [CatalogFace]],
        byPath: [String: [CatalogFace]]
    )?

    private struct VisibleKey: Equatable {
        let query: String
        let filter: CatalogFilter
        let selection: SidebarSelection
        let revision: Int
        let showSystemFonts: Bool
    }

    /// Rows and their face counts live together so the status text never has
    /// to walk the snapshot on a render.
    private struct VisibleResult {
        let key: VisibleKey
        let rows: [CatalogFamily]
        let selectionFonts: Int
        let visibleFonts: Int
    }

    /// The face set behind a sidebar selection. Family rows can include faces
    /// from outside a folder, so counts use paths and collection membership,
    /// never the sum of a family's faces.
    private enum VisibleScope {
        case all
        case active
        case path(String)
        case faces(Set<String>)
    }

    private func scopeFaceCount(
        _ scope: VisibleScope,
        familyIDs: Set<String>?
    ) -> Int {
        switch scope {
        case .all:
            guard let familyIDs else { return snapshot.faceCount }
            return snapshot.faces.reduce(0) {
                $0 + (familyIDs.contains($1.familyKey) ? 1 : 0)
            }
        case .active:
            return snapshot.faces.reduce(0) { count, face in
                guard activeFaceIDs.contains(face.id) else { return count }
                if let familyIDs, !familyIDs.contains(face.familyKey) {
                    return count
                }
                return count + 1
            }
        case .path(let path):
            return snapshot.faces.reduce(0) { count, face in
                guard LibraryPath.isInside(face.path, root: path) else { return count }
                if let familyIDs, !familyIDs.contains(face.familyKey) {
                    return count
                }
                return count + 1
            }
        case .faces(let ids):
            return snapshot.faces.reduce(0) { count, face in
                guard ids.contains(face.id) else { return count }
                if let familyIDs, !familyIDs.contains(face.familyKey) {
                    return count
                }
                return count + 1
            }
        }
    }
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var pendingChanges: [String: Set<String>] = [:]
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var sweepTask: Task<Void, Never>?
    @ObservationIgnored private var folderFamilyIDs: [String: Set<String>] = [:]
    @ObservationIgnored private let initialFolders: [URL]
    @ObservationIgnored private let databaseURL: URL?

    init() {
        var folders: [URL] = []
        var databasePath: String?
        var arguments = CommandLine.arguments.dropFirst().makeIterator()
        while let argument = arguments.next() {
            switch argument {
            case "--folder":
                if let value = arguments.next() {
                    folders.append(
                        URL(fileURLWithPath: LibraryPath.resolve(value))
                    )
                }
            case "--db":
                databasePath = arguments.next()
            default:
                break
            }
        }
        initialFolders = folders
        databaseURL = databasePath.map {
            URL(fileURLWithPath: LibraryPath.resolve($0))
        } ?? (try? LibraryLocation.defaultDatabaseURL())
    }

    // MARK: - Lifecycle

    func start() async {
        guard database == nil else { return }
        guard let databaseURL else {
            errorMessage = "No library database location."
            isLoading = false
            return
        }
        do {
            let database = try LibraryDatabase(url: databaseURL)
            self.database = database
            scanner = LibraryScanner(database: database)
            activationEngine = ActivationEngine(database: database)
            coverageIndexer = CoverageIndexer(database: database)

            var seededDefaults = false
            if initialFolders.isEmpty,
               !CommandLine.arguments.contains("--headless"),
               try database.folders().isEmpty {
                for url in LibraryLocation.defaultFontFolders() {
                    await addFolder(url, kind: .watched)
                }
                seededDefaults = true
            }

            await reload()
            refreshActive()
            refreshCoverage()
            samples = try database.samples()
            folders = try database.folders()
            collections = try database.collections()
            rebuildCollectionCounts()
            isLoading = false
            setupWatching()
            Task { await reconcileActivation() }
            Task { await syncGoogleFonts() }

            if !initialFolders.isEmpty {
                for folder in initialFolders {
                    await addFolder(folder)
                }
            } else if !seededDefaults,
                      !folders.isEmpty,
                      !CommandLine.arguments.contains("--no-rescan") {
                Task { await rescanAll() }
            }
        } catch {
            report(error)
            isLoading = false
        }
    }

    func reload() async {
        guard let database else { return }
        let fallback = fallbackFileNames
        do {
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try database.snapshot(fallbackFileNames: fallback)
            }.value
            self.snapshot = snapshot
            let ignored = (try? database.ignoredPaths()) ?? []
            if ignoredPaths != ignored {
                ignoredPaths = ignored
            }
            folderFamilyIDs.removeAll(keepingCapacity: true)
            coverageRangesByFace = nil
            collectionMembershipCache = nil
            collectionFaceIDsCache.removeAll()
            catalogRevision &+= 1
            visibleCache = nil
            rebuildVisible()
            rebuildFolderCounts()
            rebuildFolderTrees()
            rebuildCollectionCounts()
            refreshCoverage()
            refreshProblemCounts()
            folders = (try? database.folders()) ?? folders
            if selection == .problems {
                await loadProblems()
            }
        } catch {
            report(error)
        }
    }

    // MARK: - Problems

    func refreshProblemCounts() {
        guard let database else { return }
        if let counts = try? database.problemCounts() {
            duplicateCount = counts.duplicates
            missingFileCount = counts.missing
        }
    }

    /// The row paths are loaded only when the page opens. Counts stay available
    /// for the sidebar badge.
    func loadProblems() async {
        guard let database else { return }
        isLoadingProblems = true
        let result = await Task.detached(priority: .userInitiated) {
            () -> ([DuplicatePostScriptName], [ProblemFile]) in
            let duplicates = (try? database.duplicatePostScriptNames()) ?? []
            let files = (try? database.problemFiles()) ?? []
            return (duplicates, files)
        }.value
        duplicates = result.0
        problemFiles = result.1
        isLoadingProblems = false
    }

    // MARK: - Coverage

    func refreshCoverage() {
        guard let database else { return }
        if let counts = try? database.coverageCounts() {
            coverageIndexed = counts.indexed
            coverageTotal = counts.total
        }
    }

    func indexCoverage() async {
        guard let coverageIndexer else { return }
        guard !isIndexingCoverage else { return }
        isIndexingCoverage = true
        do {
            _ = try await coverageIndexer.index { [weak self] progress in
                Task { @MainActor in
                    self?.coverageIndexed = progress.indexed
                    self?.coverageTotal = progress.total
                }
            }
            await reload()
        } catch {
            report(error)
        }
        refreshCoverage()
        isIndexingCoverage = false
    }

    // MARK: - Collections

    private func collectionFaceIDs(_ id: String) -> Set<String> {
        if let cached = collectionFaceIDsCache[id] { return cached }
        guard let database else { return [] }
        let ids = (try? database.faceIDs(inCollection: id)) ?? []
        collectionFaceIDsCache[id] = ids
        return ids
    }

    private func collectionMembership() -> [String: Set<String>] {
        if let collectionMembershipCache { return collectionMembershipCache }
        let loaded = (try? database?.collectionMembership()) ?? [:]
        collectionMembershipCache = loaded
        return loaded
    }

    func isInCollection(_ family: CatalogFamily, _ collectionID: String) -> Bool {
        let membership = collectionMembership()
        return snapshot.faces(in: family).contains { face in
            membership[face.id]?.contains(collectionID) == true
        }
    }

    func rebuildFolderCounts() {
        guard !folders.isEmpty else {
            folderFontCounts = [:]
            return
        }
        var fontsByFolder: [String: Int] = [:]
        for face in snapshot.faces {
            for folder in folders
            where LibraryPath.isInside(face.path, root: folder.path) {
                fontsByFolder[folder.id, default: 0] += 1
            }
        }
        folderFontCounts = fontsByFolder
    }

    func rebuildFolderTrees() {
        final class Builder {
            let name: String
            let path: String
            var children: [String: Builder] = [:]
            var fonts = 0
            var ignored = false

            init(name: String, path: String) {
                self.name = name
                self.path = path
            }
        }

        func convert(
            _ builder: Builder,
            folderID: String?,
            watched: Bool
        ) -> FolderNode {
            let children = builder.children.values
                .sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                .map { convert($0, folderID: nil, watched: false) }
            return FolderNode(
                id: builder.path,
                name: builder.name,
                fontCount: builder.fonts,
                children: children.isEmpty ? nil : children,
                folderID: folderID,
                isWatched: watched,
                isIgnored: builder.ignored
            )
        }

        /// Walks an ignored path, creating the intermediate rows so the
        /// exclusion stays visible and can be undone.
        func markIgnored(_ ignoredPath: String, from root: Builder) {
            var node = root
            var path = root.path.hasSuffix("/") ? root.path : root.path + "/"
            guard ignoredPath.hasPrefix(path) else { return }
            for component in ignoredPath.dropFirst(path.count).split(separator: "/") {
                path += String(component) + "/"
                let key = String(component)
                let child = node.children[key] ?? Builder(name: key, path: path)
                node.children[key] = child
                node = child
            }
            node.ignored = true
        }

        var roots: [FolderNode] = []
        for folder in displayFolders {
            let root = Builder(
                name: folderTitles[folder.id] ?? folder.name,
                path: folder.path
            )
            let prefix = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
            for face in snapshot.faces where face.path.hasPrefix(prefix) {
                root.fonts += 1
                let components = face.path
                    .dropFirst(prefix.count)
                    .split(separator: "/")
                    .dropLast()
                var node = root
                var path = prefix
                for component in components {
                    path += String(component) + "/"
                    let key = String(component)
                    let child = node.children[key]
                        ?? Builder(name: key, path: path)
                    node.children[key] = child
                    child.fonts += 1
                    node = child
                }
            }
            if ignoredPaths.contains(where: {
                folder.path == $0 || folder.path.hasPrefix($0 + "/")
            }) {
                root.ignored = true
            }
            for ignoredPath in ignoredPaths {
                if ignoredPath == folder.path {
                    root.ignored = true
                } else {
                    markIgnored(ignoredPath, from: root)
                }
            }
            roots.append(convert(
                root,
                folderID: folder.id,
                watched: folder.kind == .watched
            ))
        }
        folderTreeRoots = roots
    }

    func rebuildCollectionCounts() {
        let membership = collectionMembership()
        var fontsByCollection: [String: Int] = [:]
        for face in snapshot.faces {
            for collectionID in membership[face.id] ?? [] {
                fontsByCollection[collectionID, default: 0] += 1
            }
        }
        collectionFontCounts = fontsByCollection
    }

    func refreshCollections() {
        guard let database else { return }
        collections = (try? database.collections()) ?? []
        collectionFaceIDsCache.removeAll()
        collectionMembershipCache = nil
        rebuildCollectionCounts()
    }

    @discardableResult
    func createCollection(named name: String, family: CatalogFamily? = nil) -> String? {
        guard let database else { return nil }
        do {
            let id = try database.createCollection(name: name)
            if let family {
                let faces = snapshot.faces(in: family).map(\.id)
                try database.addFaces(faces, toCollection: id)
            }
            refreshCollections()
            return id
        } catch {
            report(error)
            return nil
        }
    }

    func renameCollection(_ collection: FontCollection, to name: String) {
        guard let database else { return }
        do {
            try database.renameCollection(id: collection.id, name: name)
            refreshCollections()
        } catch {
            report(error)
        }
    }

    func deleteCollection(_ collection: FontCollection) {
        guard let database else { return }
        do {
            try database.deleteCollection(id: collection.id)
            if selection == .collection(collection.id) {
                selection = .all
            }
            refreshCollections()
        } catch {
            report(error)
        }
    }

    func toggleCollection(_ collectionID: String, family: CatalogFamily) {
        guard let database else { return }
        let faceIDs = snapshot.faces(in: family).map(\.id)
        do {
            if isInCollection(family, collectionID) {
                try database.removeFaces(faceIDs, fromCollection: collectionID)
            } else {
                try database.addFaces(faceIDs, toCollection: collectionID)
            }
            refreshCollection(collectionID)
        } catch {
            report(error)
        }
    }

    /// Activates or deactivates every face stored in a collection. Installed
    /// faces are skipped by the engine.
    func setCollectionActive(_ collection: FontCollection, active: Bool) async {
        guard let activationEngine else { return }
        let ids = collectionFaceIDs(collection.id)
        let candidates = snapshot.faces.filter { face in
            guard ids.contains(face.id) else { return false }
            return active ? face.fileStatus == "ok" : true
        }
        let faces = active
            ? candidates
            : candidates.filter { activeFaceIDs.contains($0.id) }
        guard !faces.isEmpty else {
            status = active
                ? "No fonts in \(collection.name)"
                : "No active fonts in \(collection.name)"
            return
        }
        let targets = faces.map {
            ActivationTarget(
                faceID: $0.id,
                path: $0.path,
                postscriptName: $0.postscriptName
            )
        }
        status = "\(active ? "Activating" : "Deactivating") \(collection.name)…"
        let outcome = active
            ? await activationEngine.activate(targets, scope: .user, source: "manual")
            : await activationEngine.deactivate(targets)
        refreshActive()
        status = outcome.summary.isEmpty ? "No change" : outcome.summary
    }

    private func refreshCollection(_ collectionID: String) {
        collectionMembershipCache = nil
        collectionFaceIDsCache.removeValue(forKey: collectionID)
        if let database {
            collections = (try? database.collections()) ?? collections
        }
        rebuildCollectionCounts()
        visibleCache = nil
        rebuildVisible()
    }

    // MARK: - Google Fonts

    var displayFolders: [LibraryFolder] {
        folders.filter { $0.kind != .managed }
    }

    func googleFontsRoot() throws -> URL {
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
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func googleFontCatalog(forceRefresh: Bool = false) async throws -> [GoogleFontFamily] {
        try await GoogleFontsService.shared.catalog(forceRefresh: forceRefresh)
    }

    /// Indexes downloads made outside the app (for example by the CLI) and
    /// keeps the managed folder in the library across launches.
    func syncGoogleFonts() async {
        guard let scanner,
              let root = try? googleFontsRoot(),
              let contents = try? FileManager.default.contentsOfDirectory(atPath: root.path),
              !contents.isEmpty else {
            return
        }
        do {
            _ = try await scanner.scan(
                folder: root,
                kind: .managed
            )
            await reload()
        } catch {
            report(error)
        }
    }

    // MARK: - Google Fonts activation

    /// Faces downloaded under the managed Google folder, keyed by family folder
    /// and by exact local path. Rebuilt when the catalog snapshot reloads.
    private func googleFaceCache() -> (
        byFolder: [String: [CatalogFace]],
        byPath: [String: [CatalogFace]]
    ) {
        if let cache = googleFacesCache, cache.revision == catalogRevision {
            return (cache.byFolder, cache.byPath)
        }
        var byFolder: [String: [CatalogFace]] = [:]
        var byPath: [String: [CatalogFace]] = [:]
        if let root = try? googleFontsRoot() {
            let rootPath = LibraryPath.resolve(root.path)
            for face in snapshot.faces
            where LibraryPath.isInside(face.path, root: rootPath) {
                let relative = face.path.dropFirst(rootPath.count + 1)
                guard let folder = relative.split(separator: "/").first else {
                    continue
                }
                byFolder[String(folder), default: []].append(face)
                byPath[face.path, default: []].append(face)
            }
        }
        googleFacesCache = (catalogRevision, byFolder, byPath)
        return (byFolder, byPath)
    }

    private func googleLocalURL(_ family: GoogleFontFamily, _ file: GoogleFontFile) throws -> URL {
        let root = try googleFontsRoot()
        return root
            .appendingPathComponent(GoogleFontFamily.folderName(for: family), isDirectory: true)
            .appendingPathComponent(file.filename)
    }

    func googleAllFilesDownloaded(_ family: GoogleFontFamily) -> Bool {
        family.files.allSatisfy { file in
            guard let url = try? googleLocalURL(family, file) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    func googleFace(family: GoogleFontFamily, file: GoogleFontFile) -> CatalogFace? {
        guard let url = try? googleLocalURL(family, file) else { return nil }
        return googleFaceCache().byPath[LibraryPath.resolve(url.path)]?.first
    }

    func googleFileActivation(
        family: GoogleFontFamily,
        file: GoogleFontFile
    ) -> FaceActivationState? {
        guard let url = try? googleLocalURL(family, file),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let faces = googleFaceCache().byPath[LibraryPath.resolve(url.path)] ?? []
        guard !faces.isEmpty else { return nil }
        switch activationState(for: faces) {
        case .all:
            return .active
        case .installed:
            return .installed
        case .missing:
            return .missing
        case .blocked(let owner):
            return .blocked(ownerPath: owner)
        case .none, .partial:
            return .available
        }
    }

    func googleFamilyActivation(_ family: GoogleFontFamily) -> FamilyActivation {
        let folder = GoogleFontFamily.folderName(for: family)
        let faces = googleFaceCache().byFolder[folder] ?? []
        return activationState(for: faces)
    }

    func googleFamilyPreviewFace(_ family: GoogleFontFamily) -> CatalogFace? {
        let folder = GoogleFontFamily.folderName(for: family)
        let faces = googleFaceCache().byFolder[folder] ?? []
        return faces.first { !$0.isItalic } ?? faces.first
    }

    func googlePreviewURL(
        family: GoogleFontFamily,
        text: String,
        style: GoogleFontStyle? = nil
    ) async -> URL? {
        // The subset must include the truncation periods; otherwise a clipped
        // grid tile shows three .notdef boxes.
        await GoogleFontPreviewService.shared.previewURL(
            familyName: family.name,
            text: text + " .",
            style: style
        )
    }

    private func activationState(for faces: [CatalogFace]) -> FamilyActivation {
        let present = faces.filter { $0.fileStatus == "ok" }
        guard !present.isEmpty else { return .missing }
        let activatable = present.filter { !ActivationEngine.isInstalledPath($0.path) }
        guard !activatable.isEmpty else { return .installed }

        let active = activatable.reduce(0) {
            $0 + (activeFaceIDs.contains($1.id) ? 1 : 0)
        }
        if active == 0 {
            let available = activatable.filter {
                faceActivationState($0) == .available
            }
            if available.isEmpty,
               let owner = activatable.compactMap({ face -> String? in
                   if case .blocked(let owner) = faceActivationState(face) {
                       return owner
                   }
                   return nil
               }).first {
                return .blocked(ownerPath: owner)
            }
            return .none
        }
        return active == activatable.count ? .all : .partial
    }

    private func toggle(faces: [CatalogFace], label: String) async {
        guard let activationEngine else { return }
        let present = faces.filter { $0.fileStatus == "ok" }
        guard !present.isEmpty else {
            status = "No readable files in \(label)"
            return
        }
        let activatable = present.filter { !ActivationEngine.isInstalledPath($0.path) }
        guard !activatable.isEmpty else {
            status = "\(label) is installed"
            return
        }

        let state = activationState(for: faces)
        let targetsFaces: [CatalogFace]
        switch state {
        case .all:
            targetsFaces = activatable.filter { activeFaceIDs.contains($0.id) }
        case .none, .partial:
            targetsFaces = activatable.filter {
                faceActivationState($0) == .available
            }
        case .installed, .missing, .blocked:
            return
        }
        guard !targetsFaces.isEmpty else {
            status = "No activatable files in \(label)"
            return
        }
        let targets = targetsFaces.map {
            ActivationTarget(
                faceID: $0.id,
                path: $0.path,
                postscriptName: $0.postscriptName
            )
        }
        status = state == .all
            ? "Deactivating \(label)…"
            : "Activating \(label)…"
        let outcome = state == .all
            ? await activationEngine.deactivate(targets)
            : await activationEngine.activate(targets, scope: .user, source: "manual")
        refreshActive()
        status = outcome.summary.isEmpty ? "No change" : outcome.summary
    }

    private func scanGoogleFiles(_ urls: [URL]) async throws {
        guard let scanner else { return }
        let root = try googleFontsRoot()
        let report = try await scanner.scan(
            changes: urls.map(\.path),
            folder: root,
            kind: .managed
        )
        status = "Indexed \(report.faces) Google fonts"
        await reload()
    }

    private func downloadGoogleFiles(
        _ family: GoogleFontFamily,
        files: [GoogleFontFile],
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws {
        let root = try googleFontsRoot()
        let directory = root.appendingPathComponent(
            GoogleFontFamily.folderName(for: family),
            isDirectory: true
        )
        _ = try await GoogleFontsService.shared.download(
            family,
            files: files,
            to: directory,
            progress: progress
        )
    }

    func toggleGoogleFile(
        _ family: GoogleFontFamily,
        file: GoogleFontFile,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws {
        let local = try googleLocalURL(family, file)
        var needsScan = false
        if !FileManager.default.fileExists(atPath: local.path) {
            try await downloadGoogleFiles(family, files: [file], progress: progress)
            needsScan = true
        }
        let localPath = LibraryPath.resolve(local.path)
        if googleFaceCache().byPath[localPath] == nil {
            needsScan = true
        }
        if needsScan {
            try await scanGoogleFiles([local])
        }
        let faces = googleFaceCache().byPath[localPath] ?? []
        guard !faces.isEmpty else { throw GoogleFontsError.notIndexed }
        await toggle(faces: faces, label: file.filename)
    }

    func toggleGoogleFamily(
        _ family: GoogleFontFamily,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws {
        let missing = family.files.filter { file in
            guard let url = try? googleLocalURL(family, file) else { return true }
            return !FileManager.default.fileExists(atPath: url.path)
        }
        if !missing.isEmpty {
            try await downloadGoogleFiles(family, files: missing, progress: progress)
        }
        let folder = GoogleFontFamily.folderName(for: family)
        var needsScan = !missing.isEmpty
        let localPaths = family.files.compactMap { try? googleLocalURL(family, $0) }
        let currentFaces = googleFaceCache().byFolder[folder] ?? []
        if currentFaces.count < localPaths.count {
            needsScan = true
        }
        if needsScan {
            try await scanGoogleFiles(localPaths)
        }
        let faces = googleFaceCache().byFolder[folder] ?? []
        guard !faces.isEmpty else { throw GoogleFontsError.notIndexed }
        await toggle(faces: faces, label: family.name)
    }

    // MARK: - Settings export

    private enum SettingsError: LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                "This settings file is version \(version); this build understands up to \(LibraryConfiguration.currentVersion)."
            }
        }
    }

    func configuration() -> LibraryConfiguration {
        let folderConfigs = displayFolders.map {
            LibraryConfiguration.Folder(
                path: $0.path,
                kind: $0.kind.rawValue,
                label: $0.displayName
            )
        }
        let collectionConfigs = collections.map { collection in
            let faceIDs = collectionFaceIDs(collection.id)
            let fonts = snapshot.faces
                .filter { faceIDs.contains($0.id) }
                .map(\.postscriptName)
                .sorted()
            return LibraryConfiguration.Collection(
                name: collection.name,
                sort: collection.sort,
                fonts: fonts
            )
        }
        let sampleConfigs = samples.map {
            LibraryConfiguration.Sample(
                name: $0.name,
                text: $0.text,
                size: $0.size,
                textColor: $0.textColor,
                backgroundColor: $0.backgroundColor,
                alignment: $0.alignment
            )
        }
        let preview = LibraryConfiguration.Preview(
            text: sampleText,
            size: sampleSize,
            textColor: textColor.hexRGBA,
            backgroundColor: backgroundColor.hexRGBA,
            showSystemFonts: showSystemFonts,
            fallbackFileNames: fallbackFileNames
        )
        return LibraryConfiguration(
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            folders: folderConfigs,
            collections: collectionConfigs,
            samples: sampleConfigs,
            preview: preview,
            ignoredPaths: ignoredPaths
        )
    }

    func exportSettings(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(configuration())
        try data.write(to: url, options: .atomic)
        status = "Exported settings"
    }

    func importSettings(from url: URL) async throws {
        guard let database else { return }
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(LibraryConfiguration.self, from: data)
        guard config.version <= LibraryConfiguration.currentVersion else {
            throw SettingsError.unsupportedVersion(config.version)
        }

        sampleText = config.preview.text
        sampleSize = config.preview.size
        textColor = Color(hex: config.preview.textColor) ?? .primary
        backgroundColor = Color(hex: config.preview.backgroundColor)
            ?? Color(nsColor: .textBackgroundColor)
        showSystemFonts = config.preview.showSystemFonts
        fallbackFileNames = config.preview.fallbackFileNames

        for folder in config.folders {
            let kind = FolderKind(rawValue: folder.kind) ?? .staticFolder
            await addFolder(URL(fileURLWithPath: folder.path), kind: kind)
            if let label = folder.label, !label.isEmpty {
                let canonical = LibraryPath.resolve(folder.path)
                if let stored = folders.first(where: { $0.path == canonical }) {
                    try? database.setDisplayName(folderID: stored.id, name: label)
                }
            }
        }
        folders = (try? database.folders()) ?? folders
        await reload()

        var orderedFolderIDs: [String] = []
        for item in config.folders {
            let path = LibraryPath.resolve(item.path)
            if let folder = folders.first(where: { $0.path == path }) {
                orderedFolderIDs.append(folder.id)
            }
        }
        for folder in folders where !orderedFolderIDs.contains(folder.id) {
            orderedFolderIDs.append(folder.id)
        }
        try database.setFolderOrder(orderedFolderIDs)
        folders = (try? database.folders()) ?? folders

        for path in config.ignoredPaths ?? [] {
            let canonical = LibraryPath.resolve(path)
            try database.ignorePath(canonical)
            try database.deleteFiles(under: canonical)
        }
        ignoredPaths = (try? database.ignoredPaths()) ?? ignoredPaths
        await reload()

        for item in config.collections {
            let collectionID: String
            if let existing = collections.first(where: { $0.name == item.name }) {
                collectionID = existing.id
            } else {
                collectionID = try database.createCollection(name: item.name)
            }
            let names = Set(item.fonts.map { $0.lowercased() })
            let faceIDs = snapshot.faces
                .filter { names.contains($0.postscriptName.lowercased()) }
                .map(\.id)
            try database.addFaces(faceIDs, toCollection: collectionID)
        }
        refreshCollections()

        for sample in config.samples
        where !samples.contains(where: { $0.name == sample.name }) {
            try database.upsertSample(SavedSample(
                id: UUID().uuidString,
                name: sample.name,
                text: sample.text,
                size: sample.size,
                textColor: sample.textColor,
                backgroundColor: sample.backgroundColor,
                alignment: sample.alignment,
                sort: samples.count,
                createdAt: Date().timeIntervalSince1970
            ))
        }
        samples = (try? database.samples()) ?? samples
        status = "Imported settings"
    }

    // MARK: - Saved samples

    func applySample(_ sample: SavedSample) {
        sampleText = sample.text
        sampleSize = sample.size
        textColor = Color(hex: sample.textColor) ?? .primary
        backgroundColor = Color(hex: sample.backgroundColor)
            ?? Color(nsColor: .textBackgroundColor)
        selectedSampleID = sample.id
    }

    func saveCurrentSample(named name: String, asNew: Bool = false) {
        guard let database else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = asNew ? nil : selectedSampleID.flatMap { id in
            samples.first { $0.id == id }
        }
        let id = existing?.id ?? UUID().uuidString
        let record = SavedSample(
            id: id,
            name: trimmed.isEmpty
                ? (existing?.name ?? "Sample \(samples.count + 1)")
                : trimmed,
            text: sampleText,
            size: sampleSize,
            textColor: textColor.hexRGBA,
            backgroundColor: backgroundColor.hexRGBA,
            alignment: existing?.alignment ?? "left",
            sort: existing?.sort ?? samples.count,
            createdAt: existing?.createdAt ?? Date().timeIntervalSince1970
        )
        do {
            try database.upsertSample(record)
            samples = try database.samples()
            selectedSampleID = id
        } catch {
            report(error)
        }
    }

    func deleteSelectedSample() {
        guard let database, let id = selectedSampleID else { return }
        do {
            try database.deleteSample(id: id)
            samples = try database.samples()
            selectedSampleID = nil
        } catch {
            report(error)
        }
    }

    /// Coverage ranges are loaded on first use; they are not part of the
    /// snapshot, and the cache is dropped whenever coverage or the library
    /// changes.
    private func characterCoverage() -> [String: CoverageRanges] {
        if let coverageRangesByFace { return coverageRangesByFace }
        guard let database else { return [:] }
        let loaded = (try? database.coverageRanges()) ?? [:]
        coverageRangesByFace = loaded
        return loaded
    }

    func sampleText(for family: CatalogFamily) -> String {
        family.previewText(userText: sampleText)
    }

    func sampleText(for face: CatalogFace) -> String {
        FontScript.previewText(mask: face.previewMask, userText: sampleText)
    }

    /// Long presets need a third line. Row height stays uniform across the list;
    /// only a sample change alters it.
    /// Lines a preset is allowed to use. Independent of the row height: a
    /// large short sample must not silently become a four-line row.
    var previewLineBudget: Int {
        sampleText.count > 48 ? 4 : 2
    }

    var previewMaxLines: Int { previewLineBudget }

    /// Uniform row height for the current sample and available preview width.
    ///
    /// The line count is estimated from the width and the sample size, so a
    /// single-line preview does not carry a second line's padding when the
    /// slider grows. Multi-line previews keep their breathing room. Quantized to
    /// 8 pt so dragging the slider does not relayout on every tick.
    func previewRowHeight(previewWidth: CGFloat) -> CGFloat {
        let base: CGFloat
        if sampleText.count > 48 {
            base = 224
        } else if sampleText.count > 28 {
            base = 176
        } else {
            base = 128
        }

        let size = max(1, CGFloat(sampleSize))
        // Average advance is about 0.65 em for the mixed-case samples. Wider
        // display faces wrap earlier; that is a safe overestimate for padding.
        let charactersPerLine = max(1, Int(previewWidth / (size * 0.65)))
        let estimatedLines = min(
            previewLineBudget,
            max(1, Int(ceil(Double(sampleText.count) / Double(charactersPerLine))))
        )
        let lineHeight = size * 1.3
        let padding: CGFloat = estimatedLines > 1 ? 12 : 8
        let needed = CGFloat(estimatedLines) * lineHeight + padding
        let step: CGFloat = 8
        let quantized = (needed / step).rounded(.up) * step
        return max(base, quantized)
    }

    // MARK: - Activation

    func refreshActive() {
        guard let database else { return }
        let updated = (try? database.activeFaceIDs()) ?? []
        let records = (try? database.activationRecords()) ?? []
        var owners: [String: String] = [:]
        owners.reserveCapacity(records.count)
        for record in records {
            owners[record.postscriptName.lowercased()] = record.path
        }
        guard updated != activeFaceIDs || owners != activePostScriptOwners else { return }
        activeFaceIDs = updated
        activePostScriptOwners = owners
        visibleCache = nil
        if selection == .active {
            rebuildVisible()
        }
    }

    func reconcileActivation() async {
        guard let activationEngine else { return }
        _ = await activationEngine.reconcile()
        refreshActive()
    }

    func familyActivation(_ family: CatalogFamily) -> FamilyActivation {
        let faces = snapshot.faces(in: family)
        let present = faces.filter { $0.fileStatus == "ok" }
        guard !present.isEmpty else { return .missing }
        let activatable = present.filter { !ActivationEngine.isInstalledPath($0.path) }
        guard !activatable.isEmpty else { return .installed }

        if family.hasDuplicatePostScriptNames {
            guard let preferred = representativeFace(for: family) else {
                return .missing
            }
            switch faceActivationState(preferred) {
            case .active:
                return .all
            case .installed:
                return .installed
            case .missing:
                return .missing
            case .blocked(let owner):
                return .blocked(ownerPath: owner)
            case .available:
                return .none
            }
        }

        let active = activatable.reduce(0) { count, face in
            count + (activeFaceIDs.contains(face.id) ? 1 : 0)
        }
        if active == 0 {
            let available = activatable.filter {
                faceActivationState($0) == .available
            }
            if available.isEmpty,
               let owner = activatable.compactMap({ face -> String? in
                   if case .blocked(let owner) = faceActivationState(face) {
                       return owner
                   }
                   return nil
               }).first {
                return .blocked(ownerPath: owner)
            }
            return .none
        }
        return active == activatable.count ? .all : .partial
    }

    func faceActivationState(_ face: CatalogFace) -> FaceActivationState {
        guard face.fileStatus == "ok" else { return .missing }
        if ActivationEngine.isInstalledPath(face.path) {
            return .installed
        }
        if activeFaceIDs.contains(face.id) {
            return .active
        }
        if let owner = activePostScriptOwners[face.postscriptName.lowercased()],
           owner != face.path {
            return .blocked(ownerPath: owner)
        }
        return .available
    }

    func toggle(face: CatalogFace) async {
        guard let activationEngine else { return }
        let state = faceActivationState(face)
        switch state {
        case .installed:
            return
        case .missing:
            status = "\((face.path as NSString).lastPathComponent) is missing"
            return
        case .blocked(let owner):
            status = "PostScript name is in use by \(owner)"
            return
        case .available, .active:
            break
        }

        let target = ActivationTarget(
            faceID: face.id,
            path: face.path,
            postscriptName: face.postscriptName
        )
        let activating = state == .available
        status = activating
            ? "Activating \(face.style)…"
            : "Deactivating \(face.style)…"
        let outcome = activating
            ? await activationEngine.activate([target], scope: .user, source: "manual")
            : await activationEngine.deactivate([target])
        refreshActive()
        status = outcome.summary.isEmpty ? "No change" : outcome.summary
    }

    func revealInFinder(_ face: CatalogFace) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: face.path)])
    }

    func toggle(_ family: CatalogFamily) async {
        guard let activationEngine else { return }
        let faces = Array(snapshot.faces(in: family))
        let present = faces.filter { $0.fileStatus == "ok" }
        guard !present.isEmpty else {
            status = "No readable files in \(family.name)"
            return
        }
        let activatable = present.filter { !ActivationEngine.isInstalledPath($0.path) }

        // Duplicate PostScript groups have no single family-level meaning.
        // Toggle the one file in context.
        if family.hasDuplicatePostScriptNames {
            guard let preferred = representativeFace(for: family) else {
                status = "No readable file in \(family.name)"
                return
            }
            await toggle(face: preferred)
            return
        }

        guard !activatable.isEmpty else {
            status = "\(family.name) is installed"
            return
        }
        let state = familyActivation(family)
        let targetsFaces: [CatalogFace]
        switch state {
        case .all:
            targetsFaces = activatable.filter { activeFaceIDs.contains($0.id) }
        case .none, .partial:
            targetsFaces = activatable.filter {
                faceActivationState($0) == .available
            }
        case .installed, .missing, .blocked:
            return
        }
        guard !targetsFaces.isEmpty else {
            status = "No activatable files in \(family.name)"
            return
        }
        let targets = targetsFaces.map {
            ActivationTarget(
                faceID: $0.id,
                path: $0.path,
                postscriptName: $0.postscriptName
            )
        }
        status = state == .all
            ? "Deactivating \(family.name)…"
            : "Activating \(family.name)…"
        let outcome = state == .all
            ? await activationEngine.deactivate(targets)
            : await activationEngine.activate(targets, scope: .user, source: "manual")
        refreshActive()
        status = outcome.summary.isEmpty ? "No change" : outcome.summary
    }

    /// Adds or rescans a folder. Overlap warnings live in
    /// `requestAddFolders`; this is the low-level path used by scans, seeding,
    /// settings import and confirmed adds.
    func addFolder(_ url: URL, kind: FolderKind = .staticFolder) async {
        guard let database, let scanner else { return }
        let resolved = URL(fileURLWithPath: LibraryPath.resolve(url.path))
        status = "Scanning \(resolved.lastPathComponent)…"
        do {
            let report = try await scanner.scan(folder: resolved, kind: kind)
            status = report.summary
            await reload()
            folders = try database.folders()
            setupWatching()
            await reconcileActivation()
        } catch {
            report(error)
        }
    }

    // MARK: - User folder adds

    func requestAddFolder(_ url: URL, kind: FolderKind) {
        requestAddFolders([FolderAddEntry(url: url, kind: kind)])
    }

    func requestAddFolders(_ entries: [FolderAddEntry]) {
        var seen = Set<String>()
        let resolved = entries.compactMap { entry -> FolderAddEntry? in
            let path = LibraryPath.resolve(entry.url.path)
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return FolderAddEntry(
                url: URL(fileURLWithPath: path),
                kind: entry.kind
            )
        }
        guard !resolved.isEmpty else { return }
        var seenWarnings = Set<String>()
        let warnings = resolved
            .flatMap { folderAddWarnings(for: $0.url.path) }
            .filter { seenWarnings.insert($0).inserted }
        if warnings.isEmpty {
            Task { await addFolders(resolved) }
        } else {
            pendingFolderAdd = PendingFolderAdd(entries: resolved, warnings: warnings)
        }
    }

    func confirmPendingFolderAdd() async {
        guard let pending = pendingFolderAdd else { return }
        pendingFolderAdd = nil
        await addFolders(pending.entries)
    }

    func cancelPendingFolderAdd() {
        pendingFolderAdd = nil
    }

    private func addFolders(_ entries: [FolderAddEntry]) async {
        for entry in entries {
            await addFolder(entry.url, kind: entry.kind)
        }
    }

    /// Warnings shown before an add proceeds. Paths are already canonical.
    func folderAddWarnings(for path: String) -> [String] {
        let candidate = LibraryPath.resolve(path)
        var warnings: [String] = []
        var seen = Set<String>()

        func append(_ warning: String) {
            if seen.insert(warning).inserted {
                warnings.append(warning)
            }
        }

        for ignored in ignoredPaths {
            switch LibraryPath.relation(candidate, ignored) {
            case .same:
                append("This folder is already ignored.")
            case .descendant:
                append("This folder is inside ignored folder \(ignored). "
                    + "Its fonts will not be indexed.")
            case .ancestor:
                append("This folder contains ignored folder \(ignored). "
                    + "That subtree stays excluded.")
            case .unrelated:
                break
            }
        }

        for folder in folders {
            switch LibraryPath.relation(candidate, folder.path) {
            case .same:
                append("This folder is already in the library.")
            case .descendant:
                append("This folder is already inside library folder \(folder.displayPath).")
            case .ancestor:
                append("This folder contains library folder \(folder.displayPath).")
            case .unrelated:
                break
            }
        }
        return warnings
    }

    func isPathIgnored(_ path: String) -> Bool {
        isIgnored(LibraryPath.resolve(path))
    }

    /// Adds individual font files. Files already inside an indexed folder join
    /// that folder; other files join a one-time folder for their directory, so
    /// the sidebar still has a path to show and reveal.
    func addFontFiles(_ urls: [URL]) async {
        guard let database, let scanner, !urls.isEmpty else { return }
        let extensions: Set<String> = ["ttf", "otf", "ttc", "otc", "dfont"]
        let files = urls.filter {
            extensions.contains($0.pathExtension.lowercased())
        }
        guard !files.isEmpty else {
            errorMessage = "No font files were selected."
            return
        }
        if let blocked = files.first(where: {
            isPathIgnored($0.deletingLastPathComponent().path)
        }) {
            errorMessage = "\(blocked.deletingLastPathComponent().lastPathComponent) is ignored. "
                + "Stop ignoring it in the settings first."
            return
        }

        var grouped: [String: [URL]] = [:]
        for file in files {
            let directory = LibraryPath.resolve(
                file.deletingLastPathComponent().path
            )
            grouped[directory, default: []].append(file)
        }

        status = "Adding \(files.count) \(files.count == 1 ? "font" : "fonts")…"
        do {
            var addedFaces = 0
            for (directory, directoryFiles) in grouped {
                let covering = folders
                    .filter { LibraryPath.isInside(directory, root: $0.path) }
                    .max { $0.path.count < $1.path.count }
                let folderURL = URL(fileURLWithPath: covering?.path ?? directory)
                let report = try await scanner.scan(
                    changes: directoryFiles.map(\.path),
                    folder: folderURL,
                    kind: covering?.kind ?? .staticFolder
                )
                addedFaces += report.faces
            }
            status = "Added \(addedFaces) \(addedFaces == 1 ? "font" : "fonts") from \(files.count) \(files.count == 1 ? "file" : "files")"
            await reload()
            folders = try database.folders()
            setupWatching()
        } catch {
            report(error)
        }
    }

    /// A mixed drop: folders become indexed folders, font files are added
    /// individually. Anything else is ignored.
    func importURLs(_ urls: [URL]) async {
        var directories: [URL] = []
        var files: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                directories.append(url)
            } else {
                files.append(url)
            }
        }
        if !directories.isEmpty {
            requestAddFolders(
                directories.map {
                    FolderAddEntry(url: $0, kind: .staticFolder)
                }
            )
        }
        if !files.isEmpty {
            await addFontFiles(files)
        }
    }

    func renameFolder(_ folder: LibraryFolder, to name: String) async {
        guard let database else { return }
        do {
            try database.setDisplayName(folderID: folder.id, name: name)
            folders = try database.folders()
            status = "Renamed to \(name)"
        } catch {
            report(error)
        }
    }

    func revealFolder(_ folder: LibraryFolder) {
        revealPath(folder.path)
    }

    /// Moves a sidebar root before another root. Managed folders stay hidden at
    /// the end of the stored order.
    func moveFolder(id sourceID: String, by offset: Int) {
        guard offset != 0 else { return }
        var ordered = displayFolders
        guard let from = ordered.firstIndex(where: { $0.id == sourceID }) else { return }
        let destination = from + offset
        guard ordered.indices.contains(destination) else { return }
        let item = ordered.remove(at: from)
        ordered.insert(item, at: destination)
        persistFolderOrder(ordered, moved: item)
    }

    private func persistFolderOrder(_ ordered: [LibraryFolder], moved: LibraryFolder) {
        guard let database else { return }
        var ids = ordered.map(\.id)
        ids.append(contentsOf: folders.filter { $0.kind == .managed }.map(\.id))
        do {
            try database.setFolderOrder(ids)
            folders = try database.folders()
            status = "Moved \(moved.name)"
        } catch {
            report(error)
        }
    }

    func revealPath(_ path: String) {
        let url = URL(fileURLWithPath: path)
        // A missing file cannot be selected in Finder; show its folder instead.
        let target = FileManager.default.fileExists(atPath: path)
            ? url
            : url.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    func activeFaceCount(in folder: LibraryFolder) -> Int {
        snapshot.faces.reduce(0) { count, face in
            count + (activeFaceIDs.contains(face.id)
                && LibraryPath.isInside(face.path, root: folder.path) ? 1 : 0)
        }
    }

    func setWatched(_ folder: LibraryFolder, _ watched: Bool) async {
        guard let database else { return }
        if watched {
            // Turning watching on is a full sync, confirmed by the caller.
            await addFolder(URL(fileURLWithPath: folder.path), kind: .watched)
            status = "Watching \(folder.displayPath)"
            return
        }
        do {
            try database.setKind(folderID: folder.id, kind: .staticFolder)
            folders = try database.folders()
            setupWatching()
            status = "Stopped watching \(folder.displayPath)"
        } catch {
            report(error)
        }
    }

    func removeFolder(_ folder: LibraryFolder) async {
        guard let database else { return }
        // Deactivate first: removing rows would otherwise leave fonts active
        // with no journal entry to turn them off later.
        let activeTargets = snapshot.faces
            .filter {
                LibraryPath.isInside($0.path, root: folder.path)
                    && activeFaceIDs.contains($0.id)
            }
            .map {
                ActivationTarget(
                    faceID: $0.id,
                    path: $0.path,
                    postscriptName: $0.postscriptName
                )
            }
        if !activeTargets.isEmpty, let activationEngine {
            let outcome = await activationEngine.deactivate(activeTargets)
            refreshActive()
            if !outcome.failures.isEmpty {
                errorMessage = outcome.summary
                return
            }
        }

        do {
            let pathPrefix = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
            try await Task.detached {
                // Nested roots: hand this root's files back to the deepest
                // remaining ancestor before deleting the folder row.
                let remaining = try database.folders().filter { $0.id != folder.id }
                let parent = remaining
                    .filter {
                        $0.path != folder.path
                            && LibraryPath.isInside(folder.path, root: $0.path)
                    }
                    .max { $0.path.count < $1.path.count }
                if let parent {
                    try database.adoptFiles(
                        fromFolderID: folder.id,
                        toFolderID: parent.id,
                        pathPrefix: pathPrefix
                    )
                }
                try database.removeFolder(id: folder.id)
            }.value
            if selection == .folder(folder.id) {
                selection = .all
            }
            if case .subfolder(let path) = selection,
               LibraryPath.isInside(path, root: folder.path) {
                selection = .all
            }
            await reload()
            folders = try database.folders()
            setupWatching()
            status = "Removed \(folder.displayPath)"
        } catch {
            report(error)
        }
    }

    /// Excludes a folder subtree from indexing. Font files stay on disk; their
    /// rows and any active registrations go away. The sidebar keeps an ignored
    /// row so the exclusion stays reversible.
    func ignoreFolder(path: String) async {
        guard let database else { return }
        let canonical = LibraryPath.resolve(path)
        let activeTargets = snapshot.faces
            .filter {
                LibraryPath.isInside($0.path, root: canonical)
                    && activeFaceIDs.contains($0.id)
            }
            .map {
                ActivationTarget(
                    faceID: $0.id,
                    path: $0.path,
                    postscriptName: $0.postscriptName
                )
            }
        if !activeTargets.isEmpty, let activationEngine {
            let outcome = await activationEngine.deactivate(activeTargets)
            refreshActive()
            if !outcome.failures.isEmpty {
                errorMessage = outcome.summary
                return
            }
        }

        do {
            try await Task.detached {
                try database.ignorePath(canonical)
                try database.deleteFiles(under: canonical)
            }.value
            if case .subfolder(let selected) = selection,
               LibraryPath.isInside(selected, root: canonical) {
                selection = .all
            }
            await reload()
            setupWatching()
            status = "Ignoring \((canonical as NSString).lastPathComponent)"
        } catch {
            report(error)
        }
    }

    func unignoreFolder(path: String) async {
        guard let database else { return }
        let canonical = LibraryPath.resolve(path)
        do {
            try await Task.detached {
                try database.unignorePath(canonical)
            }.value
            ignoredPaths = (try? database.ignoredPaths()) ?? ignoredPaths
            let affected = folders
                .filter {
                    LibraryPath.isInside($0.path, root: canonical)
                        || LibraryPath.isInside(canonical, root: $0.path)
                }
                .map(\.path)
            if affected.isEmpty {
                await reload()
            } else {
                await scan(rootPaths: affected)
            }
            setupWatching()
            status = "Indexing \((canonical as NSString).lastPathComponent) again"
        } catch {
            report(error)
        }
    }

    /// Removes every file row whose status is not `ok`. Missing rows persist by
    /// default so collections survive an offline volume; this is the explicit
    /// cleanup from the Warnings page.
    func removeMissingFiles() async {
        guard let database else { return }
        // A missing file can still own a journal row until reconcile runs.
        // Clear those first so the rows are never dropped while fontd still
        // holds a registration.
        let stale = snapshot.faces
            .filter { $0.fileStatus != "ok" && activeFaceIDs.contains($0.id) }
            .map {
                ActivationTarget(
                    faceID: $0.id,
                    path: $0.path,
                    postscriptName: $0.postscriptName
                )
            }
        if !stale.isEmpty, let activationEngine {
            let outcome = await activationEngine.deactivate(stale)
            refreshActive()
            if !outcome.failures.isEmpty {
                errorMessage = outcome.summary
                return
            }
        }
        do {
            let removed = try await Task.detached {
                try database.deleteMissingFiles()
            }.value
            refreshActive()
            await reload()
            status = removed == 0
                ? "No missing entries to remove"
                : "Removed \(removed) missing \(removed == 1 ? "entry" : "entries")"
        } catch {
            report(error)
        }
    }

    private func isIgnored(_ path: String) -> Bool {
        ignoredPaths.contains { LibraryPath.isInside(path, root: $0) }
    }

    // MARK: - Watching

    private func setupWatching() {
        guard !CommandLine.arguments.contains("--headless") else { return }
        watcher?.stop()
        watcher = nil
        debounceTask?.cancel()
        sweepTask?.cancel()

        let roots = folders
            .filter { $0.kind == .watched && !isIgnored($0.path) }
            .map(\.path)
        guard !roots.isEmpty else { return }

        let watcher = FolderWatcher()
        watcher.start(roots: roots) { [weak self] changes in
            Task { @MainActor in
                self?.receivedChanges(changes)
            }
        }
        self.watcher = watcher
        scheduleSweep()
    }

    private func receivedChanges(_ changes: [(root: String, path: String)]) {
        for change in changes {
            pendingChanges[change.root, default: []].insert(change.path)
        }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            let pending = self.pendingChanges
            self.pendingChanges.removeAll()
            await self.applyChanges(pending)
        }
    }

    private func applyChanges(_ changes: [String: Set<String>]) async {
        guard let scanner else { return }
        var reloadNeeded = false
        let manager = FileManager.default

        for (root, changedPaths) in changes {
            guard let folder = folders.first(where: { $0.path == root }) else { continue }
            guard !isIgnored(root) else { continue }
            let paths = changedPaths.filter { !isIgnored($0) }
            guard !paths.isEmpty else { continue }

            // A directory event means the subtree changed; scan the folder.
            var needsFullScan = false
            for path in paths {
                var isDirectory: ObjCBool = false
                let exists = manager.fileExists(atPath: path, isDirectory: &isDirectory)
                if exists, isDirectory.boolValue {
                    needsFullScan = true
                    break
                }
                if !exists, (path as NSString).pathExtension.isEmpty {
                    needsFullScan = true
                    break
                }
            }

            do {
                let report: ScanReport
                if needsFullScan {
                    report = try await scanner.scan(
                        folder: URL(fileURLWithPath: root),
                        kind: folder.kind
                    )
                } else {
                    report = try await scanner.scan(
                        changes: Array(paths),
                        folder: URL(fileURLWithPath: root),
                        kind: folder.kind
                    )
                }
                status = report.summary
                reloadNeeded = true
            } catch {
                report(error)
            }
        }
        if reloadNeeded {
            await reload()
            await reconcileActivation()
        }
    }

    private func scan(rootPaths: [String]) async {
        guard let scanner else { return }
        var changed = false
        for path in rootPaths {
            guard let folder = folders.first(where: { $0.path == path }) else { continue }
            guard !isIgnored(path) else { continue }
            do {
                let report = try await scanner.scan(
                    folder: URL(fileURLWithPath: path),
                    kind: folder.kind
                )
                status = report.summary
                changed = true
            } catch {
                report(error)
            }
        }
        if changed {
            await reload()
            await reconcileActivation()
        }
    }

    private func scheduleSweep() {
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled, let self else { return }
                let roots = self.folders
                    .filter { $0.kind == .watched && !self.isIgnored($0.path) }
                    .map(\.path)
                await self.scan(rootPaths: roots)
            }
        }
    }

    func rescanAll() async {
        guard let database, let scanner else { return }
        for folder in folders {
            guard !isIgnored(folder.path) else { continue }
            status = "Scanning \(folder.name)…"
            do {
                let report = try await scanner.scan(
                    folder: URL(fileURLWithPath: folder.path),
                    kind: folder.kind
                )
                status = report.summary
            } catch {
                report(error)
            }
        }
        await reload()
        folders = (try? database.folders()) ?? folders
        await reconcileActivation()
    }

    // MARK: - Visible rows

    private func rebuildVisible() {
        let key = VisibleKey(
            query: query,
            filter: filter,
            selection: selection,
            revision: catalogRevision,
            showSystemFonts: showSystemFonts
        )
        if let visibleCache, visibleCache.key == key {
            if visibleFamilies.count != visibleCache.rows.count {
                visibleFamilies = visibleCache.rows
            }
            if selectionFontCount != visibleCache.selectionFonts {
                selectionFontCount = visibleCache.selectionFonts
            }
            if visibleFontCount != visibleCache.visibleFonts {
                visibleFontCount = visibleCache.visibleFonts
            }
            return
        }

        var families = snapshot.families
        let scope: VisibleScope
        switch selection {
        case .active:
            families = snapshot.families(containingAny: activeFaceIDs)
            scope = .active
        case .all:
            scope = .all
        case .folder(let folderID):
            if let folder = folders.first(where: { $0.id == folderID }) {
                let ids = familyIDs(forFolderPath: folder.path)
                families = families.filter { ids.contains($0.id) }
                scope = .path(folder.path)
            } else {
                scope = .all
            }
        case .subfolder(let path):
            let ids = familyIDs(forFolderPath: path)
            families = families.filter { ids.contains($0.id) }
            scope = .path(path)
        case .collection(let collectionID):
            let ids = collectionFaceIDs(collectionID)
            families = snapshot.families(containingAny: ids)
            scope = .faces(ids)
        case .problems:
            families = []
            scope = .faces([])
        case .googleFonts:
            families = []
            scope = .faces([])
        }
        // The denominator is the current sidebar item, including system fonts
        // that a global toggle may hide. It is never the whole library unless
        // All Fonts is selected.
        let selectionFonts = scopeFaceCount(scope, familyIDs: nil)
        if !showSystemFonts {
            families = families.filter { !snapshot.isSystemFamily($0) }
        }
        let needle = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !needle.isEmpty {
            let bytes = Data(needle.utf8)
            families = families.filter { $0.searchBlob.range(of: bytes) != nil }
        }
        if filter.isActive {
            let scalars = filter.characterScalars
            let coverage = scalars.isEmpty ? [:] : characterCoverage()
            families = families.filter { family in
                snapshot.matches(family, filter: filter)
                    && (scalars.isEmpty
                        || snapshot.family(family, covers: scalars, coverage: coverage))
            }
        }
        // Store one array instance per input change. Filtering in the view body
        // on every scroll tick made SwiftUI diff thousands of rows.
        let visibleFonts = scopeFaceCount(
            scope,
            familyIDs: Set(families.map(\.id))
        )
        visibleCache = VisibleResult(
            key: key,
            rows: families,
            selectionFonts: selectionFonts,
            visibleFonts: visibleFonts
        )
        visibleFamilies = families
        selectionFontCount = selectionFonts
        visibleFontCount = visibleFonts
    }

    /// Leaf names are enough until two folders share one. Three "Fonts"
    /// folders exist, so those show a path that starts distinctively.
    var folderTitles: [String: String] {
        var leafCounts: [String: Int] = [:]
        for folder in displayFolders {
            leafCounts[folder.name, default: 0] += 1
        }
        var titles: [String: String] = [:]
        for folder in displayFolders {
            titles[folder.id] = (leafCounts[folder.name] ?? 0) > 1
                ? folder.displayPath
                : folder.name
        }
        return titles
    }

    var visibleStatus: String {
        if selection == .problems {
            return "\(problemCount.formatted()) "
                + (problemCount == 1 ? "warning" : "warnings")
        }
        if selection == .googleFonts {
            return "Google Fonts"
        }
        let visible = visibleFontCount.formatted()
        let total = selectionFontCount.formatted()
        if visibleFontCount == selectionFontCount {
            return "\(visible) \(visibleFontCount == 1 ? "font" : "fonts")"
        }
        return "\(visible) of \(total) \(selectionFontCount == 1 ? "font" : "fonts")"
    }

    func representativeFace(for family: CatalogFamily) -> CatalogFace? {
        let readable = snapshot.faces(in: family).filter { $0.fileStatus == "ok" }
        guard !readable.isEmpty else { return nil }
        let scoped: [CatalogFace]
        if let path = selectedFolderPath {
            scoped = readable.filter { LibraryPath.isInside($0.path, root: path) }
        } else {
            scoped = []
        }
        let pool = scoped.isEmpty ? readable : scoped
        if let active = pool.first(where: { activeFaceIDs.contains($0.id) }) {
            return active
        }
        return pool.first { !$0.isItalic && $0.weightClass == 400 }
            ?? pool.first { !$0.isItalic }
            ?? pool.first
    }

    private var selectedFolderPath: String? {
        switch selection {
        case .folder(let folderID):
            return folders.first(where: { $0.id == folderID })?.path
        case .subfolder(let subfolderPath):
            return subfolderPath
        default:
            return nil
        }
    }

    private func familyIDs(forFolderPath path: String) -> Set<String> {
        if let cached = folderFamilyIDs[path] { return cached }
        var ids = Set<String>()
        for face in snapshot.faces
        where LibraryPath.isInside(face.path, root: path) {
            ids.insert(face.familyKey)
        }
        folderFamilyIDs[path] = ids
        return ids
    }
}
