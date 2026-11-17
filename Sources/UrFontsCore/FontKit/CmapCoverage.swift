import Foundation

/// Scripts the preview and filters care about. A font can carry several.
public enum FontScript: UInt64, CaseIterable, Sendable {
    case latin = 0x0001
    case greek = 0x0002
    case cyrillic = 0x0004
    case arabic = 0x0008
    case hebrew = 0x0010
    case devanagari = 0x0020
    case thai = 0x0040
    case cjk = 0x0080
    case hiragana = 0x0100
    case katakana = 0x0200
    case hangul = 0x0400

    public var displayName: String {
        switch self {
        case .latin: "Latin"
        case .greek: "Greek"
        case .cyrillic: "Cyrillic"
        case .arabic: "Arabic"
        case .hebrew: "Hebrew"
        case .devanagari: "Devanagari"
        case .thai: "Thai"
        case .cjk: "CJK"
        case .hiragana: "Hiragana"
        case .katakana: "Katakana"
        case .hangul: "Hangul"
        }
    }

    public var sampleText: String {
        switch self {
        case .latin: "Hamburgerfontsiv"
        case .greek: "Καλημέρα κόσμε"
        case .cyrillic: "Съешь ещё этих мягких булок"
        case .arabic: "أبجد هوز حطي كلمن"
        case .hebrew: "אבגדהוזחטיכלמנסעפצקרשת"
        case .devanagari: "नमस्ते दुनिया"
        case .thai: "สวัสดีชาวโลก"
        case .cjk: "永字体设计"
        case .hiragana: "あいうえお かきくけこ"
        case .katakana: "アイウエオ カキクケコ"
        case .hangul: "다람쥐 헌 쳇바퀴에 타고파"
        }
    }

    /// A CJK font with Latin coverage should still preview CJK. Latin-only and
    /// Latin+Greek/Cyrillic fonts keep the user's sample.
    static let distinctive: [FontScript] = [
        .cjk, .hangul, .hiragana, .katakana,
        .arabic, .hebrew, .devanagari, .thai,
    ]

    public static func preferredSample(in mask: UInt64) -> FontScript? {
        for script in distinctive where mask & script.rawValue != 0 {
            return script
        }
        if mask & FontScript.latin.rawValue == 0 {
            for script in FontScript.allCases where mask & script.rawValue != 0 {
                return script
            }
        }
        return nil
    }

    /// Preview text for a family: script-specific when the family has a
    /// distinctive script, otherwise the user's sample.
    public static func previewText(mask: UInt64, userText: String) -> String {
        preferredSample(in: mask)?.sampleText ?? userText
    }

    /// Scripts whose complete sample is covered by `ranges`. Partial script
    /// coverage must not select a sample: CoreText would fill the gaps with a
    /// fallback font.
    public static func previewMask(for ranges: CoverageRanges) -> UInt64 {
        var mask: UInt64 = 0
        for script in allCases {
            let scalars = script.sampleText.unicodeScalars.map(\.value)
            if ranges.containsAll(scalars) {
                mask |= script.rawValue
            }
        }
        return mask
    }
}

/// Codepoint ranges a face covers, sorted and merged.
///
/// Stored as big-endian UInt32 pairs so a scan can decode without JSON.
public struct CoverageRanges: Sendable, Equatable {
    private let pairs: [UInt32]

    public init(ranges: [ClosedRange<UInt32>]) {
        var merged: [ClosedRange<UInt32>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last,
               range.lowerBound <= last.upperBound &+ 1 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        var values: [UInt32] = []
        values.reserveCapacity(merged.count * 2)
        for range in merged {
            values.append(range.lowerBound)
            values.append(range.upperBound)
        }
        pairs = values
    }

    public init?(data: Data) {
        guard data.count % 4 == 0, !data.isEmpty else { return nil }
        var values: [UInt32] = []
        values.reserveCapacity(data.count / 4)
        var index = data.startIndex
        while index < data.endIndex {
            let end = data.index(index, offsetBy: 4)
            let value = data[index..<end].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            values.append(value)
            index = end
        }
        pairs = values
    }

    public var data: Data {
        var data = Data(capacity: pairs.count * 4)
        for value in pairs {
            data.append(UInt8((value >> 24) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))
        }
        return data
    }

    public var isEmpty: Bool { pairs.isEmpty }

    public func contains(_ scalar: UInt32) -> Bool {
        var low = 0
        var high = pairs.count / 2 - 1
        while low <= high {
            let middle = (low + high) / 2
            let lower = pairs[middle * 2]
            let upper = pairs[middle * 2 + 1]
            if scalar < lower {
                high = middle - 1
            } else if scalar > upper {
                low = middle + 1
            } else {
                return true
            }
        }
        return false
    }

    public func containsAll(_ scalars: [UInt32]) -> Bool {
        scalars.allSatisfy(contains)
    }
}

/// Result of reading a face's `cmap`: a coarse script mask plus exact ranges.
public struct ScriptCoverage: Sendable, Equatable {
    public let mask: UInt64
    public let ranges: CoverageRanges

    public init(mask: UInt64, ranges: CoverageRanges) {
        self.mask = mask
        self.ranges = ranges
    }

