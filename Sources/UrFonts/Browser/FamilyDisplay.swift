import Foundation
import UrFontsCore

/// A local font file used for a preview. Library rows pass a catalog face;
/// host rows pass their downloaded face or a lightweight preview subset.
struct PreviewSource: Equatable {
    let path: String
    let faceIndex: Int
    /// The face's PostScript name. CoreText returns one descriptor per named
    /// variable instance, so the SFNT face index alone can select the wrong
    /// face in a variable font or collection. Host subsets leave this nil.
    let postscriptName: String?

    init(path: String, faceIndex: Int = 0, postscriptName: String? = nil) {
        self.path = path
        self.faceIndex = faceIndex
        self.postscriptName = postscriptName
    }

    init(face: CatalogFace) {
        self.path = face.path
        self.faceIndex = face.index
        self.postscriptName = face.postscriptName
    }
}

/// Display data shared by library and host rows. Keeps `FamilyRow` and
/// `FamilyTile` independent of `CatalogFamily`.
struct FamilyDisplay: Identifiable, Equatable {
    let id: String
    let name: String
    let countLabel: String
    let shortCount: String
    let hasVariableFace: Bool
    let warning: String?

    init(
        id: String,
        name: String,
        countLabel: String,
        shortCount: String,
        hasVariableFace: Bool,
        warning: String?
    ) {
        self.id = id
        self.name = name
        self.countLabel = countLabel
        self.shortCount = shortCount
        self.hasVariableFace = hasVariableFace
        self.warning = warning
    }

    init(family: CatalogFamily) {
        var reasons: [String] = []
        if family.hasDuplicatePostScriptNames {
            reasons.append("Multiple files share a PostScript name")
        }
        if family.missingFaceCount > 0 {
            reasons.append("\(family.missingFaceCount) file(s) missing")
        }
        self.init(
            id: family.id,
            name: family.name,
            countLabel: family.countLabel,
            shortCount: "\(family.styleCount)",
            hasVariableFace: family.hasVariableFace,
            warning: reasons.isEmpty ? nil : reasons.joined(separator: ". ")
        )
    }

    init(google family: GoogleFontFamily) {
        let styles = family.styles.count
        self.init(
            id: family.name,
            name: family.name,
            countLabel: "\(styles) \(styles == 1 ? "style" : "styles") · \(family.category)",
            shortCount: "\(styles)",
            hasVariableFace: family.isVariable,
            warning: family.files.isEmpty ? "No downloadable files" : nil
        )
    }
}
