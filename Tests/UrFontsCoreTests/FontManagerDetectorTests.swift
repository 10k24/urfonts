import Foundation
import Testing
import UrFontsCore

@Suite("Font manager detection")
struct FontManagerDetectorTests {
    @Test("no config folder means no suggestions")
    func noConfig() {
        let detector = FontBaseCacheDetector(
            homeDirectory: "/Users/test",
            fileExists: { _ in false }
        )
        #expect(detector.detect().isEmpty)
    }

    @Test("config plus cache folders produces canonical suggestions")
    func detectsCaches() {
        let home = "/Users/test"
        let config = home + "/Library/Application Support/FontBase"
        let cache = home + "/Library/Fonts/FontBase"
        let detector = FontBaseCacheDetector(
            homeDirectory: home,
            fileExists: { path in path == config || path == cache }
        )
        let caches = detector.detect()
        #expect(caches.count == 1)
        #expect(caches[0].managerName == "FontBase")
        #expect(caches[0].path == LibraryPath.resolve(cache))
    }

    @Test("config without a cache folder produces no suggestion")
    func configOnly() {
        let home = "/Users/test"
        let config = home + "/Library/Application Support/FontBase"
        let detector = FontBaseCacheDetector(
            homeDirectory: home,
            fileExists: { $0 == config }
        )
        #expect(detector.detect().isEmpty)
    }
}
