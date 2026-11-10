import AppKit
import SwiftUI
import UrFontsCore

/// Library health: duplicate PostScript names and files that are missing or no
/// longer readable. Warning types stay collapsed so the page reads as a summary;
/// expand one to inspect its files. Only explicit cleanup changes the library.
struct ProblemsView: View {
    @Bindable var model: AppModel
    @State private var duplicatesExpanded = false
    @State private var missingExpanded = false
    @State private var confirmRemoveMissing = false

    var body: some View {
        Group {
            if model.isLoadingProblems {
                ProgressView("Checking the library…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.problemCount == 0 {
                ContentUnavailableView {
                    Label("No warnings", systemImage: "checkmark.seal")
                } description: {
                    Text("No duplicate PostScript names and no missing files.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !model.duplicates.isEmpty {
                        DisclosureGroup(isExpanded: $duplicatesExpanded) {
                            Text("These files share a PostScript name. Activating both "
                                + "can make apps use only one of them. Trial fonts with "
                                + "placeholder names such as \"false\" appear here too.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)

                            ForEach(model.duplicates) { duplicate in
                                duplicateRow(duplicate)
                            }
                        } label: {
                            warningLabel(
                                title: "Duplicate PostScript names",
                                detail: "More than one file claims the same name",
                                systemImage: "doc.on.doc",
                                count: model.duplicates.count
                            )
                            .contextMenu {
                                Button("Copy All Duplicate Warnings") {
                                    copy(
                                        model.duplicates
                                            .map(duplicateMessage)
                                            .joined(separator: "\n\n")
                                    )
                                }
                            }
                        }
                    }

                    if !model.problemFiles.isEmpty {
                        DisclosureGroup(isExpanded: $missingExpanded) {
                            Text("These files were moved, deleted, or cannot be read. "
                                + "Their entries stay until you remove them.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)

                            Button("Remove \(model.problemFiles.count) Missing "
                                + "\(model.problemFiles.count == 1 ? "Entry" : "Entries")…",
                                role: .destructive) {
                                confirmRemoveMissing = true
                            }
                            .padding(.vertical, 2)

                            ForEach(model.problemFiles) { file in
                                problemRow(file)
                            }
                        } label: {
                            warningLabel(
                                title: "Missing or unreadable files",
                                detail: "Files no longer available on disk",
                                systemImage: "questionmark.folder",
                                count: model.problemFiles.count
                            )
                            .contextMenu {
                                Button("Copy All Missing Warnings") {
                                    copy(
                                        model.problemFiles
                                            .map(problemMessage)
                                            .joined(separator: "\n\n")
                                    )
                                }
                                Button("Remove Missing Entries…", role: .destructive) {
                                    confirmRemoveMissing = true
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog(
            "Remove \(model.problemFiles.count) missing "
                + "\(model.problemFiles.count == 1 ? "entry" : "entries")?",
            isPresented: $confirmRemoveMissing,
            titleVisibility: .visible
        ) {
            Button("Remove Missing Entries", role: .destructive) {
                Task { await model.removeMissingFiles() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removed fonts also leave their collections. No files on disk "
                + "are touched. A later scan adds the font back if the file returns.")
        }
    }

    private func warningLabel(
        title: String,
        detail: String,
        systemImage: String,
        count: Int
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func duplicateRow(_ duplicate: DuplicatePostScriptName) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(duplicate.name)
                .font(.system(size: 13, weight: .medium))
            ForEach(duplicate.paths, id: \.self) { path in
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .contextMenu {
                        Button("Copy Warning") { copy(duplicateMessage(duplicate)) }
                        Button("Reveal in Finder") { model.revealPath(path) }
                        copyPathButton(path)
                    }
            }
        }
        .padding(.vertical, 3)
        .padding(.leading, 28)
        .contextMenu {
            Button("Copy Warning") { copy(duplicateMessage(duplicate)) }
        }
    }

    private func problemRow(_ file: ProblemFile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(file.familyName ?? (file.path as NSString).lastPathComponent)
                .font(.system(size: 13, weight: .medium))
            Text(file.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(file.status == "missing" ? "Missing" : file.status.capitalized)
                .font(.caption2)
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 2)
        .padding(.leading, 28)
        .contextMenu {
            Button("Copy Warning") { copy(problemMessage(file)) }
            Button("Reveal in Finder") { model.revealPath(file.path) }
            copyPathButton(file.path)
        }
    }

    private func duplicateMessage(_ duplicate: DuplicatePostScriptName) -> String {
        (["Duplicate PostScript name: \(duplicate.name)"] + duplicate.paths)
            .joined(separator: "\n")
    }

    private func problemMessage(_ file: ProblemFile) -> String {
        let label = file.familyName ?? (file.path as NSString).lastPathComponent
        let status = file.status == "missing" ? "Missing" : "Unreadable"
        return "\(status): \(label)\n\(file.path)"
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyPathButton(_ path: String) -> some View {
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
    }
}
