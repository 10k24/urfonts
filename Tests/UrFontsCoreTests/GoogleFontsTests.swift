import Foundation
import Testing
import UrFontsCore

@Suite("Google Fonts")
struct GoogleFontsTests {
    @Test("folder names are filesystem safe and stable")
    func folderName() {
        #expect(GoogleFontFamily.folderName(for: family("Open Sans")) == "Open Sans")
        #expect(GoogleFontFamily.folderName(for: family("Roboto Slab")) == "Roboto Slab")
        #expect(GoogleFontFamily.folderName(for: family("IBM Plex Sans")) == "IBM Plex Sans")
    }

    @Test("variants become named styles and map to variable files")
    func styles() {
        let upright = GoogleFontFile(
            path: "ofl/montserrat/Montserrat[wght].ttf",
            filename: "Montserrat[wght].ttf"
        )
        let italic = GoogleFontFile(
            path: "ofl/montserrat/Montserrat-Italic[wght].ttf",
            filename: "Montserrat-Italic[wght].ttf"
        )
        let montserrat = GoogleFontFamily(
            name: "Montserrat",
            category: "Sans Serif",
            variants: ["100", "100i", "400", "400i", "700", "700i"],
            popularity: 1,
            files: [italic, upright],
            licensePath: nil
        )
        #expect(montserrat.styles.map(\.name)
            == ["Thin", "Thin Italic", "Regular", "Italic", "Bold", "Bold Italic"])
        #expect(montserrat.styles[0].weight == 100)
        #expect(montserrat.styles[1].isItalic)
        #expect(montserrat.file(for: montserrat.styles[0])?.filename == upright.filename)
        #expect(montserrat.file(for: montserrat.styles[1])?.filename == italic.filename)
    }

    @Test("standard license bodies are recognized")
    func standardLicenses() {
        let ofl = """
        Copyright 2020 The Example Authors

        This Font Software is licensed under the SIL Open Font License, Version 1.1.

        SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007

        PERMISSION & CONDITIONS

        TERMINATION
        """
        #expect(StandardLicense.detect(text: ofl) == .ofl)
        #expect(StandardLicense.detect(text: "A custom license.") == nil)
    }

    private func family(_ name: String) -> GoogleFontFamily {
        GoogleFontFamily(
            name: name,
            category: "Sans Serif",
            variants: ["regular"],
            popularity: 1,
            files: [],
            licensePath: nil
        )
    }
}
