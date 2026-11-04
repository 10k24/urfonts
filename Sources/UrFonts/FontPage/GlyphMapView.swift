import AppKit
import CoreText
import SwiftUI
import UrFontsCore

/// Character map for one face. Built from the font's own cmap via CoreText, so
/// it works for inactive fonts without registering anything.
struct GlyphMapView: View {
    let face: CatalogFace
    let textColor: Color

    @State private var loaded: LoadedFont?
    @State private var scalars: [Unicode.Scalar] = []
    @State private var query = ""

    private let displayLimit = 600

    private var filtered: [Unicode.Scalar] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return Array(scalars.prefix(displayLimit)) }

        if let hex = Self.parseCodePoint(needle) {
            return scalars.filter { $0.value == hex }.prefix(displayLimit).map { $0 }
        }
        let lowered = needle.lowercased()
        return scalars.filter { scalar in
            String(scalar).lowercased().contains(lowered)
                || String(scalar.value, radix: 16).contains(lowered)
        }.prefix(displayLimit).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Glyphs")
                    .font(.headline)
                Spacer()
                TextField("Character or code point", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            if loaded == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if scalars.isEmpty {
                Text("This face reports no characters.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(scalars.count) characters\(scalars.count > displayLimit && query.isEmpty ? ", showing first \(displayLimit)" : "")")
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
                            textColor: textColor
                        )
                    }
                }
            }
        }
        .task(id: face.id) {
            guard let font = await FontLoader.shared.font(
                path: face.path,
                faceIndex: face.index
            ) else { return }
            loaded = font
            scalars = Self.characters(in: font.ctFont)
        }
    }

    private static func characters(in font: CTFont) -> [Unicode.Scalar] {
        let characterSet = CTFontCopyCharacterSet(font)
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(256)
        // BMP plus the supplementary planes worth showing.
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
        .help(String(format: "U+%04X ", scalar.value) + String(scalar))
        .onTapGesture {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(scalar), forType: .string)
        }
        .contextMenu {
            Button("Copy Character") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(scalar), forType: .string)
            }
            Button("Copy Code Point") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    String(format: "U+%04X", scalar.value),
                    forType: .string
                )
            }
        }
    }
}
