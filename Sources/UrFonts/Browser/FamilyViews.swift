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
            // ASCII periods, not U+2026: some display fonts map the ellipsis
            // to a decorative or "NO GLYPH" stamp.
            let ellipsis = makeLine(text: "...", font: font, color: color)
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

    /// Grid tiles honor the sample size. Shrink only when one line is taller
    /// than the tile, then truncate horizontally. Width-fitting would make the
    /// size slider a no-op.
    static func drawGrid(
        text: String,
        font: CTFont,
        color: NSColor,
        in context: CGContext,
        rect: CGRect,
        inset: CGFloat = 6
    ) {
        let availableHeight = max(1, rect.height - inset * 2)
        let height = CTFontGetAscent(font) + CTFontGetDescent(font)
        let sized: CTFont
        if height > availableHeight {
            let scale = availableHeight / height
            sized = Self.font(from: font, size: max(8, CTFontGetSize(font) * scale))
        } else {
            sized = font
        }
        drawTruncated(
            text: text,
            font: sized,
            color: color,
            in: context,
            rect: rect,
            inset: inset
        )
    }

    /// Line breaks and vertical placement for a wrapped list preview.
    ///
    /// One owner for the geometry: the Canvas draws it and the row aligns the
    /// family metadata to `firstBaselineFromTop`.
    struct Layout {
        let lines: [CTLine]
        let lineHeight: CGFloat
        let inkAscent: CGFloat
        let top: CGFloat

        /// Distance from the top of the drawing rect to the first baseline.
        var firstBaselineFromTop: CGFloat { top + inkAscent }
    }

    /// List rows wrap to at most `maxLines`; the last line gets an ellipsis if
    /// the text does not fit. Grid tiles keep the single-line fitted drawing.
    static func layout(
        text: String,
        font: CTFont,
        width: CGFloat,
        height: CGFloat,
        inset: CGFloat = 6,
        maxLines: Int = 2
    ) -> Layout? {
        let availableWidth = max(1, width - inset * 2)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let totalLength = attributed.length
        guard totalLength > 0 else { return nil }

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
        guard !lines.isEmpty else { return nil }

        if start < totalLength, let last = lines.popLast() {
            // ASCII periods avoid a font's decorative U+2026 glyph.
            let ellipsis = makeLine(text: "...", font: font, color: .labelColor)
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
        if blockHeight <= height - 12 {
            top = max(0, (height - blockHeight) / 2)
        } else {
            top = 6
        }
        return Layout(
            lines: lines,
            lineHeight: lineHeight,
            inkAscent: inkAscent,
            top: top
        )
    }

    static func draw(
        layout: Layout,
        font: CTFont,
        color: NSColor,
        in context: CGContext,
        rect: CGRect,
        inset: CGFloat = 6
    ) {
        for (index, line) in layout.lines.enumerated() {
            let baseline = rect.height
                - layout.top
                - CGFloat(index) * layout.lineHeight
                - layout.inkAscent
            drawLine(
                line,
                font: font,
                color: color,
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
            font: font,
            color: color,
            in: context,
            rect: rect,
            x: x,
            baselineFromBottom: (rect.height - (ascent + descent)) / 2 + descent
        )
    }

    private static func drawLine(
        _ line: CTLine,
        font: CTFont,
        color: NSColor,
        in context: CGContext,
        rect: CGRect,
        x: CGFloat,
        baselineFromBottom: CGFloat
    ) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(color.cgColor)
        drawRuns(
            line,
            primaryFont: font,
            in: context,
            origin: CGPoint(x: x, y: baselineFromBottom)
        )
        context.restoreGState()
    }

    /// CoreText falls back to another installed font for missing characters.
    /// That is wrong for a font preview: the user must see this font's .notdef.
    /// Draw primary runs normally, and replace every fallback run's glyphs with
    /// the primary font's glyph 0 at the same positions.
    private static func drawRuns(
        _ line: CTLine,
        primaryFont: CTFont,
        in context: CGContext,
        origin: CGPoint
    ) {
        let primaryName = CTFontCopyPostScriptName(primaryFont) as String
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName] as! CTFont
            let runName = CTFontCopyPostScriptName(runFont) as String

            var glyphs = [CGGlyph](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for index in 0..<count {
                positions[index].x += origin.x
                positions[index].y += origin.y
            }

            if runName == primaryName {
                CTFontDrawGlyphs(runFont, glyphs, positions, count, context)
            } else {
                var tofu = [CGGlyph](repeating: 0, count: count)
                CTFontDrawGlyphs(primaryFont, &tofu, positions, count, context)
            }
        }
    }
}

