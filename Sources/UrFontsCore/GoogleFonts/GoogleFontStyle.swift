import Foundation

/// One Google Fonts style key. Variable families list many styles that map to
/// one TTF; static families usually map one style to one file.
public struct GoogleFontStyle: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let weight: Int
    public let isItalic: Bool

    public init(id: String, name: String, weight: Int, isItalic: Bool) {
        self.id = id
        self.name = name
        self.weight = weight
        self.isItalic = isItalic
    }

    /// CSS Family API descriptor for this style.
    public var cssDescriptor: String {
        "ital,wght@\(isItalic ? 1 : 0),\(weight)"
    }
}

public extension GoogleFontFamily {
    var styles: [GoogleFontStyle] {
        var seen = Set<String>()
        let parsed = variants.compactMap { GoogleFontStyle(variant: $0) }
            .filter { seen.insert($0.id).inserted }
        if !parsed.isEmpty {
            return parsed
        }
        let fallback = files.map { file -> GoogleFontStyle in
            let filename = (file.filename as NSString).deletingPathExtension
            let italic = filename.lowercased().contains("italic")
            return GoogleFontStyle(
                id: file.path,
                name: italic ? "Italic" : "Regular",
                weight: 400,
                isItalic: italic
            )
        }
        return fallback
    }

    /// The file that owns a style. Variable families have one Roman and one
    /// Italic file, so several styles share a file.
    func file(for style: GoogleFontStyle) -> GoogleFontFile? {
        guard !files.isEmpty else { return nil }
        let normalized = style.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        if let exact = files.first(where: {
            ($0.filename as NSString).deletingPathExtension
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
                .contains(normalized)
        }) {
            return exact
        }
        let italics = files.filter {
            ($0.filename as NSString).deletingPathExtension
                .lowercased()
                .contains("italic")
        }
        if style.isItalic, let italic = italics.first {
            return italic
        }
        if !style.isItalic, let upright = files.first(where: { !italics.contains($0) }) {
            return upright
        }
        return files.first
    }
}

private extension GoogleFontStyle {
    init?(variant: String) {
        let key = variant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }

        let digits = key.prefix { $0.isNumber }
        let weight: Int
        if !digits.isEmpty, let value = Int(digits) {
            weight = value
        } else if key.contains("bold") {
            weight = 700
        } else {
            weight = 400
        }
        let italic = key.contains("italic") || key.hasSuffix("i")

        let weightName: String
        switch weight {
        case 100: weightName = "Thin"
        case 200: weightName = "Extra Light"
        case 300: weightName = "Light"
        case 400: weightName = "Regular"
        case 500: weightName = "Medium"
        case 600: weightName = "Semi Bold"
        case 700: weightName = "Bold"
        case 800: weightName = "Extra Bold"
        case 900: weightName = "Black"
        default: weightName = "Regular"
        }
        let name: String
        if weight == 400, italic {
            name = "Italic"
        } else if weight == 400 {
            name = "Regular"
        } else {
            name = italic ? "\(weightName) Italic" : weightName
        }
        self.init(id: key, name: name, weight: weight, isItalic: italic)
    }
}
