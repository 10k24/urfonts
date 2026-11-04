import CoreServices
import Foundation

/// Watches root folders with FSEvents and reports which roots changed.
///
/// Events are advisory: the scanner still compares stamps, so a duplicate event
/// costs one stat, not a parse. Missed events while the app is closed are
/// covered by the launch rescan and the periodic sweep.
public final class FolderWatcher: @unchecked Sendable {
    /// `(watched root as the library stores it, changed path under that root)`.
    public typealias Handler = @Sendable ([(root: String, path: String)]) -> Void

    private let queue = DispatchQueue(label: "com.10k24.urfonts.watcher")
    private let lock = NSLock()
    /// FSEvents reports canonical paths (`/private/var/...`), while the library
    /// stores what the user picked. Keep both forms.
    private var roots: [(original: String, resolved: String)] = []
    private var handler: Handler?
    private var stream: FSEventStreamRef?

    public init() {}

    public func start(roots: [String], handler: @escaping Handler) {
        stop()
        lock.lock()
        self.roots = roots.map {
            ($0, URL(fileURLWithPath: $0).resolvingSymlinksInPath().path)
        }
        self.handler = handler
        lock.unlock()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            folderWatcherCallback,
            &context,
            roots as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            flags
        ) else {
            return
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    fileprivate func receive(paths: [String]) {
        lock.lock()
        let roots = self.roots
        let handler = self.handler
        lock.unlock()
        guard let handler, !roots.isEmpty else { return }

        var changes: [(root: String, path: String)] = []
        var seen = Set<String>()
        for path in paths {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            for root in roots
            where resolved == root.resolved || resolved.hasPrefix(root.resolved + "/") {
                let suffix = resolved.dropFirst(root.resolved.count)
                let originalPath = root.original + suffix
                let key = root.original + "\u{0}" + originalPath
                guard seen.insert(key).inserted else { continue }
                changes.append((root.original, originalPath))
            }
        }
        if !changes.isEmpty {
            handler(changes)
        }
    }
}

private func folderWatcherCallback(
    _ stream: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] ?? []
    watcher.receive(paths: paths)
}
