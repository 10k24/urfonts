import AppKit
import CoreText
import Darwin
import SwiftUI

/// Phase 0: which container can carry a very large library?
///
/// Both variants render the same rows at a fixed height and draw one CoreText
/// line per row. The driver scrolls a real scroll view in an offscreen window
/// and measures layout plus display per step. It never activates the app.
///
/// This is a spike, not the browser. Delete it once the container is chosen and
/// the real browser owns the measurement.
enum ListSpike {
    static let rowCount = 5_750      // four styles per family
    static let rowHeight: CGFloat = 64
    static let viewport = NSSize(width: 1000, height: 700)

    struct Row: Identifiable, Equatable {
        let id: Int
        let name: String
        let styles: Int

        static let all: [Row] = (0..<ListSpike.rowCount).map { index in
            Row(
                id: index,
                name: String(format: "Fixture Family %05d", index + 1),
                styles: 4
            )
        }
    }

    @MainActor
    static func run() -> Int32 {
        let logger = SpikeLog(name: "list-spike")
        let rows = Row.all

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: viewport),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)

        logger.line("rows \(rows.count), row height \(Int(rowHeight))")

        let lazy = measure(
            name: "swiftui-lazyvstack",
            logger: logger,
            window: window
        ) { host in
            let hosting = NSHostingView(rootView: LazySpikeView(rows: rows))
            host.addSubview(hosting)
            hosting.frame = host.bounds
            hosting.autoresizingMask = [.width, .height]
        }

        let table = measure(
            name: "nstableview",
            logger: logger,
            window: window
        ) { host in
            let controller = SpikeTableController(rows: rows)
            host.spikeController = controller
            let scrollView = controller.makeScrollView(frame: host.bounds)
            host.addSubview(scrollView)
            scrollView.frame = host.bounds
            scrollView.autoresizingMask = [.width, .height]
        }

        logger.line("")
        logger.line("result")
        logger.line("  lazyvstack rows made \(lazy.rowsMade), draws \(lazy.draws)")
        logger.line("  nstableview rows made \(table.rowsMade), draws \(table.draws)")
        logger.line("  lazyvstack p99 \(milliseconds(lazy.p99)) ms, max \(milliseconds(lazy.max)) ms")
        logger.line("  nstableview p99 \(milliseconds(table.p99)) ms, max \(milliseconds(table.max)) ms")
        logger.line("  lazyvstack rss delta \(lazy.rssDelta / 1_000_000) MB")
        logger.line("  nstableview rss delta \(table.rssDelta / 1_000_000) MB")

        let winner = lazy.p99 <= table.p99 ? "swiftui-lazyvstack" : "nstableview"
        logger.line("chosen: \(winner)")

        window.orderOut(nil)
        return logger.finish()
    }

    // MARK: - Measurement

    private struct Result {
        let p99: TimeInterval
        let max: TimeInterval
        let rssDelta: UInt64
        let rowsMade: Int
        let draws: Int
    }

    @MainActor
    private static func measure(
        name: String,
        logger: SpikeLog,
        window: NSWindow,
        build: (SpikeHost) -> Void
    ) -> Result {
        let host = SpikeHost(frame: NSRect(origin: .zero, size: viewport))
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        SpikeCounters.reset()
        let before = residentBytes()
        let mounted = CACurrentMediaTime()
        build(host)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let mountTime = CACurrentMediaTime() - mounted
        // SwiftUI mounts on a run-loop turn. The window is offscreen and the
        // process cannot become active, so this cannot take focus.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        window.displayIfNeeded()

        guard let scrollView = findScrollView(host),
              let documentView = scrollView.documentView else {
            logger.line("\(name): no scroll view found")
            return Result(
                p99: .infinity,
                max: .infinity,
                rssDelta: 0,
                rowsMade: SpikeCounters.rowsMade,
                draws: SpikeCounters.draws
            )
        }
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = false
        let maxY = max(0, documentView.frame.height - clip.bounds.height)

        var samples: [TimeInterval] = []
        let steps = 60
        for step in 0..<steps {
            let y = maxY * CGFloat(step) / CGFloat(steps - 1)
            let started = CACurrentMediaTime()
            clip.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(clip)
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            // Let SwiftUI flush the scroll update inside the measured window,
            // so its cost is not moved outside the sample.
            RunLoop.current.run(until: Date())
            window.displayIfNeeded()
            samples.append(CACurrentMediaTime() - started)
        }

        let after = residentBytes()
        let sorted = samples.sorted()
        let p99 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))]
        let maxTime = sorted.last ?? 0

        logger.line(String(
            format: "%@: mount %.0f ms, p50 %.2f ms, p99 %.2f ms, max %.2f ms, rows made %d, draws %d",
            name, mountTime * 1000,
            sorted[sorted.count / 2] * 1000, p99 * 1000, maxTime * 1000,
            SpikeCounters.rowsMade, SpikeCounters.draws
        ))
        return Result(
            p99: p99,
            max: maxTime,
            rssDelta: after > before ? after - before : 0,
            rowsMade: SpikeCounters.rowsMade,
            draws: SpikeCounters.draws
        )
    }

    private static func milliseconds(_ interval: TimeInterval) -> String {
        String(format: "%.2f", interval * 1000)
    }

    private static func findScrollView(_ view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for child in view.subviews {
            if let found = findScrollView(child) { return found }
        }
        return nil
    }

    private static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.resident_size : 0
    }
}

