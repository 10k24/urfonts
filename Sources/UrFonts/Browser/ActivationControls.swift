import SwiftUI

/// Shared activation glyph. Family and face controls differ only in which state
/// they map to which symbol; rendering and hit targets live here.
struct ActivationGlyph: View {
    let symbol: String
    let tint: Color?
    let help: String
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    Image(systemName: symbol)
                        .font(.system(size: PreviewMetrics.activationIconSize))
                        .foregroundStyle(tint ?? .secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: PreviewMetrics.activationIconSize))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(
            width: PreviewMetrics.activationHitSize,
            height: PreviewMetrics.activationHitSize
        )
        .help(help)
        .accessibilityLabel(help)
    }
}

struct ActivationDot: View {
    let state: FamilyActivation
    let action: () -> Void

    var body: some View {
        switch state {
        case .installed:
            ActivationGlyph(
                symbol: "checkmark.square.fill",
                tint: nil,
                help: "Installed system font",
                action: nil
            )
        case .missing:
            ActivationGlyph(
                symbol: "questionmark.square",
                tint: nil,
                help: "File missing",
                action: nil
            )
        case .blocked(let ownerPath):
            ActivationGlyph(
                symbol: "square",
                tint: nil,
                help: "PostScript name already active from \(ownerPath)",
                action: nil
            )
        case .none:
            ActivationGlyph(
                symbol: "square",
                tint: .secondary,
                help: "Activate",
                action: action
            )
        case .partial:
            ActivationGlyph(
                symbol: "minus.square.fill",
                tint: .accentColor,
                help: "Partially active, click to activate all",
                action: action
            )
        case .all:
            ActivationGlyph(
                symbol: "checkmark.square.fill",
                tint: .accentColor,
                help: "Deactivate",
                action: action
            )
        }
    }
}

/// Per-file control in the font sheet. A duplicate PostScript name is visibly
/// blocked instead of failing after the click.
struct FaceActivationControl: View {
    let state: FaceActivationState
    let action: () -> Void

    var body: some View {
        switch state {
        case .available:
            ActivationGlyph(
                symbol: "square",
                tint: .secondary,
                help: "Activate",
                action: action
            )
        case .active:
            ActivationGlyph(
                symbol: "checkmark.square.fill",
                tint: .accentColor,
                help: "Deactivate",
                action: action
            )
        case .installed:
            ActivationGlyph(
                symbol: "checkmark.square.fill",
                tint: nil,
                help: "Installed system font",
                action: nil
            )
        case .missing:
            ActivationGlyph(
                symbol: "questionmark.square",
                tint: nil,
                help: "File missing",
                action: nil
            )
        case .blocked(let ownerPath):
            ActivationGlyph(
                symbol: "square",
                tint: nil,
                help: "PostScript name already active from \(ownerPath)",
                action: nil
            )
        }
    }
}
