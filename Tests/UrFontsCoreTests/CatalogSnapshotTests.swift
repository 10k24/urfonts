import Testing
@testable import UrFontsCore

struct CatalogSnapshotTests {
    @Test("alternate files collapse into one selectable style")
    func alternateFilesCollapse() {
        let otf = face(
            id: "otf",
            family: "Test Family",
            style: "Regular",
            postscript: "TestFamily-Regular",
            path: "/fonts/TestFamily-Regular.otf",
            weight: 400
        )
        let webTtf = face(
            id: "web",
            family: "Test Family",
            style: "Regular",
            postscript: "TestFamily-Regular-Web",
            path: "/fonts/WEB/TestFamily-Regular.ttf",
            weight: 400
        )
        let bold = face(
            id: "bold",
            family: "Test Family",
            style: "Bold",
            postscript: "TestFamily-Bold",
            path: "/fonts/TestFamily-Bold.otf",
            weight: 700
        )

        let snapshot = CatalogSnapshot.build(faces: [webTtf, bold, otf])
        let family = snapshot.families[0]

        #expect(family.faceCount == 3)
        #expect(family.styleCount == 2)
        #expect(family.countLabel == "2 styles")
        #expect(family.preferredFaceIDs.contains("otf"))
        #expect(family.preferredFaceIDs.contains("bold"))
        #expect(!family.preferredFaceIDs.contains("web"))
        #expect(!family.hasDuplicatePostScriptNames)
        #expect(
            family.representativeFace(in: snapshot.faces(in: family))?.id == "otf"
        )
    }

    @Test("placeholder PostScript names do not become faces")
    func placeholderNamesFiltered() {
        let real = face(
            id: "real",
            family: "Real Family",
            style: "Regular",
            postscript: "RealFamily-Regular",
            path: "/fonts/RealFamily-Regular.otf"
        )
        let broken = face(
            id: "broken",
            family: "Real Family",
            style: "Regular",
            postscript: "false",
            path: "/fonts/WEB/RealFamily-Regular.ttf"
        )

        let snapshot = CatalogSnapshot.build(faces: [real, broken])

        #expect(snapshot.faceCount == 1)
        #expect(snapshot.families.count == 1)
        #expect(snapshot.families[0].styleCount == 1)
        #expect(snapshot.families[0].preferredFaceIDs == ["real"])
    }

    private func face(
        id: String,
        family: String,
        style: String,
        postscript: String,
        path: String,
        weight: Int = 400
    ) -> CatalogFace {
        CatalogFace(
            id: id,
            fileID: "file-\(id)",
            path: path,
            fileStatus: "ok",
            index: 0,
            family: family,
            familyKey: family.lowercased(),
            style: style,
            fullName: "\(family) \(style)",
            postscriptName: postscript,
            weightClass: weight,
            widthClass: 5,
            isItalic: false,
            isVariable: false,
            axes: [],
            unitsPerEm: 1000,
            xHeight: nil,
            capHeight: nil,
            ascender: nil,
            descender: nil,
            vendorID: nil,
            embedding: nil,
            scriptMask: 0,
            previewMask: 0
        )
    }
}