// MARK: - Rows

extension VerticalAlignment {
    private enum PreviewBaseline: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    /// Aligns the family metadata's first text baseline with the first line of
    /// the preview. The Canvas supplies the guide from `PreviewLine.Layout`.
    static let previewBaseline = VerticalAlignment(PreviewBaseline.self)
}

/// A local font file used for a preview. Library rows pass a catalog face;
/// host rows pass their downloaded face or a lightweight preview subset.
struct PreviewSource: Equatable {
    let path: String
    let faceIndex: Int

    init(path: String, faceIndex: Int = 0) {
        self.path = path
        self.faceIndex = faceIndex
    }

    init(face: CatalogFace) {
        self.path = face.path
        self.faceIndex = face.index
    }
}

/// Display data shared by library and host rows. Keeps `FamilyRow` and
/// `FamilyTile` independent of `CatalogFamily`.
struct FamilyDisplay: Identifiable, Equatable {
    let id: String
    let name: String
    let countLabel: String
    let shortCount: String
    let hasVariableFace: Bool
    let warning: String?

    init(
        id: String,
        name: String,
        countLabel: String,
        shortCount: String,
        hasVariableFace: Bool,
        warning: String?
    ) {
        self.id = id
        self.name = name
        self.countLabel = countLabel
        self.shortCount = shortCount
        self.hasVariableFace = hasVariableFace
        self.warning = warning
    }

    init(family: CatalogFamily) {
        var reasons: [String] = []
        if family.hasDuplicatePostScriptNames {
            reasons.append("Multiple files share a PostScript name")
        }
        if family.missingFaceCount > 0 {
            reasons.append("\(family.missingFaceCount) file(s) missing")
        }
        self.init(
            id: family.id,
            name: family.name,
            countLabel: family.countLabel,
            shortCount: family.hasDuplicatePostScriptNames
                ? "\(family.faceCount) files"
                : "\(family.faceCount)",
            hasVariableFace: family.hasVariableFace,
            warning: reasons.isEmpty ? nil : reasons.joined(separator: ". ")
        )
    }

    init(google family: GoogleFontFamily) {
        let variants = family.variants.count
        self.init(
            id: family.name,
            name: family.name,
            countLabel: "\(variants) \(variants == 1 ? "variant" : "variants") · \(family.category)",
            shortCount: "\(variants)",
            hasVariableFace: family.isVariable,
            warning: family.files.isEmpty ? "No downloadable files" : nil
        )
    }
}

struct FamilyRow: View, Equatable {
    let display: FamilyDisplay
    let preview: PreviewSource?
    let sampleText: String
    let sampleSize: Double
    let textColor: Color
    let backgroundColor: Color
    let control: HostControlPhase
    let onToggle: () -> Void
    let maxLines: Int
    let rowHeight: CGFloat

    @State private var loaded: LoadedFont?
    @State private var previewLayout: PreviewLine.Layout?
    @State private var previewWidth: CGFloat = 0

