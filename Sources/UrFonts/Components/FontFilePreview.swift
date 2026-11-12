import AppKit
import SwiftUI
import UrFontsCore

/// One-line preview for a single downloaded file. Shared by the library family
/// sheet and host family sheets.
struct FontFilePreview: View {
    let path: String
    let faceIndex: Int
    let text: String
    let textColor: Color
    var size: CGFloat = 30

    @State private var loaded: LoadedFont?

    init(
        face: CatalogFace,
        text: String,
        textColor: Color,
        size: CGFloat = 30
    ) {
        self.path = face.path
        self.faceIndex = face.index
        self.text = text
        self.textColor = textColor
        self.size = size
    }

    init(
        path: String,
        faceIndex: Int = 0,
        text: String,
        textColor: Color,
        size: CGFloat = 30
    ) {
        self.path = path
        self.faceIndex = faceIndex
        self.text = text
        self.textColor = textColor
        self.size = size
    }

    var body: some View {
        Canvas { context, canvasSize in
            guard let loaded else { return }
            let font = PreviewLine.font(from: loaded.ctFont, size: size)
            context.withCGContext { cg in
                PreviewLine.drawTruncated(
                    text: text,
                    font: font,
                    color: NSColor(textColor),
                    in: cg,
                    rect: CGRect(origin: .zero, size: canvasSize),
                    inset: 0
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(path):\(faceIndex)") {
            loaded = await FontLoader.shared.font(path: path, faceIndex: faceIndex)
        }
    }
}
