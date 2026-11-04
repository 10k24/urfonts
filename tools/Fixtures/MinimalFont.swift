import Foundation

/// A structurally valid, tiny TrueType font.
///
/// Fixtures need 23,000 files with unique family, style and PostScript names,
/// and nothing else: no real glyphs are required to index or register a font.
/// Writing one valid font from scratch keeps the fixture library small
/// (about 800 bytes per file) and independent of any bundled font licence.
///
/// Glyph 0 is empty. Glyph 1 is a rectangle and is mapped to A-Z, so the font
/// has an outline for tools that insist on one.
public struct MinimalFontSpec: Sendable {
    public var family: String
    public var style: String
    public var postscriptName: String
    public var weightClass: UInt16
    public var isItalic: Bool
    public var isBold: Bool

    public init(
        family: String,
        style: String,
        postscriptName: String,
        weightClass: UInt16,
        isItalic: Bool,
        isBold: Bool
    ) {
        self.family = family
        self.style = style
        self.postscriptName = postscriptName
        self.weightClass = weightClass
        self.isItalic = isItalic
        self.isBold = isBold
    }

    /// Four styles per family keeps grouping tests meaningful without
    /// multiplying the file count.
    public static let styles: [(name: String, weight: UInt16, bold: Bool, italic: Bool)] = [
        ("Regular", 400, false, false),
        ("Bold", 700, true, false),
        ("Italic", 400, false, true),
        ("Bold Italic", 700, true, true),
    ]

    /// Family and style are derived from the index so a fixture library is
    /// reproduced identically on every machine.
    public init(index: Int) {
        let familyIndex = index / MinimalFontSpec.styles.count + 1
        let style = MinimalFontSpec.styles[index % MinimalFontSpec.styles.count]
        let family = String(format: "Fixture Family %05d", familyIndex)
        let postscriptStyle = style.name.replacingOccurrences(of: " ", with: "")
        self.init(
            family: family,
            style: style.name,
            postscriptName: "FixtureFamily\(String(format: "%05d", familyIndex))-\(postscriptStyle)",
            weightClass: style.weight,
            isItalic: style.italic,
            isBold: style.bold
        )
    }
}

public enum MinimalFont {
    public static func data(for spec: MinimalFontSpec) -> Data {
        var tables: [(tag: String, data: Data)] = [
            ("OS/2", os2Table(spec)),
            ("cmap", cmapTable()),
            ("glyf", glyfTable()),
            ("head", headTable(spec)),
            ("hhea", hheaTable()),
            ("hmtx", hmtxTable()),
            ("loca", locaTable()),
            ("maxp", maxpTable()),
            ("name", nameTable(spec)),
            ("post", postTable()),
        ]
        tables.sort { $0.tag < $1.tag }
        return assemble(tables: tables)
    }

    // MARK: - Tables

    private static func headTable(_ spec: MinimalFontSpec) -> Data {
        var d = Data()
        d.u32(0x0001_0000)          // version
        d.u32(0x0001_0000)          // fontRevision
        d.u32(0)                    // checkSumAdjustment, patched by assemble
        d.u32(0x5F0F_3CF5)          // magicNumber
        d.u16(0x000B)               // flags: baseline y=0, lsb x=0, integer ppem
        d.u16(1000)                 // unitsPerEm
        d.u64(0)                    // created
        d.u64(0)                    // modified
        d.i16(0)                    // xMin
        d.i16(0)                    // yMin
        d.i16(450)                  // xMax
        d.i16(700)                  // yMax
        var macStyle: UInt16 = 0
        if spec.isBold { macStyle |= 0x01 }
        if spec.isItalic { macStyle |= 0x02 }
        d.u16(macStyle)
        d.u16(8)                    // lowestRecPPEM
        d.i16(2)                    // fontDirectionHint
        d.i16(0)                    // indexToLocFormat: short
        d.i16(0)                    // glyphDataFormat
        return d
    }

    private static func hheaTable() -> Data {
        var d = Data()
        d.u32(0x0001_0000)          // version
        d.i16(800)                  // ascender
        d.i16(-200)                 // descender
        d.i16(0)                    // lineGap
        d.u16(500)                  // advanceWidthMax
        d.i16(0)                    // minLeftSideBearing
        d.i16(0)                    // minRightSideBearing
        d.i16(450)                  // xMaxExtent
        d.i16(1)                    // caretSlopeRise
        d.i16(0)                    // caretSlopeRun
        d.i16(0)                    // caretOffset
        d.i16(0)                    // reserved
        d.i16(0)
        d.i16(0)
        d.i16(0)
        d.i16(0)                    // metricDataFormat
        d.u16(4)                    // numberOfHMetrics
        return d
    }

