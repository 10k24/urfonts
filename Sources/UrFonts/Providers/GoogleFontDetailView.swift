import SwiftUI
import UrFontsCore

/// Host family sheet. Lists every style; each preview is fetched independently.
/// Variable families map several styles to one owned TTF.
struct GoogleFontDetailView: View {
    @Bindable var model: AppModel
    let family: GoogleFontFamily

    @Environment(\.dismiss) private var dismiss
    @State private var downloading: Set<String> = []
    @State private var progress: [String: Double] = [:]

    private var downloadedFace: CatalogFace? {
        model.googleFamilyPreviewFace(family)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    detailPreview
                    styles
                    if let url = licenseURL {
                        licenseRow(url)
                    }
                }
                .padding(24)
            }
        }
        .frame(
            minWidth: 720,
            idealWidth: 760,
            maxWidth: .infinity,
            minHeight: 460,
            idealHeight: 600,
            maxHeight: .infinity
        )
        .background(model.backgroundColor)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(family.name)
                    .font(.title2.weight(.semibold))
                Text(
                    "\(family.styles.count) styles · \(family.category)"
                        + (family.isVariable ? " · variable" : "")
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(Messages.Google.done) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private var detailPreview: some View {
        ZStack {
            if let face = downloadedFace {
                FontFilePreview(
                    face: face,
                    text: model.sampleText(for: face),
                    textColor: model.textColor,
                    size: 66
                )
            } else if let style = family.styles.first {
                GoogleStylePreview(
                    model: model,
                    family: family,
                    style: style,
                    file: family.file(for: style),
                    size: 66
                )
            } else {
                Text(Messages.Google.noPreview)
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

    private var styles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Messages.Google.styles)
                .font(.headline)
            if family.styles.isEmpty {
                Text("This family has no downloadable styles.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(family.styles) { style in
                    styleRow(style)
                    if style.id != family.styles.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func styleRow(_ style: GoogleFontStyle) -> some View {
        let file = family.file(for: style)
        return HStack(alignment: .bottom, spacing: 14) {
            if let file {
                HostActivationControl(
                    phase: fileControlPhase(file),
                    action: { toggle(file) }
                )
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(style.name)
                Text(file?.filename ?? "No file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(width: 200, alignment: .leading)

            GoogleStylePreview(
                model: model,
                family: family,
                style: style,
                file: file
            )
            .frame(height: 44)
        }
        .padding(.vertical, 10)
        .help(
            family.isVariable && file != nil
                ? "Variable file: activating a style activates every style in this file"
                : ""
        )
    }

    private func licenseRow(_ url: URL) -> some View {
        HStack(spacing: 8) {
            Text(StandardLicense.detect(url: url)?.rawValue ?? Messages.Google.readLicense)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Text(url.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private var licenseURL: URL? {
        guard let root = try? model.googleFontsRoot() else { return nil }
        let url = root
            .appendingPathComponent(GoogleFontFamily.folderName(for: family), isDirectory: true)
            .appendingPathComponent("LICENSE.txt")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func fileControlPhase(_ file: GoogleFontFile) -> HostControlPhase {
        if downloading.contains(file.filename) {
            return .downloading(progress: progress[file.filename])
        }
        if let state = model.googleFileActivation(family: family, file: file) {
            return .file(state)
        }
        return .download
    }

    private func toggle(_ file: GoogleFontFile) {
        guard !downloading.contains(file.filename) else { return }
        downloading.insert(file.filename)
        progress[file.filename] = nil
        Task { @MainActor in
            do {
                try await model.toggleGoogleFile(family, file: file) { done, total in
                    Task { @MainActor in
                        progress[file.filename] = total > 0
                            ? Double(done) / Double(total)
                            : nil
                    }
                }
            } catch {
                model.report(error, context: "Google style activation")
            }
            downloading.remove(file.filename)
            progress.removeValue(forKey: file.filename)
        }
    }
}

/// One style preview, downloaded as a tiny CSS subset. Falls back to the
/// downloaded file when the network is unavailable.
private struct GoogleStylePreview: View {
    @Bindable var model: AppModel
    let family: GoogleFontFamily
    let style: GoogleFontStyle
    let file: GoogleFontFile?
    var size: CGFloat = 30

    @State private var previewURL: URL?

    var body: some View {
        Group {
            if let previewURL {
                FontFilePreview(
                    path: previewURL.path,
                    text: model.sampleText,
                    textColor: model.textColor,
                    size: size
                )
            } else if let face = file.flatMap({
                model.googleFace(family: family, file: $0)
            }) {
                FontFilePreview(
                    face: face,
                    text: model.sampleText(for: face),
                    textColor: model.textColor,
                    size: size
                )
            } else {
                Text(style.name)
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: previewKey) {
            previewURL = await model.googlePreviewURL(
                family: family,
                text: model.sampleText,
                style: style
            )
        }
    }

    private var previewKey: String {
        "\(family.name)\u{0}\(style.id)\u{0}\(model.sampleText)"
    }
}
