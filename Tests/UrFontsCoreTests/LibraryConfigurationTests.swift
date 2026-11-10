import Foundation
import Testing
import UrFontsCore

@Suite("Settings configuration")
struct LibraryConfigurationTests {
    @Test("configuration JSON round-trips with a version")
    func roundTrip() throws {
        let configuration = LibraryConfiguration(
            exportedAt: "2026-11-04T00:00:00Z",
            folders: [
                .init(path: "/Users/x/Fonts", kind: "watched", label: "Client A"),
                .init(path: "/Users/x/Trials", kind: "static", label: nil),
            ],
            collections: [
                .init(name: "Brand", sort: 0, fonts: ["Inter-Regular", "Inter-Bold"]),
            ],
            samples: [
                .init(
                    name: "Specimen",
                    text: "AaBbCcDdEeFf",
                    size: 42,
                    textColor: "#FFFFFFFF",
                    backgroundColor: "#101010FF",
                    alignment: "left"
                ),
            ],
            preview: .init(
                text: "Hamburgefonstiv",
                size: 42,
                textColor: "#FFFFFFFF",
                backgroundColor: "#101010FF",
                showSystemFonts: true,
                fallbackFileNames: true
            ),
            ignoredPaths: ["/Users/x/Fonts/Cache"]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)

        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["version"] as? Int == LibraryConfiguration.currentVersion)

        let decoded = try JSONDecoder().decode(LibraryConfiguration.self, from: data)
        #expect(decoded == configuration)
        #expect(decoded.collections[0].fonts == ["Inter-Regular", "Inter-Bold"])
        #expect(decoded.folders[0].label == "Client A")
        #expect(decoded.ignoredPaths == ["/Users/x/Fonts/Cache"])

        // Settings files written before exclusions existed have no key.
        var legacy = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        legacy.removeValue(forKey: "ignoredPaths")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let old = try JSONDecoder().decode(LibraryConfiguration.self, from: legacyData)
        #expect(old.ignoredPaths == nil)
    }
}
