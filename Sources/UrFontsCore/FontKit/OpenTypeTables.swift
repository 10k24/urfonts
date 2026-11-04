import Foundation

// Readers for the tables the library needs. Every optional means "the font did
// not provide it"; callers apply fallbacks, never crash paths.

struct NameTable {
    private var values: [UInt16: String]

    subscript(nameID: UInt16) -> String? {
        values[nameID]
    }

    static func parse(_ table: FontTable) throws -> NameTable {
        let format = try table.u16(0)
        guard format == 0 || format == 1 else { throw FontParseError.malformed }
        let count = Int(try table.u16(2))
        let stringOffset = Int(try table.u16(4))
        guard count >= 0, count < 4096 else { throw FontParseError.malformed }

        var best: [UInt16: (score: Int, value: String)] = [:]
        for index in 0..<count {
            let record = 6 + index * 12
            let platform = Int(try table.u16(record))
            let encoding = Int(try table.u16(record + 2))
            let language = Int(try table.u16(record + 4))
            let nameID = try table.u16(record + 6)
            let length = Int(try table.u16(record + 8))
            let offset = Int(try table.u16(record + 10))

            guard let decoded = decode(
                table: table,
                stringOffset: stringOffset,
                offset: offset,
                length: length,
                platform: platform,
                encoding: encoding
            ), !decoded.isEmpty else { continue }

            let score = preference(platform: platform, encoding: encoding, language: language)
            if let existing = best[nameID], existing.score <= score { continue }
            best[nameID] = (score, decoded)
        }

        return NameTable(values: best.mapValues(\.value))
    }

    private static func preference(platform: Int, encoding: Int, language: Int) -> Int {
        if platform == 3, encoding == 1, language == 0x0409 { return 0 }
        if platform == 3, encoding == 1 { return 1 }
        if platform == 3, encoding == 10 { return 2 }
        if platform == 0 { return 3 }
        if platform == 1, encoding == 0 { return 4 }
        return 5
    }

    private static func decode(
        table: FontTable,
        stringOffset: Int,
        offset: Int,
        length: Int,
        platform: Int,
        encoding: Int
    ) -> String? {
        guard length > 0, length < 64 * 1024 else { return nil }
        guard let data = try? table.data(stringOffset + offset, length: length) else { return nil }

        switch (platform, encoding) {
        case (3, 1), (0, _):
            return String(data: data, encoding: .utf16BigEndian)
        case (3, 10):
            return String(data: data, encoding: .utf32BigEndian)
        case (1, 0):
            return String(data: data, encoding: .macOSRoman)
        default:
            return String(data: data, encoding: .utf16BigEndian)
        }
    }
}

struct HeadTable {
    let unitsPerEm: Int
    let macStyle: UInt16
    let xMin: Int16
    let yMin: Int16
    let xMax: Int16
    let yMax: Int16

    static func parse(_ table: FontTable) throws -> HeadTable {
        let unitsPerEm = Int(try table.u16(18))
        guard unitsPerEm > 0 else { throw FontParseError.malformed }
        return HeadTable(
            unitsPerEm: unitsPerEm,
            macStyle: try table.u16(44),
            xMin: try table.i16(36),
            yMin: try table.i16(38),
            xMax: try table.i16(40),
            yMax: try table.i16(42)
        )
    }
}

struct HheaTable {
    let ascender: Int16
    let descender: Int16
    let lineGap: Int16
    let numberOfHMetrics: UInt16

    static func parse(_ table: FontTable) throws -> HheaTable {
        HheaTable(
            ascender: try table.i16(4),
            descender: try table.i16(6),
            lineGap: try table.i16(8),
            numberOfHMetrics: try table.u16(34)
        )
    }
}

struct OS2Table {
    let version: UInt16
    let weightClass: UInt16
    let widthClass: UInt16
    let embedding: UInt16
    let selection: UInt16
    let vendorID: String?
    let xHeight: Int16?
    let capHeight: Int16?
    let typoAscender: Int16?
    let typoDescender: Int16?

    var isItalic: Bool { selection & 0x01 != 0 }
    var isBold: Bool { selection & 0x20 != 0 }

    static func parse(_ table: FontTable) throws -> OS2Table {
        let version = try table.u16(0)
        let length = table.length

        var xHeight: Int16?
        var capHeight: Int16?
        if version >= 2, length >= 96 {
            xHeight = try table.i16(86)
            capHeight = try table.i16(88)
        }

        var vendorID: String?
        if length >= 62 {
            let bytes = try table.data(58, length: 4)
            let value = String(bytes: bytes, encoding: .ascii)?
                .trimmingCharacters(in: .whitespaces)
            if let value, !value.isEmpty { vendorID = value }
        }

        return OS2Table(
            version: version,
            weightClass: try table.u16(4),
            widthClass: try table.u16(6),
            embedding: try table.u16(8),
            selection: try table.u16(62),
            vendorID: vendorID,
            xHeight: xHeight,
            capHeight: capHeight,
            typoAscender: length >= 74 ? try table.i16(68) : nil,
            typoDescender: length >= 74 ? try table.i16(70) : nil
        )
    }
}

struct VariableAxis {
    let tag: String
    let minimum: Double
    let defaultValue: Double
    let maximum: Double
    let nameID: UInt16
}

struct FvarTable {
    let axes: [VariableAxis]

    static func parse(_ table: FontTable) throws -> FvarTable {
        let axisOffset = Int(try table.u16(4))
        let axisCount = Int(try table.u16(8))
        let axisSize = Int(try table.u16(10))
        guard axisCount >= 0, axisCount < 512, axisSize >= 20 else {
            return FvarTable(axes: [])
        }

        var axes: [VariableAxis] = []
        axes.reserveCapacity(axisCount)
        for index in 0..<axisCount {
            let record = axisOffset + index * axisSize
            let tag = try table.tag(record)
            let minimum = try fixed(table, record + 4)
            let defaultValue = try fixed(table, record + 8)
            let maximum = try fixed(table, record + 12)
            let nameID = try table.u16(record + 18)
            axes.append(VariableAxis(
                tag: tag,
                minimum: minimum,
                defaultValue: defaultValue,
                maximum: maximum,
                nameID: nameID
            ))
        }
        return FvarTable(axes: axes)
    }

    private static func fixed(_ table: FontTable, _ offset: Int) throws -> Double {
        Double(try table.i32(offset)) / 65_536.0
    }
}
