import Foundation

/// One face as the UI sees it. Everything is precomputed; views never touch
/// files or the database.
public struct CatalogFace: Sendable, Identifiable, Equatable {
    public let id: String
    public let fileID: String
    public let path: String
    public let fileStatus: String
    public let index: Int
    public let family: String
    public let familyKey: String
    public let style: String
    public let fullName: String
    public let postscriptName: String
    public let weightClass: Int
    public let widthClass: Int
    public let isItalic: Bool
    public let isVariable: Bool
    public let axes: [FontAxis]
    public let unitsPerEm: Int
    public let xHeight: Double?
    public let capHeight: Double?
    public let ascender: Double?
    public let descender: Double?
    public let vendorID: String?
    public let embedding: Int?
    public let scriptMask: UInt64
    /// Scripts whose complete sample text is covered by this face.
    public let previewMask: UInt64

    /// Identity of a visual style inside a family. OTF and TTF copies of the
    /// same style collapse to one key even when their PostScript names differ.
    public var styleKey: String {
        let styleName = style
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "normal", with: "regular")
        return "\(styleName)\u{1}\(weightClass)\u{1}\(widthClass)\u{1}\(isItalic ? 1 : 0)"
    }
}

/// Name-table values used by some web subsets instead of a real identity.
/// Fontshare exports, for example, write the literal `false` for ids 1, 4 and 6.
enum PlaceholderFontName {
    private static let values: Set<String> = [
        "false", "none", "null", "undefined", "untitled", "nil",
    ]

    static func isPlaceholder(_ name: String) -> Bool {
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.isEmpty || values.contains(lower)
    }
}

public enum FontLocation {
    /// Apple's own font folders. `/Library/Fonts` and `~/Library/Fonts` are
    /// user-installed and not treated as system fonts.
    public static func isSystemFont(path: String) -> Bool {
        path.hasPrefix("/System/Library/Fonts/")
    }
}

public enum FontKindFilter: String, Sendable, CaseIterable {
    case any
    case variable
    case staticFont = "static"
}

/// Facets that do not need a coverage index.
public struct CatalogFilter: Sendable, Equatable {
    public var kind: FontKindFilter = .any
    public var requiresItalic = false
    public var requiresBold = false
    public var script: FontScript?
    public var characters: String = ""

    public init() {}

    public var isActive: Bool {
        kind != .any
            || requiresItalic
            || requiresBold
            || script != nil
            || !characters.isEmpty
    }

    public var characterScalars: [UInt32] {
        characters.unicodeScalars.map(\.value)
    }
}

/// A family is a contiguous range in the snapshot's sorted face array. No
/// copies, no nested arrays.
public struct CatalogFamily: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let faceRange: Range<Int>
    /// Lowercased UTF-8 haystack for substring search. Bytes are much faster
    /// than grapheme-aware `String.contains` across thousands of families.
    public let searchBlob: Data
    public let hasVariableFace: Bool
    public let scriptMask: UInt64
    /// Scripts whose complete sample text is covered by the readable faces.
    public let previewMask: UInt64
    /// True when sibling files report the same PostScript name, so only one of
    /// them can be active at a time.
    public let hasDuplicatePostScriptNames: Bool
    /// Faces whose file is missing or unreadable. They remain in the snapshot
    /// so collections survive an offline volume.
    public let missingFaceCount: Int
    /// Distinct visual styles after collapsing alternate files. This is the
    /// number the family checkbox activates.
    public let styleCount: Int
    /// One preferred face per style group. Alternate files stay in the sheet
    /// but are not part of the family toggle.
    public let preferredFaceIDs: [String]

    public var faceCount: Int { faceRange.count }

    /// Display label for the family count. The number matches what the family
    /// checkbox activates, not how many files happen to exist.
    public var countLabel: String {
        var text = "\(styleCount) style\(styleCount == 1 ? "" : "s")"
        if missingFaceCount > 0 {
            text += " · \(missingFaceCount) missing"
        }
        return text
    }

    /// Script-aware preview, falling back to the user's sample.
    public func previewText(userText: String) -> String {
        FontScript.previewText(mask: previewMask, userText: userText)
    }
}

/// Immutable read model. Built from the database at launch, replaced whole on
/// every change. Sorting and folding happen once, here.
public struct CatalogSnapshot: Sendable {
    public let faces: [CatalogFace]
    public let families: [CatalogFamily]
    private let faceIndexByID: [String: Int]
    private let familyIndexByID: [String: Int]

    public static let empty = CatalogSnapshot.build(faces: [])

    public var faceCount: Int { faces.count }
    public var familyCount: Int { families.count }

    public func family(id: String) -> CatalogFamily? {
        guard let index = familyIndexByID[id] else { return nil }
        return families[index]
    }

    public func face(id: String) -> CatalogFace? {
        guard let index = faceIndexByID[id] else { return nil }
        return faces[index]
    }

    public func faces(in family: CatalogFamily) -> ArraySlice<CatalogFace> {
        faces[family.faceRange]
    }

