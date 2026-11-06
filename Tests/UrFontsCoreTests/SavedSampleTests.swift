import Foundation
import Testing
import UrFontsCore

@Suite("Saved samples")
struct SavedSampleTests {
    @Test("samples round-trip and delete")
    func crud() throws {
        let database = try LibraryDatabase(inMemory: true)
        #expect(try database.samples().isEmpty)

        let sample = SavedSample(
            id: "sample-1",
            name: "Brand specimen",
            text: "Hamburgefonstiv",
            size: 42,
            textColor: "#FFFFFFFF",
            backgroundColor: "#101010FF",
            sort: 0,
            createdAt: 1
        )
        try database.upsertSample(sample)
        var samples = try database.samples()
        #expect(samples.count == 1)
        #expect(samples[0].name == "Brand specimen")
        #expect(samples[0].size == 42)

        var edited = sample
        edited.name = "Client A"
        edited.size = 64
        try database.upsertSample(edited)
        samples = try database.samples()
        #expect(samples.count == 1)
        #expect(samples[0].name == "Client A")
        #expect(samples[0].size == 64)

        let second = SavedSample(
            id: "sample-2",
            name: "Body",
            text: "Second",
            size: 18,
            textColor: "#000000FF",
            backgroundColor: "#FFFFFFFF",
            sort: 1,
            createdAt: 2
        )
        try database.upsertSample(second)
        #expect(try database.samples().map(\.name) == ["Client A", "Body"])

        try database.deleteSample(id: "sample-1")
        #expect(try database.samples().map(\.name) == ["Body"])
    }
}
