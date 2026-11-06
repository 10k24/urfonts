import Foundation

/// Builds script coverage in the background, one batch of files at a time.
///
/// Coverage is deliberately not part of the main scan: reading the whole library
/// again is expensive, and cloud-backed folders may block on read. The caller
/// decides when to pay for it.
public actor CoverageIndexer {
    public struct Progress: Sendable, Equatable {
        public let indexed: Int
        public let total: Int
    }

    private let database: LibraryDatabase
    private var cancelled = false

    public init(database: LibraryDatabase) {
        self.database = database
    }

    public func cancel() {
        cancelled = true
    }

    /// Returns the number of faces now indexed. Safe to call repeatedly; each
    /// call resumes from the pending rows.
    @discardableResult
    public func index(
        batchSize: Int = 200,
        progress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> Int {
        cancelled = false
        var counts = try database.coverageCounts()
        progress?(Progress(indexed: counts.indexed, total: counts.total))

        while !cancelled {
            let pending = try database.pendingCoverage(limit: batchSize)
            if pending.isEmpty { break }

            let byPath = Dictionary(grouping: pending, by: \.path)
            for (path, faces) in byPath {
                if cancelled { break }
                let coverage = (try? FontFileParser.coverage(
                    url: URL(fileURLWithPath: path)
                )) ?? [:]
                var values: [String: ScriptCoverage] = [:]
                values.reserveCapacity(faces.count)
                for face in faces {
                    values[face.faceID] = coverage[face.faceIndex]
                        ?? ScriptCoverage(mask: 0, ranges: CoverageRanges(ranges: []))
                }
                try database.setCoverage(values)
            }

            counts = try database.coverageCounts()
            progress?(Progress(indexed: counts.indexed, total: counts.total))
        }
        return try database.coverageCounts().indexed
    }
}
