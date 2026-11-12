import Foundation

/// Fetches a tiny TTF subset from the Google Fonts CSS API for inline host
/// previews. This never touches the managed library or activation journal.
public actor GoogleFontPreviewService {
    public static let shared = GoogleFontPreviewService()

    private let cacheDirectory: URL
    private let maxCachedFiles = 400
    private var inFlight: [String: Task<URL?, Never>] = [:]

    public init(cacheDirectory: URL? = nil) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let caches = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.cacheDirectory = caches
                .appendingPathComponent("Ur Fonts", isDirectory: true)
                .appendingPathComponent("HostPreviews", isDirectory: true)
        }
    }

    /// Preview URL for the configured sample text. Returns nil when the API
    /// cannot provide a TrueType subset.
    public func previewURL(
        familyName: String,
        text: String,
        style: GoogleFontStyle? = nil
    ) async -> URL? {
        let sample = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return nil }
        let styleKey = style?.cssDescriptor ?? "family"
        let key = "\(familyName)\u{0}\(styleKey)\u{0}\(sample)"
        let directory = cacheDirectory
        let file = directory.appendingPathComponent(
            "\(Self.sanitize(familyName))-\(Self.hash(key)).ttf"
        )

        if FileManager.default.fileExists(atPath: file.path) {
            if let size = try? FileManager.default
                .attributesOfItem(atPath: file.path)[.size] as? NSNumber,
               size.intValue > 0 {
                return file
            }
            try? FileManager.default.removeItem(at: file)
        }

        if let task = inFlight[key] {
            return await task.value
        }
        let task = Task { [cacheDirectory] () -> URL? in
            await Self.fetch(
                familyName: familyName,
                style: style,
                text: sample,
                directory: cacheDirectory,
                file: file
            )
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if result != nil {
            trimCache()
        }
        return result
    }

    private func trimCache() {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ), files.count > maxCachedFiles else {
            return
        }
        let sorted = files.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return left < right
        }
        for url in sorted.prefix(files.count - maxCachedFiles) {
            try? manager.removeItem(at: url)
        }
    }

    private nonisolated static func fetch(
        familyName: String,
        style: GoogleFontStyle?,
        text: String,
        directory: URL,
        file: URL
    ) async -> URL? {
        guard var components = URLComponents(
            string: "https://fonts.googleapis.com/css2"
        ) else {
            return nil
        }
        let familyValue = style.map {
            "\(familyName):\($0.cssDescriptor)"
        } ?? familyName
        components.queryItems = [
            URLQueryItem(name: "family", value: familyValue),
            URLQueryItem(name: "text", value: text),
        ]
        guard let cssURL = components.url else { return nil }

        var request = URLRequest(url: cssURL)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (cssData, cssResponse) = try? await URLSession.shared.data(for: request),
              let http = cssResponse as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let css = String(data: cssData, encoding: .utf8),
              css.contains("format('truetype')"),
              let start = css.range(of: "src: url("),
              let end = css[start.upperBound...].firstIndex(of: ")") else {
            return nil
        }
        let raw = String(css[start.upperBound..<end])
        guard let url = URL(string: raw) else { return nil }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty else {
            return nil
        }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }

    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let cleaned = name.unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
        return cleaned.isEmpty ? "font" : String(cleaned.prefix(80))
    }

    private static func hash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
