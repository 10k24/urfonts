import SwiftUI

/// Shared grid geometry for library and host family views.
enum FamilyGridLayout {
    static func columns(for width: CGFloat) -> [GridItem] {
        let spacing: CGFloat = 12
        let horizontalPadding: CGFloat = 32
        let minimumTile: CGFloat = 280
        let available = max(1, width - horizontalPadding)
        let fitting = Int((available + spacing) / (minimumTile + spacing))
        let count = min(4, max(1, fitting))
        return Array(
            repeating: GridItem(.flexible(), spacing: spacing),
            count: count
        )
    }
}
