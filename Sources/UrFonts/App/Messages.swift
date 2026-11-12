import Foundation

/// Central user-facing strings. New UI copy goes here so localization can be
/// added without hunting through views.
enum Messages {
    enum Sidebar {
        static let library = String(
            localized: "sidebar.library",
            defaultValue: "Library",
            comment: "Sidebar section"
        )
        static let allFonts = String(
            localized: "sidebar.allFonts",
            defaultValue: "All Fonts",
            comment: "Sidebar row"
        )
        static let active = String(
            localized: "sidebar.active",
            defaultValue: "Active",
            comment: "Sidebar row"
        )
        static let warnings = String(
            localized: "sidebar.warnings",
            defaultValue: "Warnings",
            comment: "Sidebar row"
        )
        static let hosts = String(
            localized: "sidebar.hosts",
            defaultValue: "Hosts",
            comment: "Sidebar section"
        )
        static let folders = String(
            localized: "sidebar.folders",
            defaultValue: "Folders",
            comment: "Sidebar section"
        )
        static let collections = String(
            localized: "sidebar.collections",
            defaultValue: "Collections",
            comment: "Sidebar section"
        )
        static let googleFonts = String(
            localized: "sidebar.googleFonts",
            defaultValue: "Google Fonts",
            comment: "Host row"
        )

        static func allFontsHelp(families: Int, fonts: Int) -> String {
            String(
                localized: "sidebar.allFonts.help",
                defaultValue: "\(families) families · \(fonts) fonts",
                comment: "All Fonts tooltip"
            )
        }

        static func activeHelp(_ count: Int) -> String {
            String(
                localized: "sidebar.active.help",
                defaultValue: "\(count) active \(count == 1 ? "font" : "fonts")",
                comment: "Active tooltip"
            )
        }

        static let warningsHelp = String(
            localized: "sidebar.warnings.help",
            defaultValue: "Duplicate PostScript names and missing files",
            comment: "Warnings tooltip"
        )
        static let googleFontsHelp = String(
            localized: "sidebar.googleFonts.help",
            defaultValue: "Browse and download Google Fonts",
            comment: "Hosts tooltip"
        )
    }

    enum Settings {
        static let ignoredFolders = String(
            localized: "settings.ignoredFolders",
            defaultValue: "Ignored Folders",
            comment: "Settings title"
        )
        static let ignoredFoldersHelp = String(
            localized: "settings.ignoredFolders.help",
            defaultValue: "Add folders here to omit them from your library, including re-scans. The files stay on disk.",
            comment: "Settings help"
        )
        static let noIgnoredFolders = String(
            localized: "settings.ignoredFolders.empty",
            defaultValue: "No ignored folders.",
            comment: "Settings empty state"
        )
        static let addFolder = String(
            localized: "settings.addFolder",
            defaultValue: "Add Folder…",
            comment: "Settings button"
        )
        static let detectedManagers = String(
            localized: "settings.detectedManagers",
            defaultValue: "Detected Font Managers",
            comment: "Settings section"
        )
        static let addToIgnoreList = String(
            localized: "settings.addToIgnoreList",
            defaultValue: "Add to Ignore List",
            comment: "Settings button"
        )
    }

    enum Google {
        static let styles = String(
            localized: "google.styles",
            defaultValue: "Styles",
            comment: "Google family section"
        )
        static let done = String(
            localized: "common.done",
            defaultValue: "Done",
            comment: "Sheet button"
        )
        static let readLicense = String(
            localized: "google.readLicense",
            defaultValue: "Read License",
            comment: "Unknown license label"
        )
        static let noPreview = String(
            localized: "google.noPreview",
            defaultValue: "No preview",
            comment: "Empty preview"
        )
        static let loadingCatalog = String(
            localized: "google.loadingCatalog",
            defaultValue: "Loading catalog…",
            comment: "Google loading"
        )
        static let couldNotLoad = String(
            localized: "google.couldNotLoad",
            defaultValue: "Could not load Google Fonts",
            comment: "Google error title"
        )
        static let retry = String(
            localized: "common.retry",
            defaultValue: "Retry",
            comment: "Retry button"
        )
        static let noFonts = String(
            localized: "google.noFonts",
            defaultValue: "No Google Fonts",
            comment: "Google empty state"
        )
    }

    enum Activation {
        static let activate = String(
            localized: "activation.activate",
            defaultValue: "Activate",
            comment: "Activation help"
        )
        static let partial = String(
            localized: "activation.partial",
            defaultValue: "Partially active, click to activate all",
            comment: "Activation help"
        )
        static let deactivate = String(
            localized: "activation.deactivate",
            defaultValue: "Deactivate",
            comment: "Activation help"
        )
        static let installed = String(
            localized: "activation.installed",
            defaultValue: "Installed system font",
            comment: "Activation help"
        )
        static let fileMissing = String(
            localized: "activation.fileMissing",
            defaultValue: "File missing",
            comment: "Activation help"
        )
        static let downloadAndActivate = String(
            localized: "activation.downloadAndActivate",
            defaultValue: "Download and activate",
            comment: "Host activation"
        )
        static let downloading = String(
            localized: "activation.downloading",
            defaultValue: "Downloading",
            comment: "Host progress"
        )
        static let noDownloadableFiles = String(
            localized: "activation.noDownloadableFiles",
            defaultValue: "No downloadable files",
            comment: "Host unavailable"
        )

        static func blocked(ownerPath: String) -> String {
            String(
                localized: "activation.blocked.owner",
                defaultValue: "PostScript name already active from \(ownerPath)",
                comment: "Activation help with owner"
            )
        }
    }

    enum Problems {
        static let noWarnings = String(
            localized: "problems.noWarnings",
            defaultValue: "No warnings",
            comment: "Warnings empty title"
        )
        static let noWarningsDetail = String(
            localized: "problems.noWarnings.detail",
            defaultValue: "No duplicate PostScript names and no missing files.",
            comment: "Warnings empty detail"
        )
        static let duplicates = String(
            localized: "problems.duplicates",
            defaultValue: "Duplicate PostScript names",
            comment: "Warnings section"
        )
        static let missing = String(
            localized: "problems.missing",
            defaultValue: "Missing or unreadable files",
            comment: "Warnings section"
        )
    }
}
