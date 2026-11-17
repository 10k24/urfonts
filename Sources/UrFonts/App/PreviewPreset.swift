import Foundation

/// A sample-text preset in the preview settings picker.
///
/// One table owns the stable id, title and sample for every preset, so adding a
/// preset is one entry instead of edits in three switches. `custom` has no
/// sample text and represents any user-edited string.
struct PreviewPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let text: String?

    static let custom = PreviewPreset(
        id: "custom",
        title: "Custom",
        text: nil
    )

    /// Picker order is deliberate: broad sample first, narrow samples next,
    /// custom last. Alphabetical titles would put "AaBbCcDdEeFf" first and bury
    /// the general sample.
    static let all: [PreviewPreset] = [
        .init(
            id: "alphabet",
            title: "Uppercase, lowercase, numbers",
            text: "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789"
        ),
        .init(id: "abcd", title: "AaBbCcDdEeFf", text: "AaBbCcDdEeFf"),
        .init(
            id: "pangram",
            title: "Pangram",
            text: "The quick brown fox jumps over the lazy dog."
        ),
        .init(id: "numerals", title: "Numbers only", text: "0123456789"),
        custom,
    ]

    static func matching(_ text: String) -> PreviewPreset {
        all.first { $0.text == text } ?? custom
    }
}
