import CoreGraphics

/// One source for activation-control sizing.
///
/// Rows, grid tiles and the font page all read these values, so changing
/// `controlScale` resizes every checkbox, hit target and VF badge together.
enum PreviewMetrics {
    static let controlScale: CGFloat = 1.5

    static let activationIconSize: CGFloat = (15 * controlScale).rounded()
    static let activationHitSize: CGFloat = (20 * controlScale).rounded()
    static let badgeFontSize: CGFloat = (9 * controlScale).rounded()
    static let badgeHorizontalPadding: CGFloat = (5 * controlScale).rounded()
    static let badgeVerticalPadding: CGFloat = (2 * controlScale).rounded()
    static let accessorySpacing: CGFloat = (10 * controlScale).rounded()
    /// Outermost row margin. One value for both edges, so metadata and the
    /// activation column can never drift apart.
    static let rowHorizontalInset: CGFloat = 28
    /// Gap between the preview and the accessory column.
    static let rowAccessoryGap: CGFloat = (8 * controlScale).rounded()
    /// Space the preview keeps clear for the accessory column, excluding the
    /// row edge margin.
    static let rowTrailingInset: CGFloat = activationHitSize + rowAccessoryGap
    /// Extra space kept clear when the VF badge is present.
    static let variableBadgeReserve: CGFloat = (32 * controlScale).rounded()

    /// Width left for the preview after the metadata column and the widest
    /// trailing accessories. One height serves every row, so reserve the VF
    /// badge even when the current family lacks it.
    static func listPreviewWidth(for rowWidth: CGFloat) -> CGFloat {
        let fixed = rowHorizontalInset + 230 + 16
            + rowHorizontalInset
            + rowTrailingInset
            + variableBadgeReserve
        return max(1, rowWidth - fixed)
    }
}
