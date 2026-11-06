import AppKit
import Foundation
import SwiftUI
import UrFontsCore

/// Headless scenarios. Never activates the app, never takes focus.
///
/// Run as `UrFonts --headless [scenario]`. Exits with the number of failures as
/// the status. Artifacts go to the temporary directory.
enum Headless {
    static var isRequested: Bool {
        CommandLine.arguments.contains("--headless")
    }

    static func run() -> Never {
        let arguments = CommandLine.arguments
        let scenario: String
        if let index = arguments.firstIndex(of: "--headless"), index + 1 < arguments.count,
           !arguments[index + 1].hasPrefix("-") {
            scenario = arguments[index + 1]
        } else {
            scenario = "focus-check"
        }

        switch scenario {
        case "focus-check":
            exit(focusCheck())
        case "render":
            exit(render())
        case "list-spike":
            exit(ListSpike.run())
        case "browser":
            exit(browser())
        case "scroll":
            exit(browserScroll())
        case "detail":
            exit(detail())
        case "add-files":
            exit(addFiles())
        default:
            FileHandle.standardError.write(Data("unknown headless scenario: \(scenario)\n".utf8))
            exit(1)
        }
    }

    // MARK: - Scenarios

    private static func focusCheck() -> Int32 {
        let logger = Logger(name: "focus-check")
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()

        logger.check(app.activationPolicy() == .prohibited, "activation policy is prohibited")
        logger.check(!app.isActive, "process is not active after launch")
        logger.check(!NSRunningApplication.current.isActive, "running application is not active")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.setFrameOrigin(NSPoint(x: -12_000, y: -12_000))
        window.orderBack(nil)
        window.displayIfNeeded()

        logger.check(!app.isActive, "still not active after creating and backing a window")
        logger.check(!window.isKeyWindow, "window is not key")
        window.orderOut(nil)

        return logger.finish()
    }