    var body: some View {
        let previewBaseline = previewLayout?.firstBaselineFromTop ?? rowHeight / 2
        return HStack(alignment: .previewBaseline, spacing: 16) {
            metadata
                .alignmentGuide(.previewBaseline) { $0[.firstTextBaseline] }

            previewCanvas
                .alignmentGuide(.previewBaseline) { _ in previewBaseline }
        }
        .padding(.leading, PreviewMetrics.rowHorizontalInset)
        .padding(
            .trailing,
            PreviewMetrics.rowHorizontalInset
                + PreviewMetrics.rowTrailingInset
                + (display.hasVariableFace ? PreviewMetrics.variableBadgeReserve : 0)
        )
        .frame(height: rowHeight)
        .overlay(alignment: .trailing) { accessories }
        .background(backgroundColor)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.previewDivider(on: backgroundColor))
                .frame(height: 0.5)
        }
        .task(id: loadKey) {
            guard let preview else { return }
            loaded = await FontLoader.shared.font(
                path: preview.path,
                faceIndex: preview.faceIndex
            )
            updateLayout()
        }
        .onChange(of: layoutKey) { _, _ in
            updateLayout()
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(display.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let warning = display.warning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .help(warning)
                }
            }
            Text(display.countLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(width: 230, alignment: .leading)
    }

    private var previewCanvas: some View {
        ZStack(alignment: .leading) {
            Canvas { context, size in
                guard let loaded, let previewLayout else { return }
                let font = PreviewLine.font(from: loaded.ctFont, size: sampleSize)
                context.withCGContext { cg in
                    PreviewLine.draw(
                        layout: previewLayout,
                        font: font,
                        color: NSColor(textColor),
                        in: cg,
                        rect: CGRect(origin: .zero, size: size)
                    )
                }
            }
            if preview == nil {
                Text(display.name)
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { setPreviewWidth(proxy.size.width) }
                    .onChange(of: proxy.size.width) { _, width in
                        setPreviewWidth(width)
                    }
            }
        }
    }

    private var accessories: some View {
        HStack(spacing: PreviewMetrics.accessorySpacing) {
            if display.hasVariableFace {
                Text("VF")
                    .font(.system(size: PreviewMetrics.badgeFontSize, weight: .semibold))
                    .padding(.horizontal, PreviewMetrics.badgeHorizontalPadding)
                    .padding(.vertical, PreviewMetrics.badgeVerticalPadding)
                    .background(.quaternary, in: Capsule())
            }
            HostActivationControl(phase: control, action: onToggle)
        }
        .padding(.trailing, PreviewMetrics.rowHorizontalInset)
    }

    /// Size is deliberately not part of the key: it changes per slider tick and
    /// must not reload the face or blank the preview.
    private var loadKey: String {
        "\(preview?.path ?? ""):\(preview?.faceIndex ?? 0)"
    }

    /// Everything that changes the preview line breaks or vertical placement.
    private struct LayoutKey: Equatable {
        let path: String
        let faceIndex: Int
        let text: String
        let size: Double
        let maxLines: Int
        let rowHeight: CGFloat
        let width: CGFloat
    }

    private var layoutKey: LayoutKey {
        LayoutKey(
            path: preview?.path ?? "",
            faceIndex: preview?.faceIndex ?? 0,
            text: sampleText,
            size: sampleSize,
            maxLines: maxLines,
            rowHeight: rowHeight,
            width: previewWidth
        )
    }

    private func setPreviewWidth(_ width: CGFloat) {
        guard abs(previewWidth - width) > 0.5 else { return }
        previewWidth = width
    }

    private func updateLayout() {
        guard let loaded, previewWidth > 0 else {
            previewLayout = nil
            return
        }
        let font = PreviewLine.font(from: loaded.ctFont, size: sampleSize)
        previewLayout = PreviewLine.layout(
            text: sampleText,
            font: font,
            width: previewWidth,
            height: rowHeight,
            maxLines: maxLines
        )
    }

    static func == (left: FamilyRow, right: FamilyRow) -> Bool {
        left.display == right.display
            && left.preview == right.preview
            && left.sampleText == right.sampleText
            && left.sampleSize == right.sampleSize
            && left.textColor == right.textColor
            && left.backgroundColor == right.backgroundColor
            && left.control == right.control
            && left.maxLines == right.maxLines
            && left.rowHeight == right.rowHeight
    }
}

