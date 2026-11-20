import AppKit
import CoreText
import SwiftUI
import UrFontsCore

enum GlyphSection: String, CaseIterable, Identifiable {
    case basicLatin
    case latinSupplement
    case latinExtended
    case greek
    case cyrillic
    case hebrew
    case arabic
    case devanagari
    case thai
    case cjk
    case hiragana
    case katakana
    case hangul
    case symbols
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basicLatin: "Basic Latin"
        case .latinSupplement: "Latin-1 Supplement"
        case .latinExtended: "Latin Extended"
        case .greek: "Greek"
        case .cyrillic: "Cyrillic"
        case .hebrew: "Hebrew"
        case .arabic: "Arabic"
        case .devanagari: "Devanagari"
        case .thai: "Thai"
        case .cjk: "CJK"
        case .hiragana: "Hiragana"
        case .katakana: "Katakana"
        case .hangul: "Hangul"
        case .symbols: "Symbols"
        case .other: "Other"
        }
    }

    static func section(for value: UInt32) -> GlyphSection {
        switch value {
        case 0x0000...0x007F: .basicLatin
        case 0x0080...0x00FF: .latinSupplement
        case 0x0100...0x024F: .latinExtended
        case 0x0370...0x03FF, 0x1F00...0x1FFF: .greek
        case 0x0400...0x052F: .cyrillic
        case 0x0590...0x05FF: .hebrew
        case 0x0600...0x06FF, 0x0750...0x077F: .arabic
        case 0x0900...0x097F: .devanagari
        case 0x0E00...0x0E7F: .thai
        case 0x3040...0x309F: .hiragana
        case 0x30A0...0x30FF: .katakana
        case 0x1100...0x11FF, 0xAC00...0xD7AF: .hangul
        case 0x2000...0x2BFF, 0x1F000...0x1FAFF: .symbols
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x20000...0x3FFFF: .cjk
        default: .other
        }
    }
}

/// Character map for one face. Built from the font's own cmap via CoreText, so
/// it works for inactive fonts without registering anything.
struct GlyphMapView: View {
    let face: CatalogFace
    let textColor: Color

    @State private var loaded: LoadedFont?
    @State private var scalars: [Unicode.Scalar] = []
    @State private var query = ""
    @State private var section: GlyphSection?

    private let displayLimit = 600

    private var availableSections: [GlyphSection] {
        let present = Set(scalars.map { GlyphSection.section(for: $0.value) })
        return GlyphSection.allCases.filter { present.contains($0) }
    }

    private var filtered: [Unicode.Scalar] {
        var result = scalars
        if let section {
            result = result.filter { GlyphSection.section(for: $0.value) == section }
        }

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return Array(result.prefix(displayLimit)) }

        if let hex = Self.parseCodePoint(needle) {
            return result.filter { $0.value == hex }.prefix(displayLimit).map { $0 }
        }
        let lowered = needle.lowercased()
        return result.filter { scalar in
            String(scalar).lowercased().contains(lowered)
                || String(scalar.value, radix: 16).contains(lowered)
        }.prefix(displayLimit).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Glyphs")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("Character or code point", text: $query)
                    .textFieldStyle(.roundedBorder)