    /// Renders the real browser in an offscreen window against whatever
    /// database `--db` points at. No focus, no screen recording permission.
    private static func browser() -> Int32 {
        let logger = Logger(name: "browser")
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()

        logger.check(!app.isActive, "process is not active")

        let model = AppModel()
        Task { @MainActor in
            await model.start()
        }

        let deadline = Date().addingTimeInterval(15)
        while model.isLoading, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        logger.check(!model.isLoading, "library loaded")

        if CommandLine.arguments.contains("--grid") {
            model.viewMode = .grid
        }
        if let index = CommandLine.arguments.firstIndex(of: "--query"),
           index + 1 < CommandLine.arguments.count {
            model.query = CommandLine.arguments[index + 1]
        }
        if let index = CommandLine.arguments.firstIndex(of: "--characters"),
           index + 1 < CommandLine.arguments.count {
            model.filter.characters = CommandLine.arguments[index + 1]
        }
        if CommandLine.arguments.contains("--hide-system") {
            model.setShowSystemFonts(false, persist: false)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--select-folder"),
           index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            if let folder = model.folders.first(where: {
                $0.path == path || $0.path.hasSuffix(path)
            }) {
                model.selection = .folder(folder.id)
            }
        }
        if CommandLine.arguments.contains("--warnings") {
            model.selection = .problems
            let problemsDeadline = Date().addingTimeInterval(10)
            while model.isLoadingProblems, Date() < problemsDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            logger.check(!model.isLoadingProblems, "problems loaded")
            print(
                "duplicates=\(model.duplicateCount) missing=\(model.missingFileCount)"
            )
        }
        if CommandLine.arguments.contains("--active") {
            model.selection = .active
        }
        if CommandLine.arguments.contains("--light") {
            model.backgroundColor = .white
            model.textColor = .black
        }
        if let index = CommandLine.arguments.firstIndex(of: "--preset"),
           index + 1 < CommandLine.arguments.count,
           let preset = PreviewPreset(rawValue: CommandLine.arguments[index + 1]),
           let text = preset.text {
            model.sampleText = text
        }
        if let index = CommandLine.arguments.firstIndex(of: "--size"),
           index + 1 < CommandLine.arguments.count,
           let size = Double(CommandLine.arguments[index + 1]) {
            model.sampleSize = size
        }
        if let index = CommandLine.arguments.firstIndex(of: "--script"),
           index + 1 < CommandLine.arguments.count,
           let value = UInt64(CommandLine.arguments[index + 1]),
           let script = FontScript(rawValue: value) {
            model.filter.script = script
        }
        print(
            "query=\(model.query) characters=\(model.filter.characters) "
                + "visible=\(model.visibleFamilies.count) "
                + "visibleFonts=\(model.visibleFontCount) "
                + "scopeFonts=\(model.selectionFontCount) "
                + "status=\(model.visibleStatus)"
        )
        if model.selection == .problems {
            logger.check(model.visibleStatus.contains("warning"), "status counts warnings")
        } else if model.selection == .active {
            logger.check(
                model.selectionFontCount == model.activeFaceIDs.count,
                "Active scope is every active font"
            )
            logger.check(
                model.visibleFontCount <= model.selectionFontCount,
                "visible fonts stay inside the scope"
            )
            logger.check(model.visibleStatus.contains("font"), "status counts fonts")
        } else {
            logger.check(model.selectionFontCount > 0, "scope has fonts")
            logger.check(
                model.visibleFontCount <= model.selectionFontCount,
                "visible fonts stay inside the scope"
            )
            if model.selection == .all {
                logger.check(
                    model.selectionFontCount == model.snapshot.faceCount,
                    "All Fonts scope is every font"
                )
            }
            logger.check(model.visibleStatus.contains("font"), "status counts fonts")
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1150, height: 740),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.orderBack(nil)
        window.displayIfNeeded()

        // Let rows appear and their preview fonts load.
        let settle = Date().addingTimeInterval(1.5)
        while Date() < settle {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        window.displayIfNeeded()

        logger.check(model.snapshot.familyCount > 0, "snapshot has families")
        logger.check(!app.isActive, "still not active after rendering")
        logger.check(!window.isKeyWindow, "window is not key")

        guard let content = window.contentView,
              let representation = content.bitmapImageRepForCachingDisplay(in: content.bounds)
        else {
            logger.check(false, "captured window content")
            window.orderOut(nil)
            return logger.finish()
        }
        content.cacheDisplay(in: content.bounds, to: representation)
        let name = model.viewMode == .grid ? "browser-grid.png" : "browser.png"
        if let png = representation.representation(using: .png, properties: [:]) {
            let url = logger.directory.appendingPathComponent(name)
            try? png.write(to: url)
            logger.check(FileManager.default.fileExists(atPath: url.path), "wrote \(name)")
        } else {
            logger.check(false, "encoded \(name)")
        }

        window.orderOut(nil)
        return logger.finish()
    }

    /// Adds real font files to a temporary database and checks that files in
    /// one directory create one folder row and that the faces reach the
    /// snapshot. Uses the production `AppModel.addFontFiles` path.
    private static func addFiles() -> Int32 {
        let logger = Logger(name: "add-files")
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()

        logger.check(!app.isActive, "process is not active")

        let extensions: Set<String> = ["ttf", "otf", "ttc", "otc", "dfont"]
        let paths = CommandLine.arguments.filter {
            extensions.contains(($0 as NSString).pathExtension.lowercased())
                && FileManager.default.fileExists(atPath: $0)
        }
        logger.check(paths.count >= 2, "found two font paths")
        guard paths.count >= 2 else {
            return logger.finish()
        }
        let urls = paths.prefix(2).map { URL(fileURLWithPath: $0) }

        let model = AppModel()
        Task { @MainActor in await model.start() }
        let deadline = Date().addingTimeInterval(15)
        while model.isLoading, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        logger.check(!model.isLoading, "library loaded")

        // Google Fonts sync runs after start and may add its managed folder.
        let settle = Date().addingTimeInterval(1)
        while Date() < settle {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let baselineFaces = model.snapshot.faceCount

        final class Flag {
            var done = false
        }
        let flag = Flag()
        Task { @MainActor in
            await model.addFontFiles(urls)
            flag.done = true
        }
        let addDeadline = Date().addingTimeInterval(15)
        while !flag.done, Date() < addDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        logger.check(flag.done, "add finished")

        logger.check(model.displayFolders.count == 1, "one user folder")
        if let folder = model.displayFolders.first {
            logger.check(
                folder.path == (urls[0].deletingLastPathComponent().path),
                "folder path is the parent directory"
            )
        }
        logger.check(
            model.snapshot.faceCount >= baselineFaces + 2,
            "fonts reached the snapshot"
        )
        let indexedPaths = Set(model.snapshot.faces.map(\.path))
        for url in urls {
            logger.check(indexedPaths.contains(url.path), "indexed \(url.lastPathComponent)")
        }
        if let folder = model.displayFolders.first {
            logger.check(
                model.folderFontCounts[folder.id] == 2,
                "folder counts two fonts"
            )
        }
        logger.check(!app.isActive, "still not active")

        return logger.finish()
    }

    /// Renders the family detail page, preferring a variable family so the axis
    /// controls and variation rendering are exercised.
    private static func detail() -> Int32 {
        let logger = Logger(name: "detail")
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()

        let model = AppModel()
        Task { @MainActor in await model.start() }
        let deadline = Date().addingTimeInterval(15)
        while model.isLoading, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        logger.check(!model.isLoading, "library loaded")

        guard let family = model.snapshot.families.first(where: { family in
            model.snapshot.faces(in: family).contains(where: \.isVariable)
        }) ?? model.snapshot.families.first else {
            logger.check(false, "found a family")
            return logger.finish()
        }
        logger.check(true, "family: \(family.name)")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 1180),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.contentView = NSHostingView(rootView: FamilyDetailView(model: model, family: family))
        window.orderBack(nil)
        window.displayIfNeeded()
        let settle = Date().addingTimeInterval(1.5)
        while Date() < settle {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        window.displayIfNeeded()

        logger.check(!app.isActive, "process is not active")

        guard let content = window.contentView,
              let representation = content.bitmapImageRepForCachingDisplay(in: content.bounds)
        else {
            logger.check(false, "captured detail")
            return logger.finish()
        }
        content.cacheDisplay(in: content.bounds, to: representation)
        if let png = representation.representation(using: .png, properties: [:]) {
            let url = logger.directory.appendingPathComponent("detail.png")
            try? png.write(to: url)
            logger.check(FileManager.default.fileExists(atPath: url.path), "wrote detail.png")
        }
        window.orderOut(nil)
        return logger.finish()
    }

    /// Drives the real browser list offscreen and reports per-step cost. Used to
    /// compare query/filter states without a display link.
    private static func browserScroll() -> Int32 {
        let logger = Logger(name: "scroll")
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()

        let model = AppModel()
        Task { @MainActor in await model.start() }
        let deadline = Date().addingTimeInterval(15)
        while model.isLoading, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        if let index = CommandLine.arguments.firstIndex(of: "--query"),
           index + 1 < CommandLine.arguments.count {
            model.query = CommandLine.arguments[index + 1]
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1150, height: 740),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.orderBack(nil)
        window.displayIfNeeded()

        let settle = Date().addingTimeInterval(1.5)
        while Date() < settle {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        guard let content = window.contentView,
              let scrollView = largestScrollView(in: content),
              let document = scrollView.documentView else {
            logger.check(false, "found browser scroll view")
            return logger.finish()
        }
        let clip = scrollView.contentView
        let maxY = max(0, document.frame.height - clip.bounds.height)
        func runPass() -> [TimeInterval] {
            var samples: [TimeInterval] = []
            let rowSteps = CommandLine.arguments.contains("--rows")
            let steps = rowSteps ? 200 : 120
            for step in 0..<steps {
                let y = rowSteps
                    ? min(maxY, CGFloat(step) * 128)
                    : maxY * CGFloat(step) / CGFloat(steps - 1)
                let started = CACurrentMediaTime()
                clip.scroll(to: NSPoint(x: 0, y: y))
                scrollView.reflectScrolledClipView(clip)
                content.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                RunLoop.current.run(until: Date())
                window.displayIfNeeded()
                samples.append(CACurrentMediaTime() - started)
            }
            return samples
        }

        func summarize(_ samples: [TimeInterval]) -> (Double, Double, Double) {
            let sorted = samples.sorted()
            let p50 = sorted[sorted.count / 2]
            let p99 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))]
            return (p50, p99, sorted.last ?? 0)
        }

        let first = summarize(runPass())
        let second = summarize(runPass())
        logger.check(
            second.1 < 0.016,
            String(
                format: "query=%@ families=%d pass1 p50=%.2f p99=%.2f max=%.2f | pass2 p50=%.2f p99=%.2f max=%.2f",
                model.query, model.visibleFamilies.count,
                first.0 * 1000, first.1 * 1000, first.2 * 1000,
                second.0 * 1000, second.1 * 1000, second.2 * 1000
            )
        )
        return logger.finish()
    }