    private static func maxpTable() -> Data {
        var d = Data()
        d.u32(0x0001_0000)          // version 1.0
        d.u16(4)                    // numGlyphs
        d.u16(4)                    // maxPoints
        d.u16(1)                    // maxContours
        d.u16(0)                    // maxCompositePoints
        d.u16(0)                    // maxCompositeContours
        d.u16(2)                    // maxZones
        d.u16(0)                    // maxTwilightPoints
        d.u16(0)                    // maxStorage
        d.u16(0)                    // maxFunctionDefs
        d.u16(0)                    // maxInstructionDefs
        d.u16(0)                    // maxStackElements
        d.u16(0)                    // maxSizeOfInstructions
        d.u16(0)                    // maxComponentElements
        d.u16(0)                    // maxComponentDepth
        return d
    }

    private static func hmtxTable() -> Data {
        var d = Data()
        for leftSideBearing in [Int16(0), 50, 0, 0] {
            d.u16(500)
            d.i16(leftSideBearing)
        }
        return d
    }

    private static func cmapTable() -> Data {
        // Format 4, two segments: A-Z map to glyph 1, 0xFFFF maps to glyph 0.
        let segCount: UInt16 = 2
        let subtableLength: UInt16 = 32
        var sub = Data()
        sub.u16(4)                  // format
        sub.u16(subtableLength)
        sub.u16(0)                  // language
        sub.u16(segCount * 2)
        sub.u16(4)                  // searchRange
        sub.u16(1)                  // entrySelector
        sub.u16(0)                  // rangeShift
        sub.u16(0x005A)             // endCode
        sub.u16(0xFFFF)
        sub.u16(0)                  // reservedPad
        sub.u16(0x0041)             // startCode
        sub.u16(0xFFFF)
        sub.i16(-64)                // idDelta: 0x41 + (-64) = 1
        sub.i16(1)                  // 0xFFFF + 1 = 0
        sub.u16(0)                  // idRangeOffset
        sub.u16(0)

        var d = Data()
        d.u16(0)                    // version
        d.u16(1)                    // numTables
        d.u16(3)                    // platform: Windows
        d.u16(1)                    // encoding: Unicode BMP
        d.u32(12)                   // offset to subtable
        d.append(sub)
        return d
    }

    private static func glyfTable() -> Data {
        var d = Data()
        d.i16(1)                    // numberOfContours
        d.i16(50)                   // xMin
        d.i16(0)                    // yMin
        d.i16(450)                  // xMax
        d.i16(700)                  // yMax
        d.u16(3)                    // endPtsOfContours
        d.u16(0)                    // instructionLength
        d.append(contentsOf: [0x01, 0x01, 0x01, 0x01] as [UInt8])
        for x in [Int16(50), 400, 0, -400] { d.i16(x) }
        for y in [Int16(0), 0, 700, 0] { d.i16(y) }
        return d
    }

    private static func locaTable() -> Data {
        var d = Data()
        // Short offsets, divided by two. Glyph 0 is empty, glyph 1 is 34 bytes.
        for offset in [0, 0, 17, 17, 17] {
            d.u16(UInt16(offset))
        }
        return d
    }

    private static func os2Table(_ spec: MinimalFontSpec) -> Data {
        var selection: UInt16 = 0
        if spec.isItalic { selection |= 0x01 }
        if spec.isBold { selection |= 0x20 }
        if selection == 0 { selection = 0x40 }

        var d = Data()
        d.u16(4)                    // version
        d.i16(500)                  // xAvgCharWidth
        d.u16(spec.weightClass)
        d.u16(5)                    // usWidthClass: medium
        d.u16(0)                    // fsType: installable embedding
        for _ in 0..<10 { d.i16(0) }
        d.i16(0)                    // sFamilyClass
        d.append(Data(repeating: 0, count: 10)) // PANOSE
        for _ in 0..<4 { d.u32(0) }
        d.tag("URFT")
        d.u16(selection)
        d.u16(0x0041)               // usFirstCharIndex
        d.u16(0x005A)               // usLastCharIndex
        d.i16(800)                  // sTypoAscender
        d.i16(-200)                 // sTypoDescender
        d.i16(0)                    // sTypoLineGap
        d.u16(800)                  // usWinAscent
        d.u16(200)                  // usWinDescent
        d.u32(0)                    // ulCodePageRange1
        d.u32(0)                    // ulCodePageRange2
        d.i16(500)                  // sxHeight
        d.i16(700)                  // sCapHeight
        d.u16(0)                    // usDefaultChar
        d.u16(32)                   // usBreakChar
        d.u16(0)                    // usMaxContext
        return d
    }

