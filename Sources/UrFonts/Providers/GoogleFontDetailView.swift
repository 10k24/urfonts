import SwiftUI
import UrFontsCore

/// Host family sheet. Same activation controls and file previews as the library
/// family sheet; the only extra state is downloading.
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
                    files
                    if let licenseURL = licenseURL {
                        Text("License: \(licenseURL.path)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
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
                    "\(family.category) · \(family.variants.count) variants"
                        + (family.isVariable ? " · variable" : "")
                )
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
        ZStack {
            if let face = downloadedFace {
                FontFilePreview(
                    face: face,
                    text: model.sampleText(for: face),
                    textColor: model.textColor,
                    size: 66
                )
            } else {
                Text("Download a font to preview")
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

    private var files: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Files")
                .font(.headline)
            if family.files.isEmpty {
                Text("This family has no downloadable files.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(family.files, id: \.path) { file in
                    fileRow(file)
                    if file.path != family.files.last?.path {
                        Divider()
                    }
                }
            }
        }
    }

    private func fileRow(_ file: GoogleFontFile) -> some View {
        HStack(spacing: 14) {
            HostActivationControl(
                phase: fileControlPhase(file),
                action: { toggle(file) }
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(styleLabel(for: file))
                Text(file.filename)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(width: 190, alignment: .leading)

            if let face = model.googleFace(family: family, file: file) {
                FontFilePreview(
                    face: face,
                    text: model.sampleText(for: face),
                    textColor: model.textColor
                )
            } else {
                Text("Not downloaded")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
    }

    private var licenseURL: URL? {
        guard let root = try? model.googleFontsRoot() else { return nil }
        let url = root
            .appendingPathComponent(GoogleFontFamily.folderName(for: family), isDirectory: true)
            .appendingPathComponent("LICENSE.txt")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func styleLabel(for file: GoogleFontFile) -> String {
        let base = (file.filename as NSString).deletingPathExtension
        var label = base.replacingOccurrences(
            of: "\\[[^\\]]*\\]",
            with: "",
            options: .regularExpression
        )
        let folder = GoogleFontFamily.folderName(for: family)
        if label.lowercased().hasPrefix(folder.lowercased()) {
            label = String(label.dropFirst(folder.count))
        }
        label = label.trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
        if label.isEmpty {
            return family.isVariable ? "Variable" : "Regular"
        }
        return label
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
                model.errorMessage = error.localizedDescription
            }
            downloading.remove(file.filename)
            progress.removeValue(forKey: file.filename)
        }
    }
}
