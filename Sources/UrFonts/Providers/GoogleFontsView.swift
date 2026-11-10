import SwiftUI
import UrFontsCore

struct GoogleFontsView: View {
    @Bindable var model: AppModel

    @State private var families: [GoogleFontFamily] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var downloading: Set<String> = []
    @State private var progress: [String: Double] = [:]
    @State private var detail: GoogleFontFamily?

    private var filtered: [GoogleFontFamily] {
        let needle = model.query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !needle.isEmpty else { return families }
        return families.filter {
            $0.name.lowercased().contains(needle)
                || $0.category.lowercased().contains(needle)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading catalog…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText {
                ContentUnavailableView {
                    Label("Could not load Google Fonts", systemImage: "globe")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("Retry") { model.googleRefreshRequest &+= 1 }
                }
            } else if filtered.isEmpty {
                if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView {
                        Label("No Google Fonts", systemImage: "globe")
                    }
                } else {
                    ContentUnavailableView.search(text: model.query)
                }
            } else {
                switch model.viewMode {
                case .list:
                    list
                case .grid:
                    grid
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: model.googleRefreshRequest) {
            await load(forceRefresh: model.googleRefreshRequest > 0)
        }
        .sheet(item: $detail) { family in
            GoogleFontDetailView(model: model, family: family)
        }
    }

    private var list: some View {
        GeometryReader { proxy in
            let rowHeight = model.previewRowHeight(
                previewWidth: PreviewMetrics.listPreviewWidth(for: proxy.size.width)
            )
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { family in
                        GoogleFamilyListRow(
                            model: model,
                            family: family,
                            control: controlPhase(for: family),
                            rowHeight: rowHeight,
                            onToggle: { toggle(family) },
                            onOpen: { detail = family }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var grid: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: FamilyGridLayout.columns(for: proxy.size.width),
                    spacing: 12
                ) {
                    ForEach(filtered) { family in
                        GoogleFamilyTile(
                            model: model,
                            family: family,
                            control: controlPhase(for: family),
                            onToggle: { toggle(family) },
                            onOpen: { detail = family }
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    private func controlPhase(for family: GoogleFontFamily) -> HostControlPhase {
        guard !family.files.isEmpty else { return .unavailable }
        let folder = GoogleFontFamily.folderName(for: family)
        if downloading.contains(folder) {
            return .downloading(progress: progress[folder])
        }
        if !model.googleAllFilesDownloaded(family) {
            return .download
        }
        return .family(model.googleFamilyActivation(family))
    }

    private func load(forceRefresh: Bool) async {
        isLoading = true
        errorText = nil
        do {
            families = try await model.googleFontCatalog(forceRefresh: forceRefresh)
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }

    private func toggle(_ family: GoogleFontFamily) {
        let folder = GoogleFontFamily.folderName(for: family)
        guard !downloading.contains(folder) else { return }
        downloading.insert(folder)
        progress[folder] = nil
        Task { @MainActor in
            do {
                try await model.toggleGoogleFamily(family) { done, total in
                    Task { @MainActor in
                        progress[folder] = total > 0
                            ? Double(done) / Double(total)
                            : nil
                    }
                }
            } catch {
                model.errorMessage = error.localizedDescription
            }
            downloading.remove(folder)
            progress.removeValue(forKey: folder)
        }
    }
}

private struct GoogleFamilyListRow: View {
    @Bindable var model: AppModel
    let family: GoogleFontFamily
    let control: HostControlPhase
    let rowHeight: CGFloat
    let onToggle: () -> Void
    let onOpen: () -> Void

    @State private var previewURL: URL?

    private var downloadedFace: CatalogFace? {
        model.googleFamilyPreviewFace(family)
    }

    private var preview: PreviewSource? {
        if let face = downloadedFace {
            return PreviewSource(face: face)
        }
        guard let previewURL else { return nil }
        return PreviewSource(path: previewURL.path)
    }

    var body: some View {
        FamilyRow(
            display: FamilyDisplay(google: family),
            preview: preview,
            sampleText: model.sampleText,
            sampleSize: model.sampleSize,
            textColor: model.textColor,
            backgroundColor: model.backgroundColor,
            control: control,
            onToggle: onToggle,
            maxLines: model.previewMaxLines,
            rowHeight: rowHeight
        )
        .equatable()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .task(id: previewKey) {
            await loadPreview()
        }
    }

    private var previewKey: String {
        "\(family.name)\u{0}\(model.sampleText)\u{0}\(downloadedFace?.id ?? "")"
    }

    private func loadPreview() async {
        guard !family.files.isEmpty, downloadedFace == nil else {
            previewURL = nil
            return
        }
        previewURL = await model.googlePreviewURL(
            family: family,
            text: model.sampleText
        )
    }
}

private struct GoogleFamilyTile: View {
    @Bindable var model: AppModel
    let family: GoogleFontFamily
    let control: HostControlPhase
    let onToggle: () -> Void
    let onOpen: () -> Void

    @State private var previewURL: URL?

    private var downloadedFace: CatalogFace? {
        model.googleFamilyPreviewFace(family)
    }

    private var preview: PreviewSource? {
        if let face = downloadedFace {
            return PreviewSource(face: face)
        }
        guard let previewURL else { return nil }
        return PreviewSource(path: previewURL.path)
    }

    var body: some View {
        FamilyTile(
            display: FamilyDisplay(google: family),
            preview: preview,
            sampleText: model.sampleText,
            sampleSize: model.sampleSize,
            textColor: model.textColor,
            backgroundColor: model.backgroundColor,
            control: control,
            onToggle: onToggle
        )
        .equatable()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .task(id: previewKey) {
            await loadPreview()
        }
    }

    private var previewKey: String {
        "\(family.name)\u{0}\(model.sampleText)\u{0}\(downloadedFace?.id ?? "")"
    }

    private func loadPreview() async {
        guard !family.files.isEmpty, downloadedFace == nil else {
            previewURL = nil
            return
        }
        previewURL = await model.googlePreviewURL(
            family: family,
            text: model.sampleText
        )
    }
}
