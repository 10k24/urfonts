import CoreText
import Foundation

/// One face inside one font file.
///
/// A file can hold several faces: a `.ttc` collection, or a variable font
/// whose named instances CoreText reports as separate descriptors. Names come
/// from CoreText so they match what the system and other apps show.
public struct FontFaceInfo: Sendable, Equatable {
    public let index: Int
    public let family: String
    public let style: String
    public let postscriptName: String

    public init(index: Int, family: String, style: String, postscriptName: String) {
        self.index = index
        self.family = family
        self.style = style
        self.postscriptName = postscriptName
    }
}

public enum FontFileReader {
    /// Reads face names without registering anything.
    ///
    /// The descriptors are process-local and cheap. Variable fonts return one
    /// descriptor per named instance, which usually share a PostScript name, so
    /// duplicates collapse on (PostScript name, style).
    public static func faces(at url: URL) -> [FontFaceInfo] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
            as? [CTFontDescriptor]
        else {
            return []
        }

        var faces: [FontFaceInfo] = []
        var seen = Set<String>()
        for (index, descriptor) in descriptors.enumerated() {
            let family = stringAttribute(kCTFontFamilyNameAttribute, of: descriptor)
            let style = stringAttribute(kCTFontStyleNameAttribute, of: descriptor)
            let postscriptName = stringAttribute(kCTFontNameAttribute, of: descriptor)

            // A descriptor without a PostScript name is not usable for
            // activation or conflict detection.
            guard let postscriptName, !postscriptName.isEmpty else { continue }

            let key = "\(postscriptName)\u{0}\(style ?? "")"
            guard seen.insert(key).inserted else { continue }

            faces.append(FontFaceInfo(
                index: index,
                family: family ?? postscriptName,
                style: style ?? "Regular",
                postscriptName: postscriptName
            ))
        }
        return faces
    }

    private static func stringAttribute(
        _ attribute: CFString,
        of descriptor: CTFontDescriptor
    ) -> String? {
        CTFontDescriptorCopyAttribute(descriptor, attribute) as? String
    }
}
