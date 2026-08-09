import CryptoKit
import Foundation

public struct RepositoryCoverCacheMetadata: Equatable, Codable, Sendable {
    public let contentType: String?
    public let storedAt: Date
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let sourceURL: URL?
    public let contentHash: String?
    public let etag: String?
    public let lastModified: String?
    public let needsRefresh: Bool

    public init(
        contentType: String?,
        storedAt: Date,
        pixelWidth: Int?,
        pixelHeight: Int?,
        sourceURL: URL? = nil,
        contentHash: String? = nil,
        etag: String? = nil,
        lastModified: String? = nil,
        needsRefresh: Bool = false
    ) {
        self.contentType = contentType
        self.storedAt = storedAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sourceURL = sourceURL
        self.contentHash = contentHash
        self.etag = etag
        self.lastModified = lastModified
        self.needsRefresh = needsRefresh
    }

    private enum CodingKeys: String, CodingKey {
        case contentType
        case storedAt
        case pixelWidth
        case pixelHeight
        case sourceURL
        case contentHash
        case etag
        case lastModified
        case needsRefresh
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        contentType = try values.decodeIfPresent(
            String.self,
            forKey: .contentType
        )
        storedAt = try values.decode(Date.self, forKey: .storedAt)
        pixelWidth = try values.decodeIfPresent(
            Int.self,
            forKey: .pixelWidth
        )
        pixelHeight = try values.decodeIfPresent(
            Int.self,
            forKey: .pixelHeight
        )
        sourceURL = try values.decodeIfPresent(URL.self, forKey: .sourceURL)
        contentHash = try values.decodeIfPresent(
            String.self,
            forKey: .contentHash
        )
        etag = try values.decodeIfPresent(String.self, forKey: .etag)
        lastModified = try values.decodeIfPresent(
            String.self,
            forKey: .lastModified
        )
        needsRefresh = try values.decodeIfPresent(
            Bool.self,
            forKey: .needsRefresh
        ) ?? false
    }
}

public struct RepositoryCoverCacheEntry: Equatable, Sendable {
    public let data: Data
    public let metadata: RepositoryCoverCacheMetadata

    public init(data: Data, metadata: RepositoryCoverCacheMetadata) {
        self.data = data
        self.metadata = metadata
    }
}

public protocol RepositoryCoverCaching: Sendable {
    func load(
        repositoryID: Int64,
        sourceURL: URL
    ) throws -> RepositoryCoverCacheEntry?

    func save(
        data: Data,
        metadata: RepositoryCoverCacheMetadata,
        repositoryID: Int64,
        sourceURL: URL
    ) throws

    func latest(repositoryID: Int64) throws -> RepositoryCoverCacheEntry?
    func markNeedsRefresh(repositoryIDs: Set<Int64>) throws
    func clear(repositoryID: Int64) throws
}

public extension RepositoryCoverCaching {
    func latest(repositoryID: Int64) throws -> RepositoryCoverCacheEntry? {
        nil
    }

    func markNeedsRefresh(repositoryIDs: Set<Int64>) throws {}
}

public enum RepositoryCoverCacheError: Error, Equatable, Sendable {
    case invalidSourceURL
}

public final class RepositoryCoverCache: RepositoryCoverCaching, @unchecked Sendable {
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        rootDirectory: URL = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
        .appending(path: "GitMate", directoryHint: .isDirectory),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public func load(
        repositoryID: Int64,
        sourceURL: URL
    ) throws -> RepositoryCoverCacheEntry? {
        lock.lock()
        defer { lock.unlock() }

        return try loadUnlocked(
            repositoryID: repositoryID,
            sourceURL: sourceURL
        )
    }

    public func save(
        data: Data,
        metadata: RepositoryCoverCacheMetadata,
        repositoryID: Int64,
        sourceURL: URL
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        try saveUnlocked(
            data: data,
            metadata: normalizedMetadata(
                metadata,
                data: data,
                sourceURL: sourceURL
            ),
            repositoryID: repositoryID,
            sourceURL: sourceURL
        )
    }

