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
}

/// A family is a contiguous range in the snapshot's sorted face array. No
/// copies, no nested arrays.
public struct CatalogFamily: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let faceRange: Range<Int>
    public let searchText: String
    public let hasVariableFace: Bool

    public var faceCount: Int { faceRange.count }
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
        let needle = Self.searchFold(query)
        guard !needle.isEmpty else { return Array(families.prefix(limit)) }
        var result: [CatalogFamily] = []
        result.reserveCapacity(min(limit, 64))
        for family in families where family.searchText.contains(needle) {
            result.append(family)
            if result.count == limit { break }
        }
        return result
    }

    // MARK: - Build

    static func build(faces input: [CatalogFace]) -> CatalogSnapshot {
        let faces = input.sorted { left, right in
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
                    families.append(makeFamily(faces: faces, range: start..<index))
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

    private static func makeFamily(faces: [CatalogFace], range: Range<Int>) -> CatalogFamily {
        let name = faces[range.lowerBound].family
        var parts: [String] = [searchFold(name)]
        parts.reserveCapacity(1 + range.count * 2)
        for face in faces[range] {
            parts.append(searchFold(face.style))
            parts.append(searchFold(face.postscriptName))
        }
        return CatalogFamily(
            id: faces[range.lowerBound].familyKey,
            name: name,
            faceRange: range,
            searchText: parts.joined(separator: "\u{1}"),
            hasVariableFace: faces[range].contains(where: \.isVariable)
        )
    }

    static func familyKey(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fold(_ value: String) -> String {
        value
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
