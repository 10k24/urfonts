import Foundation
import GRDB
import Testing
import UrFontsCore

@Suite("Library error text")
struct LibraryErrorTextTests {
    @Test("database errors never expose SQL")
    func databaseErrorIsSafe() {
        let error = DatabaseError(
            resultCode: .SQLITE_CONSTRAINT,
            message: "UNIQUE constraint failed: file.path",
            sql: "INSERT INTO file (id, path) VALUES (?, ?)",
            arguments: nil
        )
        let text = LibraryErrorText.message(for: error)
        #expect(text == LibraryErrorText.databaseFailure)
        #expect(!text.localizedCaseInsensitiveContains("sqlite"))
        #expect(!text.localizedCaseInsensitiveContains("insert"))
        #expect(!text.localizedCaseInsensitiveContains("file.path"))
    }

    @Test("scan errors use a safe folder message")
    func scanErrorIsSafe() {
        let text = LibraryErrorText.message(for: ScanError.unreadableFolder)
        #expect(text == "That folder could not be read.")
    }

    @Test("unknown errors use the generic message")
    func unknownErrorIsSafe() {
        struct Oops: Error {}
        #expect(LibraryErrorText.message(for: Oops()) == LibraryErrorText.genericFailure)
    }
}
