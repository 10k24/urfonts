import Foundation

/// Bounds-checked reads over mapped font data.
///
/// A font file is untrusted input. Every read either returns a value inside the
/// requested table or throws; a damaged font yields fewer faces, never a crash.
struct ByteReader {
    let data: Data

    func u8(_ offset: Int) throws -> UInt8 {
        guard offset >= 0, offset + 1 <= data.count else { throw FontParseError.truncated }
        return data[data.startIndex + offset]
    }

    func u16(_ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { throw FontParseError.truncated }
        let start = data.startIndex + offset
        return UInt16(data[start]) << 8 | UInt16(data[start + 1])
    }

    func i16(_ offset: Int) throws -> Int16 {
        Int16(bitPattern: try u16(offset))
    }

    func u32(_ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { throw FontParseError.truncated }
        let start = data.startIndex + offset
        return UInt32(data[start]) << 24
            | UInt32(data[start + 1]) << 16
            | UInt32(data[start + 2]) << 8
            | UInt32(data[start + 3])
    }

    func i32(_ offset: Int) throws -> Int32 {
        Int32(bitPattern: try u32(offset))
    }

    func tag(_ offset: Int) throws -> String {
        guard offset >= 0, offset + 4 <= data.count else { throw FontParseError.truncated }
        let start = data.startIndex + offset
        let bytes = data[start..<(start + 4)]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    func string(_ offset: Int, length: Int, encoding: String.Encoding) -> String? {
        guard offset >= 0, length >= 0, offset + length <= data.count else { return nil }
        let start = data.startIndex + offset
        return String(data: data[start..<(start + length)], encoding: encoding)
    }
}

/// One table, addressed inside the whole file.
struct FontTable {
    let reader: ByteReader
    let offset: Int
    let length: Int

    func u8(_ relative: Int) throws -> UInt8 {
        try check(relative, 1)
        return try reader.u8(offset + relative)
    }

    func u16(_ relative: Int) throws -> UInt16 {
        try check(relative, 2)
        return try reader.u16(offset + relative)
    }

    func i16(_ relative: Int) throws -> Int16 {
        try check(relative, 2)
        return try reader.i16(offset + relative)
    }

    func u32(_ relative: Int) throws -> UInt32 {
        try check(relative, 4)
        return try reader.u32(offset + relative)
    }

    func i32(_ relative: Int) throws -> Int32 {
        try check(relative, 4)
        return try reader.i32(offset + relative)
    }

    func tag(_ relative: Int) throws -> String {
        try check(relative, 4)
        return try reader.tag(offset + relative)
    }

    func data(_ relative: Int, length count: Int) throws -> Data {
        try check(relative, count)
        let start = reader.data.startIndex + offset + relative
        return reader.data[start..<(start + count)]
    }

    private func check(_ relative: Int, _ count: Int) throws {
        guard relative >= 0, count >= 0, relative + count <= length else {
            throw FontParseError.truncated
        }
    }
}

/// Table directory for one face. A `.ttc` has one directory per face.
struct FontTables {
    private let reader: ByteReader
    private let records: [String: (offset: Int, length: Int)]

    init(data: Data, directoryOffset: Int) throws {
        let reader = ByteReader(data: data)
        let version = try reader.u32(directoryOffset)
        let accepted: Set<UInt32> = [
            0x0001_0000,  // TrueType outlines
            0x4F54_544F,  // OTTO, CFF outlines
            0x7472_7565,  // true
            0x7479_7031,  // typ1
        ]
        guard accepted.contains(version) else { throw FontParseError.notAFont }
        self.reader = reader

        let numTables = Int(try reader.u16(directoryOffset + 4))
        guard numTables > 0, numTables < 4096 else { throw FontParseError.malformed }

        var records: [String: (offset: Int, length: Int)] = [:]
        records.reserveCapacity(numTables)
        for index in 0..<numTables {
            let record = directoryOffset + 12 + index * 16
            let tag = try reader.tag(record)
            let offset = Int(try reader.u32(record + 8))
            let length = Int(try reader.u32(record + 12))
            guard offset >= 0, length >= 0, offset + length <= data.count else { continue }
            records[tag] = (offset, length)
        }
        self.records = records
    }

    func table(_ tag: String) -> FontTable? {
        guard let record = records[tag] else { return nil }
        return FontTable(reader: reader, offset: record.offset, length: record.length)
    }
}

public enum FontParseError: Error, Equatable {
    case notAFont
    case truncated
    case malformed
}
