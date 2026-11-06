import AppKit
import CoreText
import SwiftUI
import UrFontsCore

/// Draws one line of preview text into a Canvas context.
///
/// Canvas contexts are y-down. CoreText draws y-up, so the context is flipped
/// around the bottom edge of the rect and the baseline is measured from there.
enum PreviewLine {
    static func font(from base: CTFont, size: CGFloat) -> CTFont {
        CTFontCreateCopyWithAttributes(base, size, nil, nil)
    }

    /// List rows truncate with an ellipsis. The sample size is the user's.
    static func drawTruncated(
        text: String,
        font: CTFont,
        color: NSColor,
        in context: CGContext,
        rect: CGRect,
        inset: CGFloat = 6
    ) {
        let available = max(1, rect.width - inset * 2)
        var line = makeLine(text: text, font: font, color: color)
        if CTLineGetTypographicBounds(line, nil, nil, nil) > available {
            let ellipsis = makeLine(text: "…", font: font, color: color)
            if let truncated = CTLineCreateTruncatedLine(
                line,
                Double(available),
                .end,
                ellipsis
            ) {
                line = truncated
            }
        }
        draw(line, font: font, color: color, in: context, rect: rect, x: inset)
    }

    /// Grid tiles fit instead of truncating: a wide font shrinks until the whole
    /// sample is visible. Cropping here reads as broken spacing.
    static func drawFitted(
        text: String,
        font: CTFont,
        color: NSColor,
        in context: CGContext,
        rect: CGRect,
        inset: CGFloat = 6
    ) {
        let availableWidth = max(1, rect.width - inset * 2)
        let availableHeight = max(1, rect.height - inset * 2)
        let probe = makeLine(text: text, font: font, color: color)
        let width = CTLineGetTypographicBounds(probe, nil, nil, nil)
        let height = CTFontGetAscent(font) + CTFontGetDescent(font)

        var scale: CGFloat = 1
        if width > availableWidth {
            scale = min(scale, availableWidth / width)
        }
        if height > availableHeight {
            scale = min(scale, availableHeight / height)
        }
        let size = max(8, CTFontGetSize(font) * scale)
        let fitted = Self.font(from: font, size: size)
        let line = makeLine(text: text, font: fitted, color: color)
        draw(line, font: fitted, color: color, in: context, rect: rect, x: inset)
    }

    /// List rows wrap to at most `maxLines`; the last line gets an ellipsis if
    /// the text does not fit. Grid tiles keep the single-line fitted drawing.
    static func drawWrapped(
        text: String,
        font: CTFont,
        color: NSColor,
        in context: CGContext,
        rect: CGRect,
        inset: CGFloat = 6,
        maxLines: Int = 2
    ) {
        let availableWidth = max(1, rect.width - inset * 2)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let totalLength = attributed.length
        guard totalLength > 0 else { return }

        var lines: [CTLine] = []
        var start = 0
        while start < totalLength, lines.count < maxLines {
            let count = CTTypesetterSuggestLineBreak(
                typesetter,
                start,
                Double(availableWidth)
            )
            guard count > 0 else { break }
            lines.append(CTTypesetterCreateLine(
                typesetter,
                CFRange(location: start, length: count)
            ))
            start += count
        }
        guard !lines.isEmpty else { return }

        if start < totalLength, let last = lines.popLast() {
            let ellipsis = makeLine(text: "…", font: font, color: color)
            let truncated = CTLineCreateTruncatedLine(
                last,
                Double(availableWidth),
                .end,
                ellipsis
            )
            lines.append(truncated ?? last)
        }

        // Display faces often draw past their font metrics. Measure the ink of
        // each line and space baselines by the largest ink box, otherwise lines
        // overlap.
        var inkAscent: CGFloat = 0
        var inkDescent: CGFloat = 0
        for line in lines {
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            // Text space is y-up: maxY is the ink above the baseline, minY below.
            inkAscent = max(inkAscent, bounds.maxY)
            inkDescent = max(inkDescent, -bounds.minY)
        }
        let metricsHeight = CTFontGetAscent(font)
            + CTFontGetDescent(font)
            + CTFontGetLeading(font)
        let lineHeight = max(metricsHeight, inkAscent + inkDescent) + 2
        let blockHeight = CGFloat(lines.count) * lineHeight
        // Center when the block fits. When the text is larger than the row, pin
        // it to the top so scaling grows downward instead of clipping upward.
        let top: CGFloat
        if blockHeight <= rect.height - 12 {
            top = max(0, (rect.height - blockHeight) / 2)
        } else {
            top = 6
        }

        for (index, line) in lines.enumerated() {
            let baseline = rect.height - top - CGFloat(index) * lineHeight - inkAscent
            drawLine(
                line,
                in: context,
                rect: rect,
                x: inset,
                baselineFromBottom: baseline
            )
        }
    }