    public func latest(
        repositoryID: Int64
    ) throws -> RepositoryCoverCacheEntry? {
        lock.lock()
        defer { lock.unlock() }
        let pointerURL = repositoryDirectory(repositoryID)
            .appending(path: "latest.json")
        guard let data = try? Data(contentsOf: pointerURL),
              let pointer = try? JSONDecoder().decode(
                  LatestCoverPointer.self,
                  from: data
              )
        else {
            return nil
        }
        return loadEntryUnlocked(
            entryRoot: repositoryDirectory(repositoryID)
                .appending(
                    path: pointer.entryHash,
                    directoryHint: .isDirectory
                )
        )
    }

    public func markNeedsRefresh(
        repositoryIDs: Set<Int64>
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        for repositoryID in repositoryIDs {
            let pointerURL = repositoryDirectory(repositoryID)
                .appending(path: "latest.json")
            guard let pointerData = try? Data(contentsOf: pointerURL),
                  let pointer = try? JSONDecoder().decode(
                      LatestCoverPointer.self,
                      from: pointerData
                  ),
                  let entry = loadEntryUnlocked(
                      entryRoot: repositoryDirectory(repositoryID)
                          .appending(
                              path: pointer.entryHash,
                              directoryHint: .isDirectory
                          )
                  )
            else {
                continue
            }
            let metadata = RepositoryCoverCacheMetadata(
                contentType: entry.metadata.contentType,
                storedAt: entry.metadata.storedAt,
                pixelWidth: entry.metadata.pixelWidth,
                pixelHeight: entry.metadata.pixelHeight,
                sourceURL: pointer.sourceURL,
                contentHash: entry.metadata.contentHash,
                etag: entry.metadata.etag,
                lastModified: entry.metadata.lastModified,
                needsRefresh: true
            )
            try saveEntryUnlocked(
                data: entry.data,
                metadata: metadata,
                entryRoot: repositoryDirectory(repositoryID)
                    .appending(
                        path: pointer.entryHash,
                        directoryHint: .isDirectory
                    ),
                latestPointerURL: pointerURL,
                latestPointer: pointer
            )
        }
    }

    private func loadUnlocked(
        repositoryID: Int64,
        sourceURL: URL
    ) throws -> RepositoryCoverCacheEntry? {
        let entryRoot = try cacheEntryRoot(
            repositoryID: repositoryID,
            sourceURL: sourceURL
        )
        return loadEntryUnlocked(entryRoot: entryRoot)
    }

