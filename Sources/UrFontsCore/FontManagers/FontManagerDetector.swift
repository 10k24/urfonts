import Foundation

/// A cache or staging folder owned by another font manager. The app suggests
/// ignoring these so copies made for activation do not show up as duplicates.
public struct DetectedFontCache: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public let managerName: String
    public let label: String
    public let path: String

    public init(managerName: String, label: String, path: String) {
        self.managerName = managerName
        self.label = label
        self.path = path
    }
}

/// One detector per font manager. New managers implement this protocol and join
/// `FontManagerDetectors.all`; the settings UI never learns manager-specific
/// details.
public protocol FontManagerCacheDetecting: Sendable {
    var managerName: String { get }
    func detect() -> [DetectedFontCache]
}

public enum FontManagerDetectors {
    public static let all: [any FontManagerCacheDetecting] = [
        FontBaseCacheDetector(),
    ]

    public static func detectedCaches() -> [DetectedFontCache] {
        var seen = Set<String>()
        return all
            .flatMap { $0.detect() }
            .filter { seen.insert($0.path).inserted }
    }
}

/// FontBase stores its settings in Application Support and stages activated
/// fonts under the standard Fonts folders. The Root folder is user configurable
/// and lives in IndexedDB; the activation cache paths are the stable contract.
public struct FontBaseCacheDetector: FontManagerCacheDetecting {
    private let homeDirectory: String
    private let fileExists: @Sendable (String) -> Bool

    public init(
        homeDirectory: String = NSHomeDirectory(),
        fileExists: @escaping @Sendable (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        }
    ) {
        self.homeDirectory = homeDirectory
        self.fileExists = fileExists
    }

    public var managerName: String { "FontBase" }

    public func detect() -> [DetectedFontCache] {
        let configDirectories = [
            homeDirectory + "/Library/Application Support/FontBase",
            homeDirectory + "/Application Support/FontBase",
        ]
        guard configDirectories.contains(where: fileExists) else { return [] }

        let candidates = [
            homeDirectory + "/Library/Fonts/FontBase",
            "/Library/Fonts/FontBase",
        ]
        return candidates
            .filter(fileExists)
            .map { candidate in
                let path = LibraryPath.resolve(candidate)
                return DetectedFontCache(
                    managerName: managerName,
                    label: "\(managerName) cache folder",
                    path: path
                )
            }
    }
}
