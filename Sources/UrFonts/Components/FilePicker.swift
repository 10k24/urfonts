import AppKit
import UniformTypeIdentifiers

/// One app-wide open/save panel. Reusing the panel avoids the repeated remote
/// service startup cost and prevents a second picker from opening on a double
/// click or another Add Folder button.
@MainActor
final class FilePicker {
    static let shared = FilePicker()

    private lazy var openPanel: NSOpenPanel = {
        let panel = NSOpenPanel()
        panel.resolvesAliases = true
        return panel
    }()
    private lazy var savePanel: NSSavePanel = NSSavePanel()
    private var isOpen = false
    private var isSaving = false

    private init() {}

    func open(
        title: String,
        message: String,
        prompt: String,
        directories: Bool,
        multiple: Bool,
        types: [UTType] = [],
        completion: @escaping ([URL]) -> Void
    ) {
        if isOpen {
            openPanel.makeKeyAndOrderFront(nil)
            return
        }
        isOpen = true

        let panel = openPanel
        panel.title = title
        panel.message = message
        panel.prompt = prompt
        panel.canChooseDirectories = directories
        panel.canChooseFiles = !directories
        panel.allowsMultipleSelection = multiple
        panel.allowedContentTypes = directories ? [] : types
        panel.begin { [weak self] response in
            guard let self else { return }
            self.isOpen = false
            if response == .OK {
                completion(panel.urls)
            }
        }
    }

    func save(
        title: String,
        name: String,
        types: [UTType],
        completion: @escaping (URL) -> Void
    ) {
        if isSaving {
            savePanel.makeKeyAndOrderFront(nil)
            return
        }
        isSaving = true

        let panel = savePanel
        panel.title = title
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = types
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard let self else { return }
            self.isSaving = false
            if response == .OK, let url = panel.url {
                completion(url)
            }
        }
    }
}
