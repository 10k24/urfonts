import Foundation
import Testing
import UrFontsCore
import UrFontsFixtures

@Suite("Minimal font fixtures")
struct MinimalFontTests {
    private func makeFont(_ index: Int = 0) throws -> URL {
        let spec = MinimalFontSpec(index: index)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-test-\(UUID().uuidString).ttf")
        try MinimalFont.data(for: spec).write(to: url)
        return url
    }

    @Test("table directory is well formed")
    func tableDirectory() throws {
        let url = try makeFont()
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)

        #expect(data.count % 4 == 0)
        #expect(readUInt32(data, at: 0) == 0x0001_0000)
        let numTables = readUInt16(data, at: 4)
        #expect(numTables == 10)

        var tags: [String] = []
        for index in 0..<Int(numTables) {
            let offset = 12 + index * 16
            tags.append(String(bytes: data[offset..<(offset + 4)], encoding: .ascii) ?? "")
        }
        #expect(Set(tags).count == tags.count)
        #expect(tags.contains("head"))
        #expect(tags.contains("name"))
        #expect(tags.contains("OS/2"))
    }

    @Test("whole file checksum matches the head adjustment")
    func checksumAdjustment() throws {
        let url = try makeFont()
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)

        var sum: UInt32 = 0
        var index = 0
        while index < data.count {
            var word: UInt32 = 0
            for offset in 0..<4 {
                word <<= 8
                if index + offset < data.count {
                    word |= UInt32(data[index + offset])
                }
            }
            sum = sum &+ word
            index += 4
        }
        #expect(sum == 0xB1B0_AFBA)
    }

    @Test("CoreText reads back the names")
    func coreTextNames() throws {
        let url = try makeFont(0)
        defer { try? FileManager.default.removeItem(at: url) }
        let faces = FontFileReader.faces(at: url)

        #expect(faces.count == 1)
        let face = try #require(faces.first)
        #expect(face.family == "Fixture Family 00001")
        #expect(face.style == "Regular")
        #expect(face.postscriptName == "FixtureFamily00001-Regular")
    }

    @Test("styles and families vary by index")
    func variants() throws {
        let urls = try [makeFont(0), makeFont(1), makeFont(4)]
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }
        let faces = urls.map { FontFileReader.faces(at: $0) }

        #expect(faces[0].first?.style == "Regular")
        #expect(faces[1].first?.style == "Bold")
        #expect(faces[2].first?.family == "Fixture Family 00002")
    }

    @Test("unreadable data has no faces")
    func invalidData() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-test-\(UUID().uuidString).ttf")
        try Data("not a font".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(FontFileReader.faces(at: url).isEmpty)
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }
}

@Suite("Registration scope")
struct RegistrationScopeTests {
    @Test("CoreText scopes round trip")
    func roundTrip() {
        for scope in FontRegistrationScope.allCases {
            #expect(FontRegistrationScope(coreText: scope.coreText) == scope)
        }
        #expect(FontRegistrationScope(coreText: .persistent) == .user)
        #expect(FontRegistrationScope.none.isRegistered == false)
        #expect(FontRegistrationScope.user.isRegistered)
    }

    @Test("report requires every request confirmed and no failures")
    func report() {
        #expect(RegistrationReport(requestedCount: 1, confirmedCount: 1, failures: []).succeeded)
        #expect(!RegistrationReport(requestedCount: 1, confirmedCount: 0, failures: []).succeeded)
        #expect(!RegistrationReport(
            requestedCount: 1,
            confirmedCount: 1,
            failures: [RegistrationFailure(message: "duplicate", urls: [])]
        ).succeeded)
    }
}
