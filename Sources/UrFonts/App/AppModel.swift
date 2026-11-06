import AppKit
import Foundation
import Observation
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
}

enum FamilyActivation: Equatable {
    case none
    case partial
    case all
    case installed
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
    var activeFaceIDs: Set<String> = []
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
    @ObservationIgnored private var activationEngine: ActivationEngine?
    @ObservationIgnored private var coverageIndexer: CoverageIndexer?
    @ObservationIgnored private var coverageRangesByFace: [String: CoverageRanges]?
    @ObservationIgnored private var catalogRevision = 0
    @ObservationIgnored private var suppressSystemFontPersistence = false
    @ObservationIgnored private var visibleCache: VisibleResult?
    @ObservationIgnored private var collectionFaceIDsCache: [String: Set<String>] = [:]
    @ObservationIgnored private var collectionMembershipCache: [String: Set<String>]?

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
            let prefix = path.hasSuffix("/") ? path : path + "/"
            return snapshot.faces.reduce(0) { count, face in
                guard face.path.hasPrefix(prefix) else { return count }
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
                    folders.append(URL(fileURLWithPath: value))
                }
            case "--db":
                databasePath = arguments.next()
            default:
                break
            }
        }
        initialFolders = folders
        databaseURL = databasePath.map { URL(fileURLWithPath: $0) }
            ?? (try? LibraryLocation.defaultDatabaseURL())
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
            activationEngine = ActivationEngine(database: database)
            coverageIndexer = CoverageIndexer(database: database)
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
            } else if !folders.isEmpty, !CommandLine.arguments.contains("--no-rescan") {
                Task { await rescanAll() }
            }
        } catch {
            errorMessage = error.localizedDescription
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
            folderFamilyIDs.removeAll(keepingCapacity: true)
            coverageRangesByFace = nil
            collectionMembershipCache = nil
            catalogRevision &+= 1
            visibleCache = nil
            rebuildVisible()
            rebuildFolderCounts()
            rebuildFolderTrees()
            rebuildCollectionCounts()
            refreshCoverage()
            refreshProblemCounts()
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
        let prefixes = folders.map { folder in
            (folder.id, folder.path.hasSuffix("/") ? folder.path : folder.path + "/")
        }
        for face in snapshot.faces {
            for (id, prefix) in prefixes where face.path.hasPrefix(prefix) {
                fontsByFolder[id, default: 0] += 1
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
                isWatched: watched
            )
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
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func renameCollection(_ collection: FontCollection, to name: String) {
        guard let database else { return }
        do {
            try database.renameCollection(id: collection.id, name: name)
            refreshCollections()
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
            collectionMembershipCache = nil
            collectionFaceIDsCache.removeValue(forKey: collectionID)
            collections = (try? database.collections()) ?? collections
            rebuildCollectionCounts()
            visibleCache = nil
            rebuildVisible()
        } catch {
            errorMessage = error.localizedDescription
        }
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

    func downloadedGoogleFamilies() -> Set<String> {
        guard let root = try? googleFontsRoot(),
              let directories = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey]
              ) else {
            return []
        }
        return Set(directories.compactMap { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                ? url.lastPathComponent
                : nil
        })
    }

    /// Indexes downloads made outside the app (for example by the CLI) and
    /// keeps the managed folder in the library across launches.
    func syncGoogleFonts() async {
        guard let database,
              let root = try? googleFontsRoot(),
              let contents = try? FileManager.default.contentsOfDirectory(atPath: root.path),
              !contents.isEmpty else {
            return
        }
        do {
            _ = try await LibraryScanner(database: database).scan(
                folder: root,
                kind: .managed
            )
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func downloadGoogleFont(_ family: GoogleFontFamily) async throws {
        guard let database else { return }
        let root = try googleFontsRoot()
        let folder = GoogleFontFamily.folderName(for: family)
        let urls = try await GoogleFontsService.shared.download(
            family,
            to: root.appendingPathComponent(folder, isDirectory: true)
        )
        let report = try await LibraryScanner(database: database).scan(
            changes: urls.map(\.path),
            folder: root,
            kind: .managed
        )
        status = "Downloaded \(family.name), \(report.faces) fonts"
        await reload()
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
            preview: preview
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
                let canonical = URL(fileURLWithPath: folder.path)
                    .resolvingSymlinksInPath().path
                if let stored = folders.first(where: { $0.path == canonical }) {
                    try? database.setDisplayName(folderID: stored.id, name: label)
                }
            }
        }
        folders = (try? database.folders()) ?? folders
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
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelectedSample() {
        guard let database, let id = selectedSampleID else { return }
        do {
            try database.deleteSample(id: id)
            samples = try database.samples()
            selectedSampleID = nil
        } catch {
            errorMessage = error.localizedDescription
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

    func invalidateCoverageRanges() {
        coverageRangesByFace = nil
    }

    func sampleText(for family: CatalogFamily) -> String {
        family.previewText(userText: sampleText)
    }

    func sampleText(for face: CatalogFace) -> String {
        FontScript.previewText(mask: face.scriptMask, userText: sampleText)
    }

    /// Long presets need a third line. Row height stays uniform across the list;
    /// only a sample change alters it.
    var previewRowHeight: CGFloat {
        if sampleText.count > 48 { return 224 }
        if sampleText.count > 28 { return 176 }
        return 128
    }

    var previewMaxLines: Int {
        previewRowHeight > 200 ? 4 : 2
    }

    // MARK: - Activation

    func refreshActive() {
        guard let database else { return }
        let updated = (try? database.activeFaceIDs()) ?? []
        guard updated != activeFaceIDs else { return }
        activeFaceIDs = updated
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
        if faces.contains(where: { ActivationEngine.isInstalledPath($0.path) }) {
            return .installed
        }
        let active = faces.reduce(0) { count, face in
            count + (activeFaceIDs.contains(face.id) ? 1 : 0)
        }
        if active == 0 { return .none }
        return active == family.faceCount ? .all : .partial
    }

    func faceActivation(_ face: CatalogFace) -> FamilyActivation {
        if ActivationEngine.isInstalledPath(face.path) {
            return .installed
        }
        return activeFaceIDs.contains(face.id) ? .all : .none
    }

    func toggle(face: CatalogFace) async {
        guard let activationEngine else { return }
        let target = ActivationTarget(
            faceID: face.id,
            path: face.path,
            postscriptName: face.postscriptName
        )
        let state = faceActivation(face)
        guard state != .installed else { return }
        status = state == .all
            ? "Deactivating \(face.style)…"
            : "Activating \(face.style)…"
        let outcome = state == .all
            ? await activationEngine.deactivate([target])
            : await activationEngine.activate([target], scope: .user, source: "manual")
        refreshActive()
        status = outcome.summary.isEmpty ? "No change" : outcome.summary
    }

    func revealInFinder(_ face: CatalogFace) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: face.path)])
    }

    func toggle(_ family: CatalogFamily) async {
        guard let activationEngine else { return }
        let faces = Array(snapshot.faces(in: family))
        guard !faces.isEmpty else { return }
        let state = familyActivation(family)
        guard state != .installed else { return }

        let targets = faces.map {
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

    func addFolder(_ url: URL, kind: FolderKind = .staticFolder) async {
        guard let database else { return }
        status = "Scanning \(url.lastPathComponent)…"
        do {
            let report = try await LibraryScanner(database: database)
                .scan(folder: url, kind: kind)
            status = report.summary
            await reload()
            folders = try database.folders()
            setupWatching()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Adds individual font files. Files already inside an indexed folder join
    /// that folder; other files join a one-time folder for their directory, so
    /// the sidebar still has a path to show and reveal.
    func addFontFiles(_ urls: [URL]) async {
        guard let database, !urls.isEmpty else { return }
        let extensions: Set<String> = ["ttf", "otf", "ttc", "otc", "dfont"]
        let files = urls.filter {
            extensions.contains($0.pathExtension.lowercased())
        }
        guard !files.isEmpty else {
            errorMessage = "No font files were selected."
            return
        }

        var grouped: [String: [URL]] = [:]
        for file in files {
            let directory = file.deletingLastPathComponent().standardizedFileURL.path
            grouped[directory, default: []].append(file)
        }

        status = "Adding \(files.count) \(files.count == 1 ? "font" : "fonts")…"
        do {
            let scanner = LibraryScanner(database: database)
            var addedFaces = 0
            for (directory, directoryFiles) in grouped {
                let covering = folders
                    .filter { directory == $0.path || directory.hasPrefix($0.path + "/") }
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
            errorMessage = error.localizedDescription
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
        for directory in directories {
            await addFolder(directory)
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
            errorMessage = error.localizedDescription
        }
    }

    func revealFolder(_ folder: LibraryFolder) {
        revealPath(folder.path)
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
        let prefix = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        return snapshot.faces.reduce(0) { count, face in
            count + (activeFaceIDs.contains(face.id) && face.path.hasPrefix(prefix) ? 1 : 0)
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
            errorMessage = error.localizedDescription
        }
    }

    func removeFolder(_ folder: LibraryFolder) async {
        guard let database else { return }
        // Deactivate first: removing rows would otherwise leave fonts active
        // with no journal entry to turn them off later.
        let prefix = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        let activeTargets = snapshot.faces
            .filter { $0.path.hasPrefix(prefix) && activeFaceIDs.contains($0.id) }
            .map {
                ActivationTarget(
                    faceID: $0.id,
                    path: $0.path,
                    postscriptName: $0.postscriptName
                )
            }
        if !activeTargets.isEmpty, let activationEngine {
            _ = await activationEngine.deactivate(activeTargets)
            refreshActive()
        }

        do {
            try await Task.detached {
                try database.removeFolder(id: folder.id)
            }.value
            if selection == .folder(folder.id) {
                selection = .all
            }
            if case .subfolder(let path) = selection,
               path.hasPrefix(folder.path + "/") {
                selection = .all
            }
            await reload()
            folders = try database.folders()
            setupWatching()
            status = "Removed \(folder.displayPath)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Watching

    private func setupWatching() {
        guard !CommandLine.arguments.contains("--headless") else { return }
        watcher?.stop()
        watcher = nil
        debounceTask?.cancel()
        sweepTask?.cancel()

        let roots = folders.filter { $0.kind == .watched }.map(\.path)
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
        guard let database else { return }
        var reloadNeeded = false
        let manager = FileManager.default

        for (root, paths) in changes {
            guard let folder = folders.first(where: { $0.path == root }) else { continue }

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
                    report = try await LibraryScanner(database: database)
                        .scan(folder: URL(fileURLWithPath: root), kind: folder.kind)
                } else {
                    report = try await LibraryScanner(database: database)
                        .scan(
                            changes: Array(paths),
                            folder: URL(fileURLWithPath: root),
                            kind: folder.kind
                        )
                }
                status = report.summary
                reloadNeeded = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if reloadNeeded {
            await reload()
        }
    }

    private func scan(rootPaths: [String]) async {
        guard let database else { return }
        var changed = false
        for path in rootPaths {
            guard let folder = folders.first(where: { $0.path == path }) else { continue }
            do {
                let report = try await LibraryScanner(database: database)
                    .scan(folder: URL(fileURLWithPath: path), kind: folder.kind)
                status = report.summary
                changed = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if changed {
            await reload()
        }
    }

    private func scheduleSweep() {
        sweepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled, let self else { return }
                let roots = self.folders
                    .filter { $0.kind == .watched }
                    .map(\.path)
                await self.scan(rootPaths: roots)
            }
        }
    }

    func rescanAll() async {
        guard let database else { return }
        for folder in folders {
            status = "Scanning \(folder.name)…"
            do {
                let report = try await LibraryScanner(database: database)
                    .scan(folder: URL(fileURLWithPath: folder.path), kind: folder.kind)
                status = report.summary
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        await reload()
        folders = (try? database.folders()) ?? folders
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
        for folder in folders {
            leafCounts[folder.name, default: 0] += 1
        }
        var titles: [String: String] = [:]
        for folder in folders {
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
        let visible = visibleFontCount.formatted()
        let total = selectionFontCount.formatted()
        if visibleFontCount == selectionFontCount {
            return "\(visible) \(visibleFontCount == 1 ? "font" : "fonts")"
        }
        return "\(visible) of \(total) \(selectionFontCount == 1 ? "font" : "fonts")"
    }

    func representativeFace(for family: CatalogFamily) -> CatalogFace? {
        let faces = snapshot.faces(in: family)
        return faces.first { !$0.isItalic && $0.weightClass == 400 }
            ?? faces.first { !$0.isItalic }
            ?? faces.first
    }

    private func familyIDs(forFolderPath path: String) -> Set<String> {
        if let cached = folderFamilyIDs[path] { return cached }
        let prefix = path.hasSuffix("/") ? path : path + "/"
        var ids = Set<String>()
        for face in snapshot.faces where face.path.hasPrefix(prefix) {
            ids.insert(face.familyKey)
        }
        folderFamilyIDs[path] = ids
        return ids
    }
}
