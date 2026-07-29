import CryptoKit
import Foundation

public struct RepositoryCoverCacheMetadata: Equatable, Codable, Sendable {
    public let contentType: String?
    public let storedAt: Date
    public let pixelWidth: Int?
    public let pixelHeight: Int?

    public init(
        contentType: String?,
        storedAt: Date,
        pixelWidth: Int?,
        pixelHeight: Int?
    ) {
        self.contentType = contentType
        self.storedAt = storedAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
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

    func clear(repositoryID: Int64) throws
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

        let urls = try cacheURLs(
            repositoryID: repositoryID,
            sourceURL: sourceURL
        )
        guard fileManager.fileExists(atPath: urls.data.path),
              fileManager.fileExists(atPath: urls.metadata.path)
        else {
            return nil
        }
        return RepositoryCoverCacheEntry(
            data: try Data(contentsOf: urls.data),
            metadata: try JSONDecoder().decode(
                RepositoryCoverCacheMetadata.self,
                from: Data(contentsOf: urls.metadata)
            )
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

        let urls = try cacheURLs(
            repositoryID: repositoryID,
            sourceURL: sourceURL
        )
        try fileManager.createDirectory(
            at: urls.data.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: urls.data, options: .atomic)
        try JSONEncoder().encode(metadata).write(
            to: urls.metadata,
            options: .atomic
        )
    }

    public func clear(repositoryID: Int64) throws {
        lock.lock()
        defer { lock.unlock() }

        let directory = repositoryDirectory(repositoryID)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    private func cacheURLs(
        repositoryID: Int64,
        sourceURL: URL
    ) throws -> (data: URL, metadata: URL) {
        guard ["http", "https"].contains(sourceURL.scheme?.lowercased()),
              sourceURL.host != nil
        else {
            throw RepositoryCoverCacheError.invalidSourceURL
        }
        let hash = stableHash(sourceURL.absoluteString)
        let dataURL = repositoryDirectory(repositoryID).appending(path: hash)
        return (
            dataURL,
            dataURL.appendingPathExtension("json")
        )
    }

    private func repositoryDirectory(_ repositoryID: Int64) -> URL {
        rootDirectory
            .appending(path: "Covers", directoryHint: .isDirectory)
            .appending(
                path: String(repositoryID),
                directoryHint: .isDirectory
            )
    }
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
