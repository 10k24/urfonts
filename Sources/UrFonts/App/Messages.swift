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
        static let appearance = String(
            localized: "settings.appearance",
            defaultValue: "Appearance",
            comment: "Settings section"
        )
        static let appearanceHelp = String(
            localized: "settings.appearance.help",
            defaultValue: "System follows your Mac setting. Light and Dark apply to every window, panel and menu.",
            comment: "Settings help"
        )
        static let appearanceSystem = String(
            localized: "settings.appearance.system",
            defaultValue: "System",
            comment: "Appearance option"
        )
        static let appearanceLight = String(
            localized: "settings.appearance.light",
            defaultValue: "Light",
            comment: "Appearance option"
        )
        static let appearanceDark = String(
            localized: "settings.appearance.dark",
            defaultValue: "Dark",
            comment: "Appearance option"
        )
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
        static let cloud = String(
            localized: "activation.cloud",
            defaultValue: "Not downloaded from cloud",
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

    enum About {
        static let menuItem = String(
            localized: "about.menuItem",
            defaultValue: "About Ur Fonts",
            comment: "About menu item"
        )
        static let applicationName = String(
            localized: "about.applicationName",
            defaultValue: "Ur Fonts",
            comment: "About panel app name"
        )
        static let byline = String(
            localized: "about.byline",
            defaultValue: "Ur Fonts by 10k24 Studio",
            comment: "About credits byline"
        )
        static let summary = String(
            localized: "about.summary",
            defaultValue: "A font manager for large libraries.",
            comment: "About credits summary"
        )
        static let repository = String(
            localized: "about.repository",
            defaultValue: "github.com/10k24/urfonts",
            comment: "About repository link"
        )
    }

    enum Welcome {
        static let title = String(
            localized: "welcome.title",
            defaultValue: "Welcome to Ur Fonts",
            comment: "First-run title"
        )
        static let intro = String(
            localized: "welcome.intro",
            defaultValue: "A font manager for large libraries. Your font files stay where they are.",
            comment: "First-run introduction"
        )
        static let filesTitle = String(
            localized: "welcome.files.title",
            defaultValue: "Read-only by design",
            comment: "First-run point"
        )
        static let filesBody = String(
            localized: "welcome.files.body",
            defaultValue: "Ur Fonts reads fonts where they live. It never moves, renames, copies or edits them.",
            comment: "First-run point"
        )
        static let foldersTitle = String(
            localized: "welcome.folders.title",
            defaultValue: "Start with a folder",
            comment: "First-run point"
        )
        static let foldersBody = String(
            localized: "welcome.folders.body",
            defaultValue: "Add a folder to watch it for changes, or scan it once. It appears in the sidebar under Folders.",
            comment: "First-run point"
        )
        static let activationTitle = String(
            localized: "welcome.activation.title",
            defaultValue: "Activation is global",
            comment: "First-run point"
        )
        static let activationBody = String(
            localized: "welcome.activation.body",
            defaultValue: "The checkbox makes a family available to every app for your user. Apps may need a relaunch before they see a newly active font.",
            comment: "First-run point"
        )
        static let addFolder = String(
            localized: "welcome.addFolder",
            defaultValue: "Add Folder…",
            comment: "First-run button"
        )
        static let explore = String(
            localized: "welcome.explore",
            defaultValue: "Explore the Library",
            comment: "First-run button"
        )
    }

    enum Help {
        static let title = String(
            localized: "help.title",
            defaultValue: "Ur Fonts Help",
            comment: "Help window title"
        )
        static let menuItem = String(
            localized: "help.menuItem",
            defaultValue: "Ur Fonts Help",
            comment: "Help menu item"
        )
        static let intro = String(
            localized: "help.intro",
            defaultValue: "Ur Fonts indexes font folders without copying or changing files. These notes cover the behavior that is easy to miss.",
            comment: "Help introduction"
        )
        static let libraryTitle = String(
            localized: "help.library.title",
            defaultValue: "Library and folders",
            comment: "Help section"
        )
        static let libraryBody = String(
            localized: "help.library.body",
            defaultValue: "Add folders once; watch a folder to pick up changes, or scan it once. Ignored folders stay in the sidebar with a slash icon and are skipped by scans. Online-only cloud files appear after the provider downloads them; they are not errors.",
            comment: "Help section"
        )
        static let activationTitle = String(
            localized: "help.activation.title",
            defaultValue: "Activation",
            comment: "Help section"
        )
        static let activationBody = String(
            localized: "help.activation.body",
            defaultValue: "The checkbox activates a family for the current user, globally. The font sheet lists every file and can activate one style. Installed fonts in system Fonts folders are locked. If two files share a PostScript name, only one can be active; the other is disabled. Apps usually refresh their font menus on launch, so activate first, then open the app.",
            comment: "Help section"
        )
        static let previewTitle = String(
            localized: "help.preview.title",
            defaultValue: "Previews",
            comment: "Help section"
        )
        static let previewBody = String(
            localized: "help.preview.body",
            defaultValue: "Click a family to preview it. The sample text, size and colors are in Preview settings (⌘E). Missing characters show the font's .notdef glyph; another font is never substituted. Variable fonts expose axis sliders in the font sheet.",
            comment: "Help section"
        )
        static let warningsTitle = String(
            localized: "help.warnings.title",
            defaultValue: "Warnings",
            comment: "Help section"
        )
        static let warningsBody = String(
            localized: "help.warnings.body",
            defaultValue: "Warnings lists duplicate PostScript names and files that are missing or unreadable. Removing an entry deletes only the library row; the file on disk is untouched. A later scan adds it back if the file returns.",
            comment: "Help section"
        )
        static let googleTitle = String(
            localized: "help.google.title",
            defaultValue: "Google Fonts",
            comment: "Help section"
        )
        static let googleBody = String(
            localized: "help.google.body",
            defaultValue: "Google Fonts is a host in the sidebar. Clicking its activation square downloads the style, indexes it and activates it. Licenses are saved beside the downloaded fonts. Downloaded families behave like local fonts.",
            comment: "Help section"
        )
        static let limitsTitle = String(
            localized: "help.limits.title",
            defaultValue: "Known limits",
            comment: "Help section"
        )
        static let limitsBody = String(
            localized: "help.limits.body",
            defaultValue: "macOS 15 or later. WOFF and WOFF2 are not rendered. There are no tags, favorites, Quick Look or document preflight yet. Downloading or ignoring folders never moves or edits a font file.",
            comment: "Help section"
        )
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
