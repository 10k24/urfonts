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
    case all
    case folder(String)
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
    var folders: [LibraryFolder] = []
    var selection: SidebarSelection = .all
    var query: String = ""
    var viewMode: BrowserViewMode = .list
    var isLoading = true
    var status = ""
    var errorMessage: String?
    var activeFaceIDs: Set<String> = []

    // Preview settings. Persisted later with the rest of the user data.
    var sampleText = "Hamburgefonstiv"
    var sampleSize: Double = 28
    var textColor: Color = Color(nsColor: .labelColor)
    var backgroundColor: Color = Color(nsColor: .textBackgroundColor)

    @ObservationIgnored private var database: LibraryDatabase?
    @ObservationIgnored private var activationEngine: ActivationEngine?
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
            await reload()
            refreshActive()
            folders = try database.folders()
            isLoading = false
            setupWatching()
            Task { await reconcileActivation() }

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
        do {
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try database.snapshot()
            }.value
            self.snapshot = snapshot
            folderFamilyIDs.removeAll(keepingCapacity: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Activation

    func refreshActive() {
        guard let database else { return }
        activeFaceIDs = (try? database.activeFaceIDs()) ?? []
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

    func setWatched(_ folder: LibraryFolder, _ watched: Bool) async {
        guard let database else { return }
        do {
            try database.setKind(folderID: folder.id, kind: watched ? .watched : .staticFolder)
            folders = try database.folders()
            setupWatching()
            status = watched
                ? "Watching \(folder.displayPath)"
                : "Stopped watching \(folder.displayPath)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeFolder(_ folder: LibraryFolder) async {
        guard let database else { return }
        do {
            try await Task.detached {
                try database.removeFolder(id: folder.id)
            }.value
            if selection == .folder(folder.id) {
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

    var visibleFamilies: [CatalogFamily] {
        var families = snapshot.families
        if case .folder(let folderID) = selection,
           let folder = folders.first(where: { $0.id == folderID }) {
            let ids = familyIDs(forFolderPath: folder.path)
            families = families.filter { ids.contains($0.id) }
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !needle.isEmpty {
            families = families.filter { $0.searchText.contains(needle) }
        }
        return families
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
        let shown = visibleFamilies.count
        let total = snapshot.familyCount
        let faces = snapshot.faceCount
        if shown == total {
            return "\(total) families · \(faces) faces"
        }
        return "\(shown) of \(total) families · \(faces) faces"
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
