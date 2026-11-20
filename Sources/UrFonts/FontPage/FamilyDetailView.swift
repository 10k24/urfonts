import AppKit
import CoreText
import SwiftUI
import UrFontsCore

struct FamilyDetailView: View {
    @Bindable var model: AppModel
    let family: CatalogFamily

    @Environment(\.dismiss) private var dismiss
    @State private var axisValues: [String: Double] = [:]
    @State private var features: [OpenTypeFeature] = []

    private var faces: [CatalogFace] {
        model.snapshot.faces(in: family).sorted { left, right in
            let leftOK = left.fileStatus == "ok"
            let rightOK = right.fileStatus == "ok"
            if leftOK != rightOK {
                return leftOK
            }
            let style = left.style.localizedStandardCompare(right.style)
            if style != .orderedSame {
                return style == .orderedAscending
            }
            return left.path.localizedStandardCompare(right.path) == .orderedAscending
        }
    }

    private var previewFace: CatalogFace? {
        faces.first { $0.fileStatus == "ok" && $0.isVariable && !$0.isItalic }
            ?? model.representativeFace(for: family)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    detailPreview
                    if let previewFace, !previewFace.axes.isEmpty {
                        axes(for: previewFace)
                    }
                    styles
                    if !features.isEmpty {
                        featureList
                    }
                    if let previewFace {
                        GlyphMapView(face: previewFace, textColor: model.textColor)
                    }
                    info
                }
                .padding(24)
            }
        }
        .frame(
            minWidth: 720,
            idealWidth: 760,
            maxWidth: .infinity,
            minHeight: 520,
            idealHeight: 640,
            maxHeight: .infinity
        )
        .background(model.backgroundColor)
        .onAppear(perform: loadDefaultAxes)
        .onChange(of: previewFace?.id) { _, _ in
            loadDefaultAxes()
        }
        .task(id: previewFace?.id) {
            await loadFeatures()
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OpenType features")
                .font(.headline)
            Text(features.map { OpenTypeFeature.displayName(for: $0.tag) }.joined(separator: " · "))
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func loadFeatures() async {
        guard let face = previewFace else {
            features = []
            return
        }
        let faceID = face.id
        let tags = await Task.detached(priority: .userInitiated) {
            (try? FontFileParser.featureTags(
                url: URL(fileURLWithPath: face.path),
                faceIndex: face.index
            )) ?? []
        }.value
        guard previewFace?.id == faceID else { return }
        features = tags
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(family.name)
                    .font(.title2.weight(.semibold))
                Text(family.countLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private var detailPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                DetailPreview(
                    face: previewFace,
                    axes: previewFace?.axes ?? [],
                    axisValues: axisValues,
                    text: previewFace?.previewText(userText: model.sampleText)
                        ?? model.sampleText,
                    textColor: model.textColor
                )
                if previewFace == nil {
                    Text("No readable file in this family")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.04))
            )
        }
    }

    private var styles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hasDuplicatePostScriptName ? "Files" : "Styles")
                .font(.headline)
            if hasDuplicatePostScriptName {
                Text("More than one file in this family reports the same PostScript "
                    + "name. Only one can be active at a time; the others are disabled.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            VStack(spacing: 0) {
                ForEach(faces) { face in
                    let state = model.faceActivationState(face)
                    let duplicatePostScript = face.fileStatus == "ok"
                        && faces.contains { other in
                            other.fileStatus == "ok"
                                && other.id != face.id
                                && other.postscriptName.caseInsensitiveCompare(
                                    face.postscriptName
                                ) == .orderedSame
                        }
                    let fileName = (face.path as NSString).lastPathComponent
                    let isCloud = face.fileStatus == "cloud"
                    let isMissing = face.fileStatus != "ok" && !isCloud
                    let alternatePath = alternatePath(for: state)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 14) {
                            FaceActivationControl(
                                state: state,
                                action: { Task { await model.toggle(face: face) } }
                            )
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(face.style)
                                    if duplicatePostScript {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.orange)
                                            .help(
                                                "Another file in this family uses the "
                                                    + "same PostScript name"
                                            )
                                    }
                                }
                                Text(duplicatePostScript ? fileName : face.postscriptName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                            .frame(width: 190, alignment: .leading)

                            if isCloud {
                                Text("Not downloaded from cloud")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else if isMissing {
                                Text("File missing")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else if let alternatePath {
                                Text(
                                    "Alternate file; use "
                                        + (alternatePath as NSString).lastPathComponent
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                FontFilePreview(
                                    face: face,
                                    text: face.previewText(userText: model.sampleText),
                                    textColor: model.textColor
                                )
                                .frame(height: 46)
                            }

                            Text("\(face.weightClass)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 30, alignment: .trailing)
                        }

                        Text(face.path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(face.path)
                            .padding(.leading, 32)

                        if isCloud {
                            Text("Not downloaded from cloud")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .padding(.leading, 32)
                        } else if isMissing {
                            Text("Missing file")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .padding(.leading, 32)
                        } else if let alternatePath {
                            Text(
                                "Alternate file; use "
                                    + (alternatePath as NSString).lastPathComponent
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 32)
                        }

                        if let owner = blockedOwner(of: state) {
                            Text("In use by \(owner)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, 32)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    if face.id != faces.last?.id {
                        Divider()
                    }
                }
            }
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func alternatePath(for state: FaceActivationState) -> String? {
        if case .alternate(let path) = state {
            return path
        }
        return nil
    }

    private func blockedOwner(of state: FaceActivationState) -> String? {
        if case .blocked(let owner) = state {
            return owner
        }
        return nil
    }

    private var hasDuplicatePostScriptName: Bool {
        var seen = Set<String>()
        for face in faces where face.fileStatus == "ok" {
            if !seen.insert(face.postscriptName.lowercased()).inserted {
                return true
            }
        }
        return false
    }

    private func axes(for face: CatalogFace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Variable axes")
                    .font(.headline)
                Spacer()
                Button("Reset") {
                    loadDefaultAxes()
                }
                .font(.caption)
            }
            ForEach(face.axes, id: \.tag) { axis in
                HStack(spacing: 12) {
                    Text(axis.name)
                        .frame(width: 130, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { axisValues[axis.tag] ?? axis.defaultValue },
                            set: { axisValues[axis.tag] = $0 }
                        ),
                        in: axis.minimum...max(axis.minimum + 0.001, axis.maximum)
                    )
                    Text(String(format: "%.0f", axisValues[axis.tag] ?? axis.defaultValue))
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Info")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                if let face = previewFace {
                    GridRow {
                        Text("File").foregroundStyle(.secondary)
                        Text(face.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    if let vendor = face.vendorID {
                        GridRow {
                            Text("Vendor").foregroundStyle(.secondary)
                            Text(vendor)
                        }
                    }
                    if let embedding = face.embedding {
                        GridRow {
                            Text("Embedding").foregroundStyle(.secondary)
                            Text("\(embedding)")
                        }
                    }
                    GridRow {
                        Text("Units per em").foregroundStyle(.secondary)
                        Text("\(face.unitsPerEm)")
                    }
                }
            }
            HStack(spacing: 10) {
                if let face = previewFace {
                    Button("Reveal in Finder") { model.revealInFinder(face) }
                    Button("Copy PostScript name") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(face.postscriptName, forType: .string)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func loadDefaultAxes() {
        guard let face = previewFace else { return }
        var values: [String: Double] = [:]
        for axis in face.axes {
            values[axis.tag] = axis.defaultValue
        }
        axisValues = values
    }
}

/// One style rendered in the sample text, so the page shows the whole family
/// the way it will look in use.
private struct DetailPreview: View {
    let face: CatalogFace?
    let axes: [FontAxis]
    let axisValues: [String: Double]
    let text: String
    let textColor: Color

    @State private var loaded: LoadedFont?

    var body: some View {
        Canvas { context, size in
            guard let loaded else { return }
            let font = variedFont(base: loaded.ctFont)
            context.withCGContext { cg in
                // Fixed point size: refitting to the canvas on every axis tick
                // changes the scale as weight changes width, which reads as
                // jitter. Truncate instead and keep the scale stable.
                PreviewLine.drawTruncated(
                    text: text,
                    font: font,
                    color: NSColor(textColor),
                    in: cg,
                    rect: CGRect(origin: .zero, size: size),
                    inset: 8
                )
            }
        }
        .task(id: face?.id) {
            guard let face else { return }
            loaded = await FontLoader.shared.font(
                path: face.path,
                faceIndex: face.index,
                postscriptName: face.postscriptName
            )
        }
    }

    private func variedFont(base: CTFont) -> CTFont {
        let size: CGFloat = 64
        guard !axes.isEmpty else {
            return CTFontCreateCopyWithAttributes(base, size, nil, nil)
        }
        var variation: [NSNumber: NSNumber] = [:]
        for axis in axes {
            let value = axisValues[axis.tag] ?? axis.defaultValue
            variation[NSNumber(value: Self.fourCharCode(axis.tag))] = NSNumber(value: value)
        }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(base),
            [kCTFontVariationAttribute: variation] as CFDictionary
        )
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    private static func fourCharCode(_ tag: String) -> UInt32 {
        var code: UInt32 = 0
        for byte in tag.utf8.prefix(4) {
            code = (code << 8) | UInt32(byte)
        }
        return code
    }
}