    /// Substring search across family, styles and PostScript names.
    public func families(matching query: String, limit: Int = 200) -> [CatalogFamily] {
        families(matching: query, filter: CatalogFilter(), limit: limit)
    }

    public func families(
        matching query: String,
        filter: CatalogFilter,
        limit: Int = 200
    ) -> [CatalogFamily] {
        let needle = Data(Self.searchFold(query).utf8)
        var result: [CatalogFamily] = []
        result.reserveCapacity(min(limit, 64))
        for family in families {
            if !needle.isEmpty,
               family.searchBlob.range(of: needle) == nil {
                continue
            }
            guard matches(family, filter: filter) else { continue }
            result.append(family)
            if result.count == limit { break }
        }
        return result
    }

    /// Exact character presence, using ranges loaded from the coverage index.
    public func family(
        _ family: CatalogFamily,
        covers scalars: [UInt32],
        coverage: [String: CoverageRanges]
    ) -> Bool {
        guard !scalars.isEmpty else { return true }
        return faces(in: family).contains { face in
            coverage[face.id]?.containsAll(scalars) == true
        }
    }

    public func isSystemFamily(_ family: CatalogFamily) -> Bool {
        let faces = faces(in: family)
        return !faces.isEmpty && faces.allSatisfy {
            FontLocation.isSystemFont(path: $0.path)
        }
    }

    public func families(containingAny faceIDs: Set<String>) -> [CatalogFamily] {
        guard !faceIDs.isEmpty else { return [] }
        return families.filter { family in
            faces(in: family).contains { faceIDs.contains($0.id) }
        }
    }

    public func matches(_ family: CatalogFamily, filter: CatalogFilter) -> Bool {
        switch filter.kind {
        case .any:
            break
        case .variable:
            guard family.hasVariableFace else { return false }
        case .staticFont:
            guard !family.hasVariableFace else { return false }
        }

        if let script = filter.script,
           family.scriptMask & script.rawValue == 0 {
            return false
        }

        let faces = faces(in: family)
        if filter.requiresItalic, !faces.contains(where: \.isItalic) {
            return false
        }
        if filter.requiresBold, !faces.contains(where: { $0.weightClass >= 600 }) {
            return false
        }
        return true
    }

    // MARK: - Build

    static func build(faces input: [CatalogFace]) -> CatalogSnapshot {
        struct Meta {
            var name: String
            var sortKey: String
            var allSystem: Bool
        }

        // Web subsets sometimes carry "false" instead of a name-table identity.
        // They are not browsable faces and must not create duplicate groups.
        let input = input.filter {
            !PlaceholderFontName.isPlaceholder($0.postscriptName)
        }

        // Family display metadata decides both the visible name and sort order.
        // System fonts must sort by their dot-stripped name, not by the raw key.
        var meta: [String: Meta] = [:]
        meta.reserveCapacity(input.count / 4 + 1)
        var latinByFamily: [String: String] = [:]
        for face in input {
            let system = FontLocation.isSystemFont(path: face.path)
            if var existing = meta[face.familyKey] {
                existing.allSystem = existing.allSystem && system
                meta[face.familyKey] = existing
            } else {
                meta[face.familyKey] = Meta(
                    name: face.family,
                    sortKey: "",
                    allSystem: system
                )
            }
            if latinByFamily[face.familyKey] == nil {
                latinByFamily[face.familyKey] = latinLabel(for: face)
            }
        }
        for (key, var value) in meta {
            if value.allSystem, value.name.hasPrefix("."), value.name.count > 1 {
                value.name.removeFirst()
            }
            var sortBase = value.name
            if !isUselessName(value.name),
               !hasLatinLetters(value.name),
               let latin = latinByFamily[key],
               latin.caseInsensitiveCompare(value.name) != .orderedSame {
                value.name = "\(value.name) (\(latin))"
                sortBase = latin
            }
            value.sortKey = familyKey(sortBase)
            meta[key] = value
        }

        let faces = input.sorted { left, right in
            let leftMeta = meta[left.familyKey]
            let rightMeta = meta[right.familyKey]
            if leftMeta?.sortKey != rightMeta?.sortKey {
                return (leftMeta?.sortKey ?? "") < (rightMeta?.sortKey ?? "")
            }
            if left.familyKey != right.familyKey {
                return left.familyKey < right.familyKey
            }
            if left.weightClass != right.weightClass {
                return left.weightClass < right.weightClass
            }
            if left.isItalic != right.isItalic {
                return !left.isItalic
            }
            return left.style < right.style
        }

        var families: [CatalogFamily] = []
        var start = 0
        if !faces.isEmpty {
            families.reserveCapacity(faces.count / 4 + 1)
            for index in 1...faces.count {
                if index == faces.count || faces[index].familyKey != faces[start].familyKey {
                    let key = faces[start].familyKey
                    let displayName = meta[key]?.name ?? faces[start].family
                    families.append(makeFamily(
                        faces: faces,
                        range: start..<index,
                        displayName: displayName
                    ))
                    start = index
                }
            }
        }

        var faceIndexByID: [String: Int] = [:]
        faceIndexByID.reserveCapacity(faces.count)
        for (index, face) in faces.enumerated() {
            faceIndexByID[face.id] = index
        }
        var familyIndexByID: [String: Int] = [:]
        familyIndexByID.reserveCapacity(families.count)
        for (index, family) in families.enumerated() {
            familyIndexByID[family.id] = index
        }
        return CatalogSnapshot(
            faces: faces,
            families: families,
            faceIndexByID: faceIndexByID,
            familyIndexByID: familyIndexByID
        )
    }

