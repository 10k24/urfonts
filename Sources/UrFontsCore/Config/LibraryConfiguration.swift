import Foundation

/// Versioned, portable settings file. Paths are absolute on this Mac; collections
/// refer to fonts by PostScript name so they survive a different folder layout.
public struct LibraryConfiguration: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public static let fileName = "urfonts-settings.json"

    public var version: Int
    public var exportedAt: String
    public var folders: [Folder]
    public var collections: [Collection]
    public var samples: [Sample]
    public var preview: Preview

    public struct Folder: Codable, Sendable, Equatable {
        public var path: String
        public var kind: String
        public var label: String?

        public init(path: String, kind: String, label: String?) {
            self.path = path
            self.kind = kind
            self.label = label
        }
    }

    public struct Collection: Codable, Sendable, Equatable {
        public var name: String
        public var sort: Int
        public var fonts: [String]

        public init(name: String, sort: Int, fonts: [String]) {
            self.name = name
            self.sort = sort
            self.fonts = fonts
        }
    }

    public struct Sample: Codable, Sendable, Equatable {
        public var name: String
        public var text: String
        public var size: Double
        public var textColor: String
        public var backgroundColor: String
        public var alignment: String

        public init(
            name: String,
            text: String,
            size: Double,
            textColor: String,
            backgroundColor: String,
            alignment: String
        ) {
            self.name = name
            self.text = text
            self.size = size
            self.textColor = textColor
            self.backgroundColor = backgroundColor
            self.alignment = alignment
        }
    }

    public struct Preview: Codable, Sendable, Equatable {
        public var text: String
        public var size: Double
        public var textColor: String
        public var backgroundColor: String
        public var showSystemFonts: Bool
        public var fallbackFileNames: Bool

        public init(
            text: String,
            size: Double,
            textColor: String,
            backgroundColor: String,
            showSystemFonts: Bool,
            fallbackFileNames: Bool
        ) {
            self.text = text
            self.size = size
            self.textColor = textColor
            self.backgroundColor = backgroundColor
            self.showSystemFonts = showSystemFonts
            self.fallbackFileNames = fallbackFileNames
        }
    }

    public init(
        version: Int = LibraryConfiguration.currentVersion,
        exportedAt: String,
        folders: [Folder],
        collections: [Collection],
        samples: [Sample],
        preview: Preview
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.folders = folders
        self.collections = collections
        self.samples = samples
        self.preview = preview
    }
}
