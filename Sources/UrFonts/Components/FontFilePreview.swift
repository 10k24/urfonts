import AppKit
import SwiftUI
import UrFontsCore

/// One-line preview for a single downloaded file. Shared by the library family
/// sheet and host family sheets.
struct FontFilePreview: View {
    let face: CatalogFace
    let text: String
    let textColor: Color
    var size: CGFloat = 30

    @State private var loaded: LoadedFont?

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
        .task(id: face.id) {
            loaded = await FontLoader.shared.font(path: face.path, faceIndex: face.index)
        }
    }
}
