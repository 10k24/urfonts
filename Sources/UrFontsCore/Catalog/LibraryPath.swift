import Foundation

/// Canonical paths shared by the scanner, watcher, and import paths.
///
/// `realpath` resolves the `/var` firmlink, which Foundation treats as already
/// standardized. Without it, stored paths and FSEvents paths disagree and every
/// delta looks like a new file.
public enum LibraryPath {
    /// How one canonical path relates to another.
    public enum Relation: Sendable, Equatable {
        /// Same path.
        case same
        /// The first path contains the second.
        case ancestor
        /// The first path is inside the second.
        case descendant
        case unrelated
    }

    /// Resolve a path typed or picked by the user.
    ///
    /// Accepts `~`, trims whitespace and resolves symlinks plus the `/var`
    /// firmlink. Use this at every user boundary; `canonical` assumes an
    /// already expanded path.
    public static func resolve(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return canonical((trimmed as NSString).expandingTildeInPath)
    }

    public static func canonical(_ path: String) -> String {
        if let resolved = realpath(path, nil) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        // Deleted file: resolve the parent, keep the leaf.
        let parent = (path as NSString).deletingLastPathComponent
        let leaf = (path as NSString).lastPathComponent
        if !parent.isEmpty, parent != "/", let resolved = realpath(parent, nil) {
            defer { free(resolved) }
            return String(cString: resolved) + "/" + leaf
        }
        return path
    }

    /// True when `path` is `root` or lives inside it.
    public static func isInside(_ path: String, root: String) -> Bool {
        if path == root { return true }
        if root == "/" { return path.hasPrefix("/") }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix)
    }

    /// `first` relative to `second`, using canonical or resolved paths.
    public static func relation(_ first: String, _ second: String) -> Relation {
        if first == second { return .same }
        if isInside(second, root: first) { return .ancestor }
        if isInside(first, root: second) { return .descendant }
        return .unrelated
    }
}
