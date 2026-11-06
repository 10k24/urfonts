import AppKit
import SwiftUI

/// Colors persist as `#RRGGBB` or `#RRGGBBAA` in the database, never as
/// NSColor archives.
extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8,
              let number = UInt64(value, radix: 16) else {
            return nil
        }
        let hasAlpha = value.count == 8
        let red = Double((number >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = Double((number >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = Double((number >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? Double(number & 0xFF) / 255 : 1
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Separators must not depend on the app appearance: preview backgrounds can
    /// be any color. Use a neutral gray that contrasts with the background.
    static func previewDivider(on background: Color) -> Color {
        guard let color = NSColor(background).usingColorSpace(.sRGB) else {
            return Color.gray.opacity(0.4)
        }
        let luminance = 0.2126 * color.redComponent
            + 0.7152 * color.greenComponent
            + 0.0722 * color.blueComponent
        return luminance > 0.5
            ? Color.black.opacity(0.16)
            : Color.white.opacity(0.16)
    }

    var hexRGBA: String {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else {
            return "#000000FF"
        }
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        let alpha = Int((color.alphaComponent * 255).rounded())
        return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }
}
