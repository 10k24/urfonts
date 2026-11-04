import CoreText
import Foundation

/// A CTFont that is safe to hand across actor boundaries.
///
/// CoreText fonts are immutable once created; the wrapper only tells Swift that.
public struct LoadedFont: @unchecked Sendable {
    public let ctFont: CTFont
    public let postscriptName: String
}

/// Creates preview fonts straight from files, without registration.
///
/// Bounded LRU: a 23,000-font library must never have more than a viewport or
/// two of fonts resident. Previews are process-local; fontd is not involved.
public actor FontLoader {
    private struct Key: Hashable {
        let path: String
        let faceIndex: Int
    }

    /// One loader for the app. Actors are cheap; font descriptors are not.
    public static let shared = FontLoader()

    /// Preview size steps derive from this, never reload the file.
    public static let baseSize: CGFloat = 72

    private let capacity: Int
    private var cache: [Key: LoadedFont] = [:]
    private var order: [Key] = []
    private var descriptors: [String: [CTFontDescriptor]] = [:]

    public init(capacity: Int = 256) {
        self.capacity = capacity
    }

    /// One font per face. Point sizes are derived by the caller with
    /// `CTFontCreateCopyWithAttributes`, which never touches the file again.
    public func font(path: String, faceIndex: Int) -> LoadedFont? {
        let key = Key(path: path, faceIndex: faceIndex)
        if let existing = cache[key] {
            touch(key)
            return existing
        }

        let table = descriptors(for: path)
        guard faceIndex >= 0, faceIndex < table.count else { return nil }
        let ctFont = CTFontCreateWithFontDescriptor(table[faceIndex], Self.baseSize, nil)
        let name = CTFontCopyPostScriptName(ctFont) as String
        let loaded = LoadedFont(ctFont: ctFont, postscriptName: name)

        cache[key] = loaded
        order.append(key)
        if order.count > capacity {
            let evicted = order.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        return loaded
    }

    public func clear() {
        cache.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }

    private func touch(_ key: Key) {
        guard let index = order.firstIndex(of: key) else { return }
        order.remove(at: index)
        order.append(key)
    }

    /// Descriptor tables are cheap to keep and expensive to rebuild: parsing a
    /// TTC once serves every face and every point size in that file.
    private func descriptors(for path: String) -> [CTFontDescriptor] {
        if let cached = descriptors[path] { return cached }
        let url = URL(fileURLWithPath: path)
        let table = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
            as? [CTFontDescriptor] ?? []
        if descriptors.count > 512 {
            descriptors.removeAll(keepingCapacity: true)
        }
        descriptors[path] = table
        return table
    }
}
