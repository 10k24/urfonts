import Foundation
import GRDB

/// Maps internal errors to text safe for the UI. Raw database errors and their
/// SQL must never reach an alert or a footer.
public enum LibraryErrorText {
    public static let databaseFailure =
        "The library could not be updated. Rescan the folder and try again."
    public static let genericFailure =
        "Something went wrong. Please try again."

    public static func message(for error: Error) -> String {
        if CloudAccess.isUnavailable(error) {
            return CloudAccess.message
        }
        if error is DatabaseError {
            return databaseFailure
        }
        if error is ScanError {
            return "That folder could not be read."
        }
        if let google = error as? GoogleFontsError,
           let text = google.errorDescription {
            return text
        }
        return genericFailure
    }
}