                Picker("Section", selection: $section) {
                    Text("All").tag(GlyphSection?.none)
                    ForEach(availableSections) { section in
                        Text(section.title).tag(Optional(section))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }

            if loaded == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if scalars.isEmpty {
                Text("This font reports no characters.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(scalars.count) characters\(scalars.count > displayLimit && query.isEmpty && section == nil ? ", showing first \(displayLimit)" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 6)],
                    spacing: 6
                ) {
                    ForEach(filtered, id: \.value) { scalar in
                        GlyphCell(
                            scalar: scalar,
                            baseFont: loaded?.ctFont,
                            unitsPerEm: face.unitsPerEm,
                            textColor: textColor
                        )
                    }
                }
            }
        }
        .task(id: face.id) {
            guard let font = await FontLoader.shared.font(
                path: face.path,
                faceIndex: face.index,
                postscriptName: face.postscriptName
            ) else { return }
            loaded = font
            scalars = Self.characters(in: font.ctFont)
        }
    }

    private static func characters(in font: CTFont) -> [Unicode.Scalar] {
        let characterSet = CTFontCopyCharacterSet(font)
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(256)
        for value in 0x20...0x2FFFF {
            guard CFCharacterSetIsLongCharacterMember(characterSet, UInt32(value)) else {
                continue
            }
            guard let scalar = Unicode.Scalar(UInt32(value)) else { continue }
            if scalar.properties.generalCategory == .control { continue }
            result.append(scalar)
        }
        return result
    }

    private static func parseCodePoint(_ value: String) -> UInt32? {
        var text = value.uppercased()
        if text.hasPrefix("U+") { text.removeFirst(2) }
        guard text.count >= 2, text.count <= 6,
              text.allSatisfy({ $0.isHexDigit }) else { return nil }
        return UInt32(text, radix: 16)
    }
}

private struct GlyphCell: View {
    let scalar: Unicode.Scalar
    let baseFont: CTFont?
    let unitsPerEm: Int
    let textColor: Color

    var body: some View {
        Canvas { context, size in
            guard let baseFont else { return }
            let font = PreviewLine.font(from: baseFont, size: 26)
            context.withCGContext { cg in
                PreviewLine.drawTruncated(
                    text: String(scalar),
                    font: font,
                    color: NSColor(textColor),
                    in: cg,
                    rect: CGRect(origin: .zero, size: size),
                    inset: 4
                )
            }
        }
        .frame(width: 44, height: 44)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
        .help(tooltip)
        .onTapGesture {
            copy(String(scalar))
        }
        .contextMenu {
            Button("Copy Character") { copy(String(scalar)) }
            Button("Copy Code Point") { copy(codePoint) }
            if let svg = svg {
                Button("Copy SVG") { copy(svg) }
            }
        }
    }

    private var codePoint: String {
        String(format: "U+%04X", scalar.value)
    }

    private var tooltip: String {
        "\(codePoint)  \(String(scalar))"
    }

    private var glyphID: CGGlyph? {
        guard let baseFont else { return nil }
        let utf16 = Array(String(scalar).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        guard CTFontGetGlyphsForCharacters(baseFont, utf16, &glyphs, utf16.count) else {
            return nil
        }
        return glyphs.first { $0 != 0 }
    }

    private var svg: String? {
        guard let baseFont, let glyphID, unitsPerEm > 0 else { return nil }
        let unitFont = PreviewLine.font(from: baseFont, size: CGFloat(unitsPerEm))
        guard let path = CTFontCreatePathForGlyph(unitFont, glyphID, nil) else { return nil }
        let data = GlyphSVG.pathData(path)
        guard !data.isEmpty else { return nil }
        let ascent = CTFontGetAscent(unitFont)
        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(unitsPerEm) \(unitsPerEm)">
          <g transform="translate(0, \(Int(ascent))) scale(1, -1)">
            <path d="\(data)" fill="currentColor"/>
          </g>
        </svg>
        """
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

enum GlyphSVG {
    static func pathData(_ path: CGPath) -> String {
        var parts: [String] = []
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                parts.append("M\(number(points[0].x)) \(number(points[0].y))")
            case .addLineToPoint:
                parts.append("L\(number(points[0].x)) \(number(points[0].y))")
            case .addQuadCurveToPoint:
                parts.append(
                    "Q\(number(points[0].x)) \(number(points[0].y)) "
                        + "\(number(points[1].x)) \(number(points[1].y))"
                )
            case .addCurveToPoint:
                parts.append(
                    "C\(number(points[0].x)) \(number(points[0].y)) "
                        + "\(number(points[1].x)) \(number(points[1].y)) "
                        + "\(number(points[2].x)) \(number(points[2].y))"
                )
            case .closeSubpath:
                parts.append("Z")
            @unknown default:
                break
            }
        }
        return parts.joined(separator: " ")
    }

    private static func number(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }
}
