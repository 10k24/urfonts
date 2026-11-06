import Foundation

public struct FontAxis: Sendable, Equatable, Codable {
    public let tag: String
    public let minimum: Double
    public let defaultValue: Double
    public let maximum: Double
    public let name: String

    public init(
        tag: String,
        minimum: Double,
        defaultValue: Double,
        maximum: Double,
        name: String
    ) {
        self.tag = tag
        self.minimum = minimum
        self.defaultValue = defaultValue
        self.maximum = maximum
        self.name = name
    }
}

/// One face as stored in the library.
///
/// Metrics are normalized by units per em so filters can compare fonts with
/// different design sizes. Raw font units stay out of the catalog.
public struct ParsedFace: Sendable, Equatable {
    public let index: Int
    public let family: String
    public let style: String
    public let fullName: String
    public let postscriptName: String
    public let weightClass: Int
    public let widthClass: Int
    public let isItalic: Bool
    public let isBold: Bool
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

/// Reads names, axes and metrics straight from the file. No CoreText, no
/// registration, no per-face font instantiation.
public enum FontFileParser {
    /// Bump when parsing output changes so the scanner re-reads every file.
    public static let version = 1

    public static func parse(url: URL) throws -> [ParsedFace] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try parse(data: data)
    }

    /// Script coverage per face index, from the `cmap` table only. Reads the
    /// file once; used by the background coverage indexer.
    public static func coverage(url: URL) throws -> [Int: ScriptCoverage] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let offsets = try faceOffsets(in: data)
        var result: [Int: ScriptCoverage] = [:]
        result.reserveCapacity(offsets.count)
        let empty = CoverageRanges(ranges: [])
        for (index, offset) in offsets.enumerated() {
            guard let tables = try? FontTables(data: data, directoryOffset: offset),
                  let cmap = tables.table("cmap"),
                  let coverage = try? CmapCoverage.coverage(cmap) else {
                result[index] = ScriptCoverage(mask: 0, ranges: empty)
                continue
            }
            result[index] = coverage
        }
        return result
    }

    public static func scriptMasks(url: URL) throws -> [Int: UInt64] {
        try coverage(url: url).mapValues(\.mask)
    }

    /// GSUB and GPOS feature tags for one face, sorted and de-duplicated.
    public static func featureTags(url: URL, faceIndex: Int = 0) throws -> [OpenTypeFeature] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let offsets = try faceOffsets(in: data)
        guard faceIndex >= 0, faceIndex < offsets.count,
              let tables = try? FontTables(data: data, directoryOffset: offsets[faceIndex])
        else {
            return []
        }

        var tags = Set<String>()
        for name in ["GSUB", "GPOS"] {
            guard let table = tables.table(name),
                  let found = try? OpenTypeFeatureTable.tags(table) else {
                continue
            }
            tags.formUnion(found)
        }
        return tags.sorted().map(OpenTypeFeature.init(tag:))
    }

    public static func parse(data: Data) throws -> [ParsedFace] {
        let offsets = try faceOffsets(in: data)
        var faces: [ParsedFace] = []
        faces.reserveCapacity(offsets.count)
        for (index, offset) in offsets.enumerated() {
            if let face = try? parseFace(data: data, directoryOffset: offset, index: index) {
                faces.append(face)
            }
        }
        guard !faces.isEmpty else { throw FontParseError.notAFont }
        return faces
    }

    // MARK: - Internals

    private static func faceOffsets(in data: Data) throws -> [Int] {
        let reader = ByteReader(data: data)
        let signature = try reader.u32(0)
        let collection = 0x7474_6366  // ttcf
        guard signature == collection else { return [0] }

        let numFonts = Int(try reader.u32(8))
        guard numFonts > 0, numFonts < 4096 else { throw FontParseError.malformed }
        var offsets: [Int] = []
        offsets.reserveCapacity(numFonts)
        for index in 0..<numFonts {
            let offset = Int(try reader.u32(12 + index * 4))
            guard offset >= 0, offset < data.count else { continue }
            offsets.append(offset)
        }
        guard !offsets.isEmpty else { throw FontParseError.malformed }
        return offsets
    }

    private static func parseFace(
        data: Data,
        directoryOffset: Int,
        index: Int
    ) throws -> ParsedFace {
        let tables = try FontTables(data: data, directoryOffset: directoryOffset)
        guard let headTable = tables.table("head") else { throw FontParseError.malformed }
        let head = try HeadTable.parse(headTable)

        let names = (try? tables.table("name").map(NameTable.parse)) ?? nil
        let os2 = try tables.table("OS/2").map(OS2Table.parse)
        let hhea = try tables.table("hhea").map(HheaTable.parse)
        let fvar = try tables.table("fvar").map(FvarTable.parse)

        let family = name(names, 16) ?? name(names, 1) ?? "Unknown"
        let style = name(names, 17) ?? name(names, 2) ?? "Regular"
        let fullName = name(names, 4) ?? "\(family) \(style)"
        let postscriptName = name(names, 6) ?? sanitizePostScript("\(family)-\(style)")

        let macStyle = head.macStyle
        let isItalic = (os2?.isItalic ?? false) || (macStyle & 0x02) != 0
        let isBold = (os2?.isBold ?? false) || (macStyle & 0x01) != 0

        let axes = (fvar?.axes ?? []).map { axis in
            FontAxis(
                tag: axis.tag,
                minimum: axis.minimum,
                defaultValue: axis.defaultValue,
                maximum: axis.maximum,
                name: name(names, axis.nameID) ?? axis.tag
            )
        }

        let upem = head.unitsPerEm
        let xHeight = ratio(os2?.xHeight, upem)
        let capHeight = ratio(os2?.capHeight, upem)
        let ascender = ratio(hhea?.ascender, upem)
        let descender = ratio(hhea?.descender, upem)

        return ParsedFace(
            index: index,
            family: family,
            style: style,
            fullName: fullName,
            postscriptName: postscriptName,
            weightClass: Int(os2?.weightClass ?? (isBold ? 700 : 400)),
            widthClass: Int(os2?.widthClass ?? 5),
            isItalic: isItalic,
            isBold: isBold,
            isVariable: !axes.isEmpty,
            axes: axes,
            unitsPerEm: upem,
            xHeight: xHeight,
            capHeight: capHeight,
            ascender: ascender,
            descender: descender,
            vendorID: os2?.vendorID,
            embedding: os2.map { Int($0.embedding) }
        )
    }

    private static func name(_ names: NameTable?, _ nameID: UInt16) -> String? {
        guard let value = names?[nameID], !value.isEmpty else { return nil }
        return value
    }

    private static func ratio(_ value: Int16?, _ upem: Int) -> Double? {
        guard let value, upem > 0 else { return nil }
        let ratio = Double(value) / Double(upem)
        guard ratio > -2, ratio < 3 else { return nil }
        return ratio
    }

    private static func sanitizePostScript(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_. ")
        let cleaned = String(value.unicodeScalars.filter { allowed.contains($0) })
            .replacingOccurrences(of: " ", with: "-")
        return String(cleaned.prefix(63))
    }
}
