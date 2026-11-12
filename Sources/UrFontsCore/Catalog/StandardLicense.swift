import Foundation

/// Standard font licenses recognized by their body text. Detection is label-only;
/// the full license file remains on disk and is still shown by path.
public enum StandardLicense: String, Sendable {
    case ofl = "SIL Open Font License 1.1"
    case apache = "Apache License 2.0"
    case ufl = "Ubuntu Font Licence 1.0"
    case cc0 = "CC0 1.0"
    case mit = "MIT License"

    public static func detect(text: String) -> StandardLicense? {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.contains("sil open font license, version 1.1")
            || normalized.contains("sil open font license version 1.1"),
           normalized.contains("permission & conditions"),
           normalized.contains("termination") {
            return .ofl
        }
        if normalized.contains("apache license"),
           normalized.contains("version 2.0, january 2004"),
           normalized.contains("terms and conditions") {
            return .apache
        }
        if normalized.contains("ubuntu font licence")
            || normalized.contains("ubuntu font license"),
           normalized.contains("version 1.0") {
            return .ufl
        }
        if normalized.contains("cc0 1.0 universal"),
           normalized.contains("statement of purpose") {
            return .cc0
        }
        if normalized.contains("mit license"),
           normalized.contains("permission is hereby granted, free of charge") {
            return .mit
        }
        return nil
    }

    public static func detect(url: URL) -> StandardLicense? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return detect(text: text)
    }
}