/// Keeps the table controller alive for the duration of the measurement.
@MainActor
private final class SpikeHost: NSView {
    var spikeController: SpikeTableController?
}

/// Proves virtualization: rows made should stay near the viewport, not the
/// library size, and draws should stay near the rows actually shown.
@MainActor
private enum SpikeCounters {
    static var rowsMade = 0
    static var draws = 0

    static func reset() {
        rowsMade = 0
        draws = 0
    }
}

// MARK: - SwiftUI variant

private struct LazySpikeView: View {
    let rows: [ListSpike.Row]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    LazySpikeRow(row: row)
                        .equatable()
                        .frame(height: ListSpike.rowHeight)
                }
            }
        }
    }
}

private struct LazySpikeRow: View, Equatable {
    let row: ListSpike.Row

    init(row: ListSpike.Row) {
        self.row = row
        SpikeCounters.rowsMade += 1
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(row.name)
                .frame(width: 260, alignment: .leading)
            Canvas { context, size in
                context.withCGContext { cg in
                    drawSample(in: cg, size: size)
                }
            }
            Text("\(row.styles) styles")
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func drawSample(in context: CGContext, size: CGSize) {
        SpikeCounters.draws += 1
        let font = CTFontCreateWithName("Helvetica" as CFString, 22, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: row.name, attributes: attributes)
        )
        context.textPosition = CGPoint(x: 0, y: size.height / 2 - 6)
        CTLineDraw(line, context)
    }
}

// MARK: - AppKit variant

@MainActor
private final class SpikeTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let rows: [ListSpike.Row]

    init(rows: [ListSpike.Row]) {
        self.rows = rows
    }

    func makeScrollView(frame: NSRect) -> NSScrollView {
        let table = NSTableView()
        table.style = .plain
        table.rowHeight = ListSpike.rowHeight
        table.headerView = nil
        table.usesAlternatingRowBackgroundColors = false
        table.intercellSpacing = .zero
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        column.width = frame.width
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self

        let scrollView = NSScrollView(frame: frame)
        scrollView.hasVerticalScroller = true
        scrollView.documentView = table
        return scrollView
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("row")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? SpikeTableCell
            ?? SpikeTableCell()
        cell.identifier = identifier
        cell.configure(rows[row])
        return cell
    }
}

@MainActor
private final class SpikeTableCell: NSTableCellView {
    private var row: ListSpike.Row?

    func configure(_ row: ListSpike.Row) {
        self.row = row
        SpikeCounters.rowsMade += 1
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let row else { return }
        SpikeCounters.draws += 1
        let font = CTFontCreateWithName("Helvetica" as CFString, 22, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: row.name, attributes: attributes)
        )
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.textPosition = CGPoint(x: 8, y: bounds.midY - 6)
        CTLineDraw(line, context)
    }
}

// MARK: - Logging

@MainActor
private final class SpikeLog {
    let directory: URL
    private let handle: FileHandle?

    init(name: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("urfonts-headless", isDirectory: true)
            .appendingPathComponent("\(stamp)-\(name)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        directory = base
        let url = base.appendingPathComponent("run.log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        line("=== \(name) ===")
    }

    func line(_ text: String) {
        print(text)
        handle?.write(Data((text + "\n").utf8))
    }

    func finish() -> Int32 {
        handle?.closeFile()
        print("artifacts: \(directory.path)")
        return 0
    }
}
