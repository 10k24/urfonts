import Foundation

/// One directory in the sidebar tree. Roots are added folders; children come
/// from the paths of indexed files. Counts are faces (fonts), matching the
/// All Fonts row.
struct FolderNode: Identifiable, Hashable {
    let id: String
    let name: String
    let fontCount: Int
    let children: [FolderNode]?
    let folderID: String?
    let isWatched: Bool
}