    private static func makeFamily(
        faces: [CatalogFace],
        range: Range<Int>,
        displayName: String
    ) -> CatalogFamily {
        let name = displayName
        var parts: [String] = [searchFold(name)]
        parts.reserveCapacity(1 + range.count * 2)
        for face in faces[range] {
            parts.append(searchFold(face.style))
            parts.append(searchFold(face.postscriptName))
        }

        var groups: [String: [CatalogFace]] = [:]
        groups.reserveCapacity(range.count)
        for face in faces[range] {
            groups[face.styleKey, default: []].append(face)
        }
        var preferredFaceIDs: [String] = []
        preferredFaceIDs.reserveCapacity(groups.count)
        var seenStyles = Set<String>()
        for face in faces[range] where seenStyles.insert(face.styleKey).inserted {
            if let preferred = preferredFace(in: groups[face.styleKey] ?? [face]) {
                preferredFaceIDs.append(preferred.id)
            }
        }

        let familyFaces = Array(faces[range])
        let readable = familyFaces.filter { $0.fileStatus == "ok" }
        let scriptMask = readable.reduce(UInt64(0)) { $0 | $1.scriptMask }
        let previewMask = readable.reduce(UInt64(0)) { $0 | $1.previewMask }
        let postscriptNames = Set(
            readable.map { $0.postscriptName.lowercased() }
        )
        let missingCount = familyFaces.reduce(0) {
            $0 + ($1.fileStatus != "ok" && $1.fileStatus != "cloud" ? 1 : 0)
        }
        return CatalogFamily(
            id: faces[range.lowerBound].familyKey,
            name: name,
            faceRange: range,
            searchBlob: Data(parts.joined(separator: "\u{1}").utf8),
            hasVariableFace: readable.contains(where: \.isVariable),
            scriptMask: scriptMask,
            previewMask: previewMask,
            hasDuplicatePostScriptNames: postscriptNames.count < readable.count,
            missingFaceCount: missingCount,
            styleCount: groups.count,
            preferredFaceIDs: preferredFaceIDs
        )
    }

    /// One file per style. Prefer readable files, non-WEB paths, then outline
    /// formats, then a stable path order. The alternate files stay in the sheet.
    private static func preferredFace(in group: [CatalogFace]) -> CatalogFace? {
        group.sorted { left, right in
            if left.fileStatus != right.fileStatus {
                return left.fileStatus == "ok"
            }
            let leftWeb = left.path.lowercased().contains("/web/")
            let rightWeb = right.path.lowercased().contains("/web/")
            if leftWeb != rightWeb {
                return !leftWeb
            }
            let leftRank = outlineRank(left.path)
            let rightRank = outlineRank(right.path)
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return left.path.localizedStandardCompare(right.path) == .orderedAscending
        }.first
    }

    private static func outlineRank(_ path: String) -> Int {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "otf", "otc":
            return 0
        case "ttf":
            return 1
        case "ttc":
            return 2
        default:
            return 3
        }
    }

    /// A name with no letters or digits tells the user nothing and must not
    /// become a row label. Some trial fonts use "." plus DEL or other control
    /// characters, which render as a bare dot.
    static func hasLatinLetters(_ name: String) -> Bool {
        name.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F, 0x1E00...0x1EFF:
                return true
            default:
                return false
            }
        }
    }

    /// A Latin label for a non-Latin family: the PostScript family prefix, then
    /// the file name. Used only for display and sorting; the raw key is kept.
    private static func latinLabel(for face: CatalogFace) -> String? {
        let postscript = face.postscriptName
        if let dash = postscript.firstIndex(of: "-") {
            let prefix = String(postscript[..<dash])
            if hasLatinLetters(prefix), !prefix.isEmpty {
                return prefix
            }
        } else if hasLatinLetters(postscript), !hasLatinLetters(face.family) {
            return postscript
        }

        let stem = fileStem(face.path)
        if hasLatinLetters(stem), !isUselessName(stem) {
            return stem.replacingOccurrences(of: "_", with: " ")
        }
        return nil
    }

    public static func isUselessName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return !trimmed.unicodeScalars.contains {
            CharacterSet.alphanumerics.contains($0)
        }
    }

    public static func fileStem(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    static func familyKey(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Search folds run tens of thousands of times per snapshot. Lowercasing is
    /// several times cheaper than full diacritic folding and finds the same
    /// names in practice; accents still match through the family key, which is
    /// fully folded.
    static func searchFold(_ value: String) -> String {
        value.lowercased()
    }
}