    private func loadEntryUnlocked(
        entryRoot: URL
    ) -> RepositoryCoverCacheEntry? {
        let currentURL = entryRoot.appending(path: "current")
        guard fileManager.fileExists(atPath: currentURL.path),
              let generation = try? String(
                contentsOf: currentURL,
                encoding: .utf8
              ),
              UUID(uuidString: generation) != nil
        else {
            return nil
        }
        let dataURL = entryRoot.appending(path: "\(generation).data")
        let metadataURL = entryRoot.appending(path: "\(generation).json")
        guard fileManager.fileExists(atPath: dataURL.path),
              fileManager.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: dataURL),
              let storedMetadata = try? JSONDecoder().decode(
                StoredCoverMetadata.self,
                from: Data(contentsOf: metadataURL)
              ),
              storedMetadata.generation == generation
        else {
            return nil
        }
        return RepositoryCoverCacheEntry(
            data: data,
            metadata: storedMetadata.metadata
        )
    }

    private func saveUnlocked(
        data: Data,
        metadata: RepositoryCoverCacheMetadata,
        repositoryID: Int64,
        sourceURL: URL
    ) throws {
        let entryRoot = try cacheEntryRoot(
            repositoryID: repositoryID,
            sourceURL: sourceURL
        )
        let safeSourceURL = sanitizedSourceURL(sourceURL)
        let pointer = LatestCoverPointer(
            sourceURL: safeSourceURL,
            entryHash: entryRoot.lastPathComponent
        )
        try saveEntryUnlocked(
            data: data,
            metadata: metadata,
            entryRoot: entryRoot,
            latestPointerURL: repositoryDirectory(repositoryID)
                .appending(path: "latest.json"),
            latestPointer: pointer
        )
    }

    private func saveEntryUnlocked(
        data: Data,
        metadata: RepositoryCoverCacheMetadata,
        entryRoot: URL,
        latestPointerURL: URL,
        latestPointer: LatestCoverPointer
    ) throws {
        try fileManager.createDirectory(
            at: entryRoot,
            withIntermediateDirectories: true
        )
        let generation = UUID().uuidString
        try data.write(
            to: entryRoot.appending(path: "\(generation).data"),
            options: .atomic
        )
        try JSONEncoder().encode(
            StoredCoverMetadata(
                generation: generation,
                metadata: metadata
            )
        ).write(
            to: entryRoot.appending(path: "\(generation).json"),
            options: .atomic
        )
        try Data(generation.utf8).write(
            to: entryRoot.appending(path: "current"),
            options: .atomic
        )
        try JSONEncoder().encode(
            latestPointer
        ).write(to: latestPointerURL, options: .atomic)
    }

    public func clear(repositoryID: Int64) throws {
        lock.lock()
        defer { lock.unlock() }

        let directory = repositoryDirectory(repositoryID)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    private func cacheEntryRoot(
        repositoryID: Int64,
        sourceURL: URL
    ) throws -> URL {
        guard READMEURLPolicy.resolvedRemoteURL(
            sourceURL.absoluteString,
            baseURL: nil
        ) != nil
        else {
            throw RepositoryCoverCacheError.invalidSourceURL
        }
        let hash = stableHash(sourceURL.absoluteString)
        return repositoryDirectory(repositoryID)
            .appending(path: hash, directoryHint: .isDirectory)
    }

    private func repositoryDirectory(_ repositoryID: Int64) -> URL {
        rootDirectory
            .appending(path: "Covers", directoryHint: .isDirectory)
            .appending(
                path: String(repositoryID),
                directoryHint: .isDirectory
            )
    }

    private func normalizedMetadata(
        _ metadata: RepositoryCoverCacheMetadata,
        data: Data,
        sourceURL: URL
    ) -> RepositoryCoverCacheMetadata {
        RepositoryCoverCacheMetadata(
            contentType: metadata.contentType,
            storedAt: metadata.storedAt,
            pixelWidth: metadata.pixelWidth,
            pixelHeight: metadata.pixelHeight,
            sourceURL: sanitizedSourceURL(sourceURL),
            contentHash: metadata.contentHash ?? stableHash(data),
            etag: metadata.etag,
            lastModified: metadata.lastModified,
            needsRefresh: metadata.needsRefresh
        )
    }

    private func sanitizedSourceURL(_ sourceURL: URL) -> URL {
        guard var components = URLComponents(
            url: sourceURL,
            resolvingAgainstBaseURL: false
        ) else {
            return sourceURL
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.url ?? sourceURL
    }
}

private struct StoredCoverMetadata: Codable {
    let generation: String
    let metadata: RepositoryCoverCacheMetadata
}

private struct LatestCoverPointer: Codable {
    let sourceURL: URL
    let entryHash: String
}

public struct FallbackRepositoryCover: Equatable, Codable, Sendable {
    public let seed: String
    public let initials: String
    public let languageColorToken: String

    public init(seed: String, initials: String, languageColorToken: String) {
        self.seed = seed
        self.initials = initials
        self.languageColorToken = languageColorToken
    }

    public static func make(
        repository: Repository,
        language: String?
    ) -> FallbackRepositoryCover {
        FallbackRepositoryCover(
            seed: stableHash(repository.fullName),
            initials: initials(from: repository.name),
            languageColorToken: languageColorToken(for: language)
        )
    }

    private static func initials(from name: String) -> String {
        let parts = name.split { character in
            !character.isLetter && !character.isNumber
        }
        let value: String
        if parts.count >= 2 {
            value = parts.prefix(2).compactMap(\.first).map(String.init)
                .joined()
        } else {
            value = String((parts.first ?? Substring(name)).prefix(2))
        }
        return value.uppercased()
    }

    private static func languageColorToken(for language: String?) -> String {
        guard let language, !language.isEmpty else {
            return "language.unknown"
        }
        let normalized = language.lowercased().unicodeScalars.reduce(
            into: ""
        ) { result, scalar in
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else if !result.hasSuffix("-") {
                result.append("-")
            }
        }
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "language.\(normalized.isEmpty ? "unknown" : normalized)"
    }
}

private func stableHash(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
}

private func stableHash(_ value: Data) -> String {
    SHA256.hash(data: value)
        .map { String(format: "%02x", $0) }
        .joined()
}