    private static func largestScrollView(in view: NSView) -> NSScrollView? {
        var found: [NSScrollView] = []
        func walk(_ view: NSView) {
            if let scroll = view as? NSScrollView { found.append(scroll) }
            for child in view.subviews { walk(child) }
        }
        walk(view)
        return found.max { $0.frame.width < $1.frame.width }
    }

    private static func render() -> Int32 {
        let logger = Logger(name: "render")
        let renderer = ImageRenderer(content: ContentView())
        renderer.scale = 2
        guard let image = renderer.nsImage else {
            logger.check(false, "ImageRenderer produced an image")
            return logger.finish()
        }
        logger.check(image.size.width > 0 && image.size.height > 0, "image has size")

        if let tiff = image.tiffRepresentation,
           let representation = NSBitmapImageRep(data: tiff),
           let png = representation.representation(using: .png, properties: [:]) {
            let url = logger.directory.appendingPathComponent("render.png")
            try? png.write(to: url)
            logger.check(FileManager.default.fileExists(atPath: url.path), "wrote render.png")
        } else {
            logger.check(false, "encoded render.png")
        }
        return logger.finish()
    }

    // MARK: - Logging

    private final class Logger {
        let directory: URL
        private let handle: FileHandle?
        private var failures = 0

        init(name: String) {
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("urfonts-headless", isDirectory: true)
                .appendingPathComponent("\(stamp)-\(name)", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            directory = base

            let logURL = base.appendingPathComponent("run.log")
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            handle = try? FileHandle(forWritingTo: logURL)
            line("=== \(name) ===")
        }

        func check(_ passed: Bool, _ what: String) {
            if !passed { failures += 1 }
            line("\(passed ? "PASS" : "FAIL") \(what)")
        }

        func finish() -> Int32 {
            line("=== \(failures) failure(s) ===")
            handle?.closeFile()
            print("artifacts: \(directory.path)")
            return Int32(failures)
        }

        private func line(_ text: String) {
            print(text)
            handle?.write(Data((text + "\n").utf8))
        }
    }
}