    public var previewMask: UInt64 {
        FontScript.previewMask(for: ranges)
    }
}

/// Reads just enough of `cmap` to know which scripts and codepoints a face
/// covers.
///
/// Segment and group ranges are treated as coverage. A format 4 segment that
/// maps to .notdef through `idRangeOffset` can therefore over-report; that is
/// acceptable for coarse filters and documented rather than silently assumed.
public enum CmapCoverage {
    struct ScriptRange {
        let script: FontScript
        let lower: UInt32
        let upper: UInt32
    }

    static let ranges: [ScriptRange] = [
        ScriptRange(script: .latin, lower: 0x0041, upper: 0x005A),
        ScriptRange(script: .latin, lower: 0x0061, upper: 0x007A),
        ScriptRange(script: .latin, lower: 0x00C0, upper: 0x024F),
        ScriptRange(script: .latin, lower: 0x1E00, upper: 0x1EFF),
        ScriptRange(script: .greek, lower: 0x0370, upper: 0x03FF),
        ScriptRange(script: .greek, lower: 0x1F00, upper: 0x1FFF),
        ScriptRange(script: .cyrillic, lower: 0x0400, upper: 0x052F),
        ScriptRange(script: .hebrew, lower: 0x0590, upper: 0x05FF),
        ScriptRange(script: .arabic, lower: 0x0600, upper: 0x06FF),
        ScriptRange(script: .arabic, lower: 0x0750, upper: 0x077F),
        ScriptRange(script: .devanagari, lower: 0x0900, upper: 0x097F),
        ScriptRange(script: .thai, lower: 0x0E00, upper: 0x0E7F),
        ScriptRange(script: .hiragana, lower: 0x3040, upper: 0x309F),
        ScriptRange(script: .katakana, lower: 0x30A0, upper: 0x30FF),
        ScriptRange(script: .hangul, lower: 0xAC00, upper: 0xD7AF),
        ScriptRange(script: .hangul, lower: 0x1100, upper: 0x11FF),
        ScriptRange(script: .cjk, lower: 0x3400, upper: 0x4DBF),
        ScriptRange(script: .cjk, lower: 0x4E00, upper: 0x9FFF),
        ScriptRange(script: .cjk, lower: 0x20000, upper: 0x3FFFF),
    ]

    static func classify(lower: UInt32, upper: UInt32) -> UInt64 {
        var mask: UInt64 = 0
        for range in ranges where range.upper >= lower && range.lower <= upper {
            mask |= range.script.rawValue
        }
        return mask
    }

    static func coverage(_ table: FontTable) throws -> ScriptCoverage {
        let count = Int(try table.u16(2))
        guard count > 0, count < 256 else {
            return ScriptCoverage(mask: 0, ranges: CoverageRanges(ranges: []))
        }

        struct Candidate {
            let format: Int
            let offset: Int
            let score: Int
        }
        var candidates: [Candidate] = []
        for index in 0..<count {
            let record = 4 + index * 8
            let platform = Int(try table.u16(record))
            let encoding = Int(try table.u16(record + 2))
            let offset = Int(try table.u32(record + 4))
            guard offset >= 0, offset + 2 <= table.length else { continue }
            let format = Int(try table.u16(offset))
            let score: Int
            switch (platform, encoding, format) {
            case (3, 10, 12), (0, 4, 12), (0, 6, 12): score = 0
            case (3, 1, 4), (0, 3, 4): score = 1
            case (_, _, 12): score = 2
            case (_, _, 4): score = 3
            default: continue
            }
            candidates.append(Candidate(format: format, offset: offset, score: score))
        }
        guard let best = candidates.min(by: { $0.score < $1.score }) else {
            return ScriptCoverage(mask: 0, ranges: CoverageRanges(ranges: []))
        }

        let codepointRanges: [ClosedRange<UInt32>]
        switch best.format {
        case 12:
            codepointRanges = try format12Ranges(table, offset: best.offset)
        case 4:
            codepointRanges = try format4Ranges(table, offset: best.offset)
        default:
            codepointRanges = []
        }

        var mask: UInt64 = 0
        for range in codepointRanges {
            mask |= classify(lower: range.lowerBound, upper: range.upperBound)
        }
        return ScriptCoverage(
            mask: mask,
            ranges: CoverageRanges(ranges: codepointRanges)
        )
    }

    private static func format4Ranges(
        _ table: FontTable,
        offset: Int
    ) throws -> [ClosedRange<UInt32>] {
        let segCount = Int(try table.u16(offset + 6)) / 2
        guard segCount > 0, segCount < 4096 else { return [] }
        let endCodes = offset + 14
        let startCodes = endCodes + segCount * 2 + 2

        var result: [ClosedRange<UInt32>] = []
        result.reserveCapacity(segCount)
        for index in 0..<segCount {
            let end = UInt32(try table.u16(endCodes + index * 2))
            let start = UInt32(try table.u16(startCodes + index * 2))
            guard start <= end, start != 0xFFFF else { continue }
            result.append(start...end)
        }
        return result
    }

    private static func format12Ranges(
        _ table: FontTable,
        offset: Int
    ) throws -> [ClosedRange<UInt32>] {
        let groupCount = Int(try table.u32(offset + 12))
        guard groupCount > 0, groupCount < 65_536 else { return [] }
        let groups = offset + 16

        var result: [ClosedRange<UInt32>] = []
        result.reserveCapacity(groupCount)
        for index in 0..<groupCount {
            let record = groups + index * 12
            let start = try table.u32(record)
            let end = try table.u32(record + 4)
            guard start <= end else { continue }
            result.append(start...end)
        }
        return result
    }
}
