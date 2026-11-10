import Foundation

public struct GoogleFontFile: Codable, Sendable, Equatable {
    public let path: String
    public let filename: String
}

public struct GoogleFontFamily: Codable, Sendable, Identifiable, Equatable {
    public let name: String
    public let category: String
    public let variants: [String]
    public let popularity: Int
    public let files: [GoogleFontFile]
    public let licensePath: String?

    public var id: String { name }
    public var isVariable: Bool { files.contains { $0.path.contains("[") } }

    public init(
        name: String,
        category: String,
        variants: [String],
        popularity: Int,
        files: [GoogleFontFile],
        licensePath: String?
    ) {
        self.name = name
        self.category = category
        self.variants = variants
        self.popularity = popularity
        self.files = files
        self.licensePath = licensePath
    }

    public static func folderName(for family: GoogleFontFamily) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let cleaned = family.name.unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? family.name : trimmed
    }
}

private struct GoogleFontCatalogCache: Codable {
    var generatedAt: Double
    var families: [GoogleFontFamily]
}

/// Fetches the Google Fonts catalog and font files from Google's public
/// metadata and the `google/fonts` GitHub repository. No API key.
public actor GoogleFontsService {
    public static let shared = GoogleFontsService()

    private let cacheDirectory: URL
    private var cachedFamilies: [GoogleFontFamily]?
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60

    public init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        cacheDirectory = base
            .appendingPathComponent("Ur Fonts", isDirectory: true)
            .appendingPathComponent("GoogleFonts", isDirectory: true)
    }

    public func catalog(forceRefresh: Bool = false) async throws -> [GoogleFontFamily] {
        if !forceRefresh, let cachedFamilies {
            return cachedFamilies
        }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let cacheURL = cacheDirectory.appendingPathComponent("catalog.json")
        if !forceRefresh,
           let data = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode(GoogleFontCatalogCache.self, from: data),
           Date().timeIntervalSince1970 - cache.generatedAt < maxCacheAge {
            cachedFamilies = cache.families
            return cache.families
        }

        async let metadataTask = fetchMetadata()
        async let treeTask = fetchTree()
        let metadata = try await metadataTask
        let tree = try await treeTask
        let families = Self.buildFamilies(metadata: metadata, tree: tree)
        let cache = GoogleFontCatalogCache(
            generatedAt: Date().timeIntervalSince1970,
            families: families
        )
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        cachedFamilies = families
        return families
    }

    /// Downloads requested TTF files for the family plus its license file.
    /// Returns local TTF URLs. Pass a file subset for per-font downloads.
    public func download(
        _ family: GoogleFontFamily,
        files requested: [GoogleFontFile]? = nil,
        to directory: URL,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [URL] {
        let files = requested ?? family.files
        guard !files.isEmpty else {
            throw GoogleFontsError.noFiles
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let licenseURL = directory.appendingPathComponent("LICENSE.txt")
        let needsLicense = family.licensePath != nil
            && !FileManager.default.fileExists(atPath: licenseURL.path)
        var localURLs: [URL] = []
        let total = files.count + (needsLicense ? 1 : 0)
        var done = 0

        for file in files {
            let url = try Self.rawURL(file.path)
            let (data, response) = try await URLSession.shared.data(from: url)
            try Self.validate(response)
            let destination = directory.appendingPathComponent(file.filename)
            try data.write(to: destination, options: .atomic)
            localURLs.append(destination)
            done += 1
            progress?(done, total)
        }

        if needsLicense, let licensePath = family.licensePath,
           let url = try? Self.rawURL(licensePath) {
            if let (data, response) = try? await URLSession.shared.data(from: url) {
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    try? data.write(to: licenseURL, options: .atomic)
                }
            }
            done += 1
            progress?(done, total)
        }
        return localURLs
    }

    // MARK: - Fetch

    private struct MetadataResponse: Decodable {
        struct Family: Decodable {
            struct Variant: Decodable {}
            let family: String
            let category: String?
            let popularity: Int?
            let fonts: [String: Variant]?
        }
        let familyMetadataList: [Family]
    }

    private struct TreeResponse: Decodable {
        struct Item: Decodable {
            let path: String
        }
        let tree: [Item]
    }

    private func fetchMetadata() async throws -> MetadataResponse {
        let url = URL(string: "https://fonts.google.com/metadata/fonts")!
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)

        let text = String(decoding: data, as: UTF8.self)
        let payload: String
        if text.hasPrefix(")]}'") {
            if let newline = text.firstIndex(of: "\n") {
                payload = String(text[text.index(after: newline)...])
            } else {
                payload = text
            }
        } else {
            payload = text
        }
        return try JSONDecoder().decode(MetadataResponse.self, from: Data(payload.utf8))
    }

    private func fetchTree() async throws -> TreeResponse {
        var components = URLComponents(
            string: "https://api.github.com/repos/google/fonts/git/trees/main"
        )!
        components.queryItems = [URLQueryItem(name: "recursive", value: "1")]
        var request = URLRequest(url: components.url!)
        request.setValue("UrFonts/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)
        return try JSONDecoder().decode(TreeResponse.self, from: data)
    }

    private static func buildFamilies(
        metadata: MetadataResponse,
        tree: TreeResponse
    ) -> [GoogleFontFamily] {
        var filesByDirectory: [String: [GoogleFontFile]] = [:]
        var licenseByDirectory: [String: String] = [:]

        for item in tree.tree {
            let parts = item.path.split(separator: "/")
            guard parts.count >= 3 else { continue }
            let directory = normalize(String(parts[1]))
            let filename = String(parts.last ?? "")
            let lower = filename.lowercased()

            if lower.hasSuffix(".ttf") {
                filesByDirectory[directory, default: []].append(
                    GoogleFontFile(path: item.path, filename: filename)
                )
            } else if lower.hasPrefix("ofl") || lower.hasPrefix("license")
                        || lower.hasPrefix("ufl") || lower.hasPrefix("apache") {
                if licenseByDirectory[directory] == nil {
                    licenseByDirectory[directory] = item.path
                }
            }
        }

        var seen = Set<String>()
        var families: [GoogleFontFamily] = []
        for family in metadata.familyMetadataList {
            guard seen.insert(family.family).inserted else { continue }
            let directory = normalize(family.family)
            var files = filesByDirectory[directory] ?? []
            if files.contains(where: { !$0.path.contains("/static/") }) {
                files.removeAll { $0.path.contains("/static/") }
            }
            files.sort { $0.filename < $1.filename }
            families.append(GoogleFontFamily(
                name: family.family,
                category: family.category ?? "Other",
                variants: (family.fonts ?? [:]).keys.sorted(),
                popularity: family.popularity ?? Int.max,
                files: files,
                licensePath: licenseByDirectory[directory]
            ))
        }
        return families.sorted {
            if $0.popularity != $1.popularity {
                return $0.popularity < $1.popularity
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func normalize(_ name: String) -> String {
        name.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func rawURL(_ path: String) throws -> URL {
        let escaped = path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let url = URL(string: "https://raw.githubusercontent.com/google/fonts/main/\(escaped)") else {
            throw GoogleFontsError.badURL
        }
        return url
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw GoogleFontsError.http(http.statusCode)
        }
    }
}

public enum GoogleFontsError: LocalizedError {
    case noFiles
    case badURL
    case http(Int)
    case notIndexed

    public var errorDescription: String? {
        switch self {
        case .noFiles: "This family has no downloadable files."
        case .badURL: "The Google Fonts file URL could not be built."
        case .http(let status): "Google Fonts returned HTTP \(status)."
        case .notIndexed: "The downloaded files could not be indexed."
        }
    }
}


