import Foundation

public struct ActivationTarget: Sendable, Hashable {
    public let faceID: String
    public let path: String
    public let postscriptName: String

    public init(faceID: String, path: String, postscriptName: String) {
        self.faceID = faceID
        self.path = path
        self.postscriptName = postscriptName
    }
}

public struct ActivationOutcome: Sendable, Equatable {
    public var activated = 0
    public var deactivated = 0
    public var installedSkipped = 0
    public var failures: [String] = []

    public var summary: String {
        if !failures.isEmpty {
            return failures.prefix(2).joined(separator: "; ")
        }
        if activated > 0 {
            return "Activated \(activated) \(activated == 1 ? "font" : "fonts")"
        }
        if deactivated > 0 {
            return "Deactivated \(deactivated) \(deactivated == 1 ? "font" : "fonts")"
        }
        if installedSkipped > 0 {
            return "Already installed"
        }
        return ""
    }
}

public struct ReconcileOutcome: Sendable, Equatable {
    public let checked: Int
    public let dropped: Int
}

/// Turns UI intent into fontd state and keeps the journal honest.
///
/// Rules:
/// - Fonts in a standard Fonts folder are installed, not ours to toggle.
/// - Duplicate PostScript names are allowed. fontd accepts multiple files with
///   the same name; the UI warns when an installed font already owns it.
/// - Every success is measured with `CTFontManagerGetScopeForURL`; the journal
///   only records what fontd confirms.
public actor ActivationEngine {
    private let database: LibraryDatabase
    private let registrar: FontRegistrar

    public init(database: LibraryDatabase, registrar: FontRegistrar = CoreTextRegistrar()) {
        self.database = database
        self.registrar = registrar
    }

    public static func isInstalledPath(_ path: String) -> Bool {
        FontLocation.isInstalledFont(path: path)
    }

    public func activate(
        _ targets: [ActivationTarget],
        scope: FontRegistrationScope = .user,
        source: String = "manual"
    ) -> ActivationOutcome {
        var outcome = ActivationOutcome()
        let unique = Dictionary(grouping: targets, by: \.faceID).compactMap { $0.value.first }
            .sorted { ($0.path, $0.faceID) < ($1.path, $1.faceID) }

        var accepted: [ActivationTarget] = []
        for target in unique {
            if Self.isInstalledPath(target.path) {
                outcome.installedSkipped += 1
                continue
            }
            accepted.append(target)
        }

        let paths = Set(accepted.map(\.path))
        let toRegister = paths.filter { registrar.scope(of: URL(fileURLWithPath: $0)) != scope }

        var registrationFailures: [String: String] = [:]
        if !toRegister.isEmpty {
            let report = registrar.register(
                toRegister.sorted().map { URL(fileURLWithPath: $0) },
                scope: scope
            )
            for failure in report.failures {
                for url in failure.urls {
                    registrationFailures[url.path] = failure.message
                }
            }
        }

        var confirmedPaths = Set<String>()
        for path in paths {
            if registrar.scope(of: URL(fileURLWithPath: path)) == scope {
                confirmedPaths.insert(path)
            } else {
                let reason = registrationFailures[path] ?? "fontd did not confirm \(scope.rawValue) scope"
                outcome.failures.append("\((path as NSString).lastPathComponent): \(reason)")
            }
        }

        let confirmed = accepted.filter { confirmedPaths.contains($0.path) }
        if !confirmed.isEmpty {
            do {
                try database.insertActivations(
                    faceIDs: confirmed.map(\.faceID),
                    scope: scope,
                    source: source
                )
                outcome.activated = confirmed.count
            } catch {
                outcome.failures.append("journal: \(error.localizedDescription)")
            }
        }

        outcome.failures = Array(Set(outcome.failures)).sorted()
        return outcome
    }

    public func deactivate(_ targets: [ActivationTarget], source: String = "manual") -> ActivationOutcome {
        var outcome = ActivationOutcome()
        let unique = Dictionary(grouping: targets, by: \.faceID).compactMap { $0.value.first }

        let records = (try? database.activationRecords()) ?? []
        var scopeByPath: [String: FontRegistrationScope] = [:]
        for record in records {
            scopeByPath[record.path] = record.scope
        }

        var pathsByScope: [FontRegistrationScope: Set<String>] = [:]
        var skipped = 0
        for target in unique {
            if Self.isInstalledPath(target.path) {
                skipped += 1
                continue
            }
            let scope = scopeByPath[target.path] ?? .user
            pathsByScope[scope, default: []].insert(target.path)
        }
        outcome.installedSkipped = skipped

        var clearedPaths = Set<String>()
        var messages = Set<String>()

        for (scope, paths) in pathsByScope {
            let report = registrar.unregister(
                paths.sorted().map { URL(fileURLWithPath: $0) },
                scope: scope
            )
            for failure in report.failures {
                for url in failure.urls {
                    messages.insert("\((url.path as NSString).lastPathComponent): \(failure.message)")
                }
            }
            for path in paths where registrar.scope(of: URL(fileURLWithPath: path)) == .none {
                clearedPaths.insert(path)
            }
        }

        let cleared = unique.filter { clearedPaths.contains($0.path) }
        if !cleared.isEmpty {
            do {
                try database.deleteActivations(faceIDs: cleared.map(\.faceID))
                outcome.deactivated = cleared.count
            } catch {
                messages.insert("journal: \(error.localizedDescription)")
            }
        }
        outcome.failures = Array(messages).sorted()
        return outcome
    }

    /// Drop journal rows whose scope no longer matches fontd. Never registers
    /// anything at launch.
    public func reconcile() -> ReconcileOutcome {
        let records = (try? database.activationRecords()) ?? []
        var stale: [String] = []
        for record in records {
            let actual = registrar.scope(of: URL(fileURLWithPath: record.path))
            if actual != record.scope {
                stale.append(record.faceID)
            }
        }
        if !stale.isEmpty {
            try? database.deleteActivations(faceIDs: stale)
        }
        return ReconcileOutcome(checked: records.count, dropped: stale.count)
    }
}
