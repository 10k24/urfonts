import Foundation

public struct OpenTypeFeature: Sendable, Hashable, Identifiable {
    public let tag: String

    public var id: String { tag }
    public var name: String { Self.names[tag] ?? tag }

    public init(tag: String) {
        self.tag = tag
    }

    static let names: [String: String] = [
        "aalt": "Access All Alternates",
        "c2sc": "Caps to Small Caps",
        "calt": "Contextual Alternates",
        "case": "Case-Sensitive Forms",
        "ccmp": "Glyph Composition",
        "dlig": "Discretionary Ligatures",
        "dnom": "Denominators",
        "frac": "Fractions",
        "fwid": "Full Width",
        "hlig": "Historical Ligatures",
        "kern": "Kerning",
        "liga": "Standard Ligatures",
        "lnum": "Lining Figures",
        "mark": "Mark Positioning",
        "mkmk": "Mark to Mark",
        "numr": "Numerators",
        "onum": "Oldstyle Figures",
        "ordn": "Ordinals",
        "pnum": "Proportional Figures",
        "salt": "Stylistic Alternates",
        "sinf": "Scientific Inferiors",
        "smcp": "Small Caps",
        "subs": "Subscript",
        "sups": "Superscript",
        "tnum": "Tabular Figures",
        "zero": "Slashed Zero",
    ]

    /// One name for a list of tags, including stylistic sets.
    public static func displayName(for tag: String) -> String {
        if tag.hasPrefix("ss"), tag.count == 4,
           let number = Int(tag.dropFirst(2)) {
            return "Stylistic Set \(number)"
        }
        if tag.hasPrefix("cv"), tag.count == 4,
           let number = Int(tag.dropFirst(2)) {
            return "Character Variant \(number)"
        }
        return names[tag] ?? tag
    }
}

enum OpenTypeFeatureTable {
    /// The feature records in GSUB/GPOS: version, then Script, Feature and
    /// Lookup list offsets. Only the feature tags are needed here.
    static func tags(_ table: FontTable) throws -> [String] {
        let featureListOffset = Int(try table.u16(6))
        guard featureListOffset + 2 <= table.length else { return [] }
        let count = Int(try table.u16(featureListOffset))
        guard count > 0, count < 4096 else { return [] }

        var tags: [String] = []
        tags.reserveCapacity(count)
        for index in 0..<count {
            let record = featureListOffset + 2 + index * 6
            guard record + 6 <= table.length else { break }
            tags.append(try table.tag(record))
        }
        return tags
    }
}
