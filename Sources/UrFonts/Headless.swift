import AppKit
import Foundation
import SwiftUI

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
        case "detail":
            exit(detail())
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
