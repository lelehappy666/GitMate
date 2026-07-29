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

        let entryRoot = try cacheEntryRoot(
            repositoryID: repositoryID,
            sourceURL: sourceURL
        )
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

    public func save(
        data: Data,
        metadata: RepositoryCoverCacheMetadata,
        repositoryID: Int64,
        sourceURL: URL
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        let entryRoot = try cacheEntryRoot(
            repositoryID: repositoryID,
            sourceURL: sourceURL
        )
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
}

private struct StoredCoverMetadata: Codable {
    let generation: String
    let metadata: RepositoryCoverCacheMetadata
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
