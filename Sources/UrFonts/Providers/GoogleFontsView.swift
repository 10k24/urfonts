import SwiftUI
import UrFontsCore

struct GoogleFontsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var families: [GoogleFontFamily] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var downloading: Set<String> = []
    @State private var downloaded: Set<String> = []

    private var filtered: [GoogleFontFamily] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return families }
        return families.filter {
            $0.name.lowercased().contains(needle)
                || $0.category.lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Google Fonts")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh") {
                    Task { await load(forceRefresh: true) }
                }
                .disabled(isLoading)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            TextField("Search families or categories", text: $query)
                .textFieldStyle(.roundedBorder)

            if isLoading {
                ProgressView("Loading catalog…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText {
                ContentUnavailableView {
                    Label("Could not load Google Fonts", systemImage: "globe")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("Retry") { Task { await load(forceRefresh: true) } }
                }
            } else {
                Text("\(filtered.count) families")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                List(filtered) { family in
                    row(for: family)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(width: 760, height: 620)
        .task {
            await load(forceRefresh: false)
        }
    }

    private func row(for family: GoogleFontFamily) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(family.name)
                    .font(.system(size: 13, weight: .medium))
                Text("\(family.category) · \(family.variants.count) variants\(family.isVariable ? " · variable" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if family.files.isEmpty {
                Text("Unavailable")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if downloaded.contains(GoogleFontFamily.folderName(for: family)) {
                Label("Downloaded", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if downloading.contains(family.name) {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Download") {
                    download(family)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private func load(forceRefresh: Bool) async {
        isLoading = true
        errorText = nil
        do {
            families = try await model.googleFontCatalog(forceRefresh: forceRefresh)
            downloaded = model.downloadedGoogleFamilies()
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }

    private func download(_ family: GoogleFontFamily) {
        downloading.insert(family.name)
        Task { @MainActor in
            do {
                try await model.downloadGoogleFont(family)
                downloaded.insert(GoogleFontFamily.folderName(for: family))
            } catch {
                model.errorMessage = error.localizedDescription
            }
            downloading.remove(family.name)
        }
    }
}