    private static func makeLine(text: String, font: CTFont, color: NSColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        return CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes)
        )
    }

    private static func draw(
        _ line: CTLine,
        font: CTFont,
        color: NSColor,
        in context: CGContext,
        rect: CGRect,
        x: CGFloat
    ) {
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        drawLine(
            line,
            in: context,
            rect: rect,
            x: x,
            baselineFromBottom: (rect.height - (ascent + descent)) / 2 + descent
        )
    }

    private static func drawLine(
        _ line: CTLine,
        in context: CGContext,
        rect: CGRect,
        x: CGFloat,
        baselineFromBottom: CGFloat
    ) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: baselineFromBottom)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

// MARK: - Rows

struct FamilyRow: View, Equatable {
    let family: CatalogFamily
    let face: CatalogFace?
    let sampleText: String
    let sampleSize: Double
    let textColor: Color
    let backgroundColor: Color
    let activation: FamilyActivation
    let onToggle: () -> Void
    let maxLines: Int
    let rowHeight: CGFloat

    @State private var loaded: LoadedFont?

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(family.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("\(family.faceCount) \(family.faceCount == 1 ? "style" : "styles")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 230, alignment: .leading)

            Canvas { context, size in
                guard let loaded else { return }
                let font = PreviewLine.font(from: loaded.ctFont, size: sampleSize)
                context.withCGContext { cg in
                    PreviewLine.drawWrapped(
                        text: sampleText,
                        font: font,
                        color: NSColor(textColor),
                        in: cg,
                        rect: CGRect(origin: .zero, size: size),
                        maxLines: maxLines
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if family.hasVariableFace {
                Text("VF")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            ActivationDot(state: activation, action: onToggle)
        }
        .padding(.leading, 20)
        .padding(.trailing, 28)
        .frame(height: rowHeight)
        .background(backgroundColor)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.previewDivider(on: backgroundColor))
                .frame(height: 0.5)
        }
        .task(id: loadKey) {
            guard let face else { return }
            loaded = await FontLoader.shared.font(
                path: face.path,
                faceIndex: face.index
            )
        }
    }

    /// Size is deliberately not part of the key: it changes per slider tick and
    /// must not reload the face or blank the preview.
    private var loadKey: String {
        "\(face?.path ?? ""):\(face?.index ?? 0)"
    }

    static func == (left: FamilyRow, right: FamilyRow) -> Bool {
        left.family == right.family
            && left.face?.path == right.face?.path
            && left.face?.index == right.face?.index
            && left.sampleText == right.sampleText
            && left.sampleSize == right.sampleSize
            && left.textColor == right.textColor
            && left.backgroundColor == right.backgroundColor
            && left.activation == right.activation
            && left.maxLines == right.maxLines
            && left.rowHeight == right.rowHeight
    }
}

struct FamilyTile: View, Equatable {
    let family: CatalogFamily
    let face: CatalogFace?
    let sampleText: String
    let sampleSize: Double
    let textColor: Color
    let backgroundColor: Color
    let activation: FamilyActivation
    let onToggle: () -> Void

    @State private var loaded: LoadedFont?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in
                guard let loaded else { return }
                let font = PreviewLine.font(from: loaded.ctFont, size: sampleSize)
                context.withCGContext { cg in
                    PreviewLine.drawFitted(
                        text: sampleText,
                        font: font,
                        color: NSColor(textColor),
                        in: cg,
                        rect: CGRect(origin: .zero, size: size)
                    )
                }
            }
            .frame(height: 76)

            Divider()

            HStack {
                Text(family.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text("\(family.faceCount)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help(
                        "\(family.faceCount) \(family.faceCount == 1 ? "style" : "styles")"
                    )
                ActivationDot(state: activation, action: onToggle)
            }
        }
        .padding(20)
        .frame(height: 170, alignment: .top)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.previewDivider(on: backgroundColor), lineWidth: 1)
        )
        .task(id: loadKey) {
            guard let face else { return }
            loaded = await FontLoader.shared.font(
                path: face.path,
                faceIndex: face.index
            )
        }
    }

    private var loadKey: String {
        "\(face?.path ?? ""):\(face?.index ?? 0)"
    }

    static func == (left: FamilyTile, right: FamilyTile) -> Bool {
        left.family == right.family
            && left.face?.path == right.face?.path
            && left.face?.index == right.face?.index
            && left.sampleText == right.sampleText
            && left.sampleSize == right.sampleSize
            && left.textColor == right.textColor
            && left.backgroundColor == right.backgroundColor
            && left.activation == right.activation
    }
}

// MARK: - Activation

struct ActivationDot: View {
    let state: FamilyActivation
    let action: () -> Void

    var body: some View {
        Group {
            switch state {
            case .installed:
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .help("Installed system font")
            case .none:
                button(symbol: "circle", tint: .secondary, help: "Activate")
            case .partial:
                button(symbol: "circle.lefthalf.filled", tint: .accentColor, help: "Partially active, click to activate all")
            case .all:
                button(symbol: "circle.fill", tint: .accentColor, help: "Deactivate")
            }
        }
        .frame(width: 20, height: 20)
    }

    private func button(symbol: String, tint: Color, help: String) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
