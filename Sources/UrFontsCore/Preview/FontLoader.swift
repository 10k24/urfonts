import CoreText
import Foundation

/// A CTFont that is safe to hand across actor boundaries.
///
/// CoreText fonts are immutable once created; the wrapper only tells Swift that.
public struct LoadedFont: @unchecked Sendable {
    public let ctFont: CTFont
}

/// Creates preview fonts straight from files, without registration.
///
/// Bounded LRU: a very large library must never have more than a viewport or
/// two of fonts resident. Previews are process-local; fontd is not involved.
public actor FontLoader {
    private struct Key: Hashable {
        let path: String
        let faceIndex: Int
        /// The face's PostScript name. CoreText exposes one descriptor per named
        /// variable instance, so the SFNT face index alone is not an identity.
        let postscriptName: String?
    }

    /// CoreText descriptors for one file. `ordered` keeps the raw table for
    /// callers that only have a face index; `byName` resolves the SFNT face by
    /// its PostScript name when named variable instances are present.
    private struct DescriptorTable {
        let ordered: [CTFontDescriptor]
        let byName: [String: CTFontDescriptor]
    }

    /// One loader for the app. Actors are cheap; font descriptors are not.
    public static let shared = FontLoader()

    /// Preview size steps derive from this, never reload the file.
    public static let baseSize: CGFloat = 72

    private let capacity: Int
    private var cache: [Key: LoadedFont] = [:]
    private var order: [Key] = []
    private var descriptors: [String: DescriptorTable] = [:]

    public init(capacity: Int = 256) {
        self.capacity = capacity
    }

    /// One font per face. Point sizes are derived by the caller with
    /// `CTFontCreateCopyWithAttributes`, which never touches the file again.
    ///
    /// `postscriptName` is the identity. A variable font can produce hundreds
    /// of descriptors for its named instances, so `faceIndex` is only a
    /// fallback for preview subsets that have no catalog face.
    public func font(
        path: String,
        faceIndex: Int,
        postscriptName: String? = nil
    ) -> LoadedFont? {
        let key = Key(path: path, faceIndex: faceIndex, postscriptName: postscriptName)
        if let existing = cache[key] {
            touch(key)
            return existing
        }

        let table = descriptors(for: path)
        let descriptor: CTFontDescriptor?
        if let postscriptName,
           let named = table.byName[postscriptName] {
            descriptor = named
        } else if faceIndex >= 0, faceIndex < table.ordered.count {
            descriptor = table.ordered[faceIndex]
        } else {
            descriptor = nil
        }
        guard let descriptor else { return nil }
        let ctFont = CTFontCreateWithFontDescriptor(descriptor, Self.baseSize, nil)
        let loaded = LoadedFont(ctFont: ctFont)

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

    /// Descriptor tables are cheap to keep and expensive to rebuild: reading one
    /// TTC serves every face and every point size in that file.
    private func descriptors(for path: String) -> DescriptorTable {
        if let cached = descriptors[path] { return cached }
        let url = URL(fileURLWithPath: path)
        let ordered = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
            as? [CTFontDescriptor] ?? []
        var byName: [String: CTFontDescriptor] = [:]
        byName.reserveCapacity(ordered.count)
        for descriptor in ordered {
            guard let name = CTFontDescriptorCopyAttribute(
                descriptor,
                kCTFontNameAttribute
            ) as? String, !name.isEmpty, byName[name] == nil else {
                continue
            }
            byName[name] = descriptor
        }
        let table = DescriptorTable(ordered: ordered, byName: byName)
        if descriptors.count > 512 {
            descriptors.removeAll(keepingCapacity: true)
        }
        descriptors[path] = table
        return table
    }
}