    private static func postTable() -> Data {
        var d = Data()
        d.u32(0x0003_0000)          // version 3.0
        d.u32(0)                    // italicAngle
        d.i16(-100)                 // underlinePosition
        d.i16(50)                   // underlineThickness
        d.u32(0)                    // isFixedPitch
        d.u32(0)                    // minMemType42
        d.u32(0)                    // maxMemType42
        d.u32(0)                    // minMemType1
        d.u32(0)                    // maxMemType1
        return d
    }

    private static func nameTable(_ spec: MinimalFontSpec) -> Data {
        let entries: [(UInt16, String)] = [
            (1, spec.family),
            (2, spec.style),
            (3, "\(spec.family) \(spec.style) 1.000;URFT"),
            (4, "\(spec.family) \(spec.style)"),
            (6, spec.postscriptName),
            (16, spec.family),
            (17, spec.style),
        ]
        var strings = Data()
        var records = Data()
        for (nameID, value) in entries {
            let encoded = utf16BE(value)
            records.u16(3)              // platform: Windows
            records.u16(1)              // encoding: Unicode BMP
            records.u16(0x0409)         // language: US English
            records.u16(nameID)
            records.u16(UInt16(encoded.count))
            records.u16(UInt16(strings.count))
            strings.append(encoded)
        }

        var d = Data()
        d.u16(0)                        // format 0
        d.u16(UInt16(entries.count))
        d.u16(UInt16(6 + records.count)) // stringOffset
        d.append(records)
        d.append(strings)
        return d
    }

    // MARK: - Assembly

    private static func assemble(tables: [(tag: String, data: Data)]) -> Data {
        let padded: [(tag: String, data: Data, checksum: UInt32)] = tables.map { entry in
            var data = entry.data
            while data.count % 4 != 0 { data.append(0) }
            return (entry.tag, data, checksum(data))
        }

        let numTables = UInt16(padded.count)
        var entrySelector: UInt16 = 0
        while (UInt32(1) << (entrySelector + 1)) <= UInt32(numTables) {
            entrySelector += 1
        }
        let searchRange = 16 * (UInt32(1) << entrySelector)
        let rangeShift = UInt32(numTables) * 16 - searchRange

        var font = Data()
        font.u32(0x0001_0000)           // sfntVersion: TrueType outlines
        font.u16(numTables)
        font.u16(UInt16(searchRange))
        font.u16(entrySelector)
        font.u16(UInt16(rangeShift))

        var offset = UInt32(12 + 16 * Int(numTables))
        var headOffset: UInt32?
        for entry in padded {
            font.tag(entry.tag)
            font.u32(entry.checksum)
            font.u32(offset)
            font.u32(UInt32(entry.data.count))
            if entry.tag == "head" { headOffset = offset }
            offset += UInt32(entry.data.count)
        }

        for entry in padded {
            font.append(entry.data)
        }

        if let headOffset {
            let adjustment = 0xB1B0_AFBA &- checksum(font)
            let start = Int(headOffset) + 8
            font.replaceSubrange(start..<(start + 4), with: bytes(of: adjustment))
        }
        return font
    }

    private static func checksum(_ data: Data) -> UInt32 {
        var sum: UInt32 = 0
        var index = data.startIndex
        while index < data.endIndex {
            var word: UInt32 = 0
            for _ in 0..<4 {
                word <<= 8
                if index < data.endIndex {
                    word |= UInt32(data[index])
                    index = data.index(after: index)
                }
            }
            sum = sum &+ word
        }
        return sum
    }

    private static func bytes(of value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }

    private static func utf16BE(_ value: String) -> Data {
        var data = Data()
        for unit in value.utf16 {
            data.append(UInt8(unit >> 8))
            data.append(UInt8(unit & 0xFF))
        }
        return data
    }
}

extension Data {
    mutating func u16(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func i16(_ value: Int16) {
        u16(UInt16(bitPattern: value))
    }

    mutating func u32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func u64(_ value: UInt64) {
        u32(UInt32((value >> 32) & 0xFFFF_FFFF))
        u32(UInt32(value & 0xFFFF_FFFF))
    }

    mutating func tag(_ value: String) {
        precondition(value.utf8.count == 4, "table tags are four bytes")
        append(contentsOf: Array(value.utf8))
    }
}
