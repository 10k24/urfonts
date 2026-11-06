import Foundation

enum PreviewPreset: String, CaseIterable, Identifiable {
    case alphabet
    case abcd
    case pangram
    case numerals
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alphabet: "Uppercase, lowercase, numbers"
        case .abcd: "AaBbCcDdEeFf"
        case .pangram: "Pangram"
        case .numerals: "Numbers only"
        case .custom: "Custom"
        }
    }

    var text: String? {
        switch self {
        case .alphabet:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789"
        case .abcd:
            "AaBbCcDdEeFf"
        case .pangram:
            "The quick brown fox jumps over the lazy dog."
        case .numerals:
            "0123456789"
        case .custom:
            nil
        }
    }

    static func matching(_ text: String) -> PreviewPreset {
        for preset in PreviewPreset.allCases {
            if let value = preset.text, value == text { return preset }
        }
        return .custom
    }
}