struct FamilyTile: View, Equatable {
    let display: FamilyDisplay
    let preview: PreviewSource?
    let sampleText: String
    let sampleSize: Double
    let textColor: Color
    let backgroundColor: Color
    let control: HostControlPhase
    let onToggle: () -> Void

    @State private var loaded: LoadedFont?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Canvas { context, size in
                    guard let loaded else { return }
                    let font = PreviewLine.font(from: loaded.ctFont, size: sampleSize)
                    context.withCGContext { cg in
                        PreviewLine.drawGrid(
                            text: sampleText,
                            font: font,
                            color: NSColor(textColor),
                            in: cg,
                            rect: CGRect(origin: .zero, size: size)
                        )
                    }
                }
                if preview == nil {
                    Text(display.name)
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 140)

            Divider()

            HStack {
                Text(display.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(display.shortCount)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help(display.countLabel)
                HostActivationControl(phase: control, action: onToggle)
            }
        }
        .padding(20)
        .frame(height: 240, alignment: .top)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.previewDivider(on: backgroundColor), lineWidth: 1)
        )
        .task(id: loadKey) {
            guard let preview else { return }
            loaded = await FontLoader.shared.font(
                path: preview.path,
                faceIndex: preview.faceIndex
            )
        }
    }

    private var loadKey: String {
        "\(preview?.path ?? ""):\(preview?.faceIndex ?? 0)"
    }

    static func == (left: FamilyTile, right: FamilyTile) -> Bool {
        left.display == right.display
            && left.preview == right.preview
            && left.sampleText == right.sampleText
            && left.sampleSize == right.sampleSize
            && left.textColor == right.textColor
            && left.backgroundColor == right.backgroundColor
            && left.control == right.control
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
                icon(
                    symbol: "checkmark.square.fill",
                    help: "Installed system font"
                )
            case .missing:
                icon(symbol: "questionmark.square", help: "File missing")
            case .blocked(let ownerPath):
                icon(
                    symbol: "square",
                    help: "PostScript name already active from \(ownerPath)"
                )
            case .none:
                button(symbol: "square", tint: .secondary, help: "Activate")
            case .partial:
                button(
                    symbol: "minus.square.fill",
                    tint: .accentColor,
                    help: "Partially active, click to activate all"
                )
            case .all:
                button(
                    symbol: "checkmark.square.fill",
                    tint: .accentColor,
                    help: "Deactivate"
                )
            }
        }
        .frame(
            width: PreviewMetrics.activationHitSize,
            height: PreviewMetrics.activationHitSize
        )
    }

    private func icon(symbol: String, help: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: PreviewMetrics.activationIconSize))
            .foregroundStyle(.tertiary)
            .help(help)
            .accessibilityLabel(help)
    }

    private func button(symbol: String, tint: Color, help: String) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: PreviewMetrics.activationIconSize))
                .foregroundStyle(tint)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Per-file control in the font sheet. A duplicate PostScript name is visibly
/// blocked instead of failing after the click.
struct FaceActivationControl: View {
    let state: FaceActivationState
    let action: () -> Void

    var body: some View {
        Group {
            switch state {
            case .available:
                button(symbol: "square", tint: .secondary, help: "Activate")
            case .active:
                button(
                    symbol: "checkmark.square.fill",
                    tint: .accentColor,
                    help: "Deactivate"
                )
            case .installed:
                icon(symbol: "checkmark.square.fill", help: "Installed system font")
            case .missing:
                icon(symbol: "questionmark.square", help: "File missing")
            case .blocked(let ownerPath):
                icon(
                    symbol: "square",
                    help: "PostScript name already active from \(ownerPath)"
                )
            }
        }
        .frame(
            width: PreviewMetrics.activationHitSize,
            height: PreviewMetrics.activationHitSize
        )
    }

    private func icon(symbol: String, help: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: PreviewMetrics.activationIconSize))
            .foregroundStyle(.tertiary)
            .help(help)
            .accessibilityLabel(help)
    }

    private func button(symbol: String, tint: Color, help: String) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: PreviewMetrics.activationIconSize))
                .foregroundStyle(tint)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
