import Foundation

public enum LocalRepositoryAvailability: Equatable, Codable, Sendable {
    case available
    case missing
    case damaged
}

public struct LocalRepositoryRecord: Equatable, Codable, Sendable {
    public let repository: Repository
    public let localURL: URL
    public let availability: LocalRepositoryAvailability
    public let localSizeInBytes: Int64
    public let lastInspectedAt: Date

    public init(
        repository: Repository,
        localURL: URL,
        availability: LocalRepositoryAvailability,
        localSizeInBytes: Int64,
        lastInspectedAt: Date
    ) {
        self.repository = repository
        self.localURL = localURL
        self.availability = availability
        self.localSizeInBytes = localSizeInBytes
        self.lastInspectedAt = lastInspectedAt
    }
}

public protocol RepositoryFileSystem: Sendable {
    func itemExists(at url: URL) -> Bool
    func recursiveByteCount(at url: URL) throws -> Int64
}

public final class LocalRepositoryCatalog: @unchecked Sendable {
    private let rootDirectory: URL
    private let fileSystem: (any RepositoryFileSystem)?
    private let fileManager: FileManager?

    public init(
        rootDirectory: URL,
        fileSystem: any RepositoryFileSystem
    ) {
        self.rootDirectory = rootDirectory
        self.fileSystem = fileSystem
        fileManager = nil
    }

    public init(
        rootDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        fileSystem = nil
        self.fileManager = fileManager
    }

    public func record(for repository: Repository) throws -> LocalRepositoryRecord {
        let localURL = localURL(for: repository)
        let gitURL = localURL.appending(path: ".git", directoryHint: .isDirectory)
        let availability: LocalRepositoryAvailability
        let localSizeInBytes: Int64

        if itemExists(at: gitURL) {
            availability = .available
            localSizeInBytes = try recursiveByteCount(at: localURL)
        } else if itemExists(at: localURL) {
            availability = .damaged
            localSizeInBytes = try recursiveByteCount(at: localURL)
        } else {
            availability = .missing
            localSizeInBytes = 0
        }

        return LocalRepositoryRecord(
            repository: repository,
            localURL: localURL,
            availability: availability,
            localSizeInBytes: localSizeInBytes,
            lastInspectedAt: Date()
        )
    }

    public func localURL(for repository: Repository) -> URL {
        rootDirectory.appending(
            path: repository.safeLocalDirectoryName,
            directoryHint: .isDirectory
        )
    }

    public func records(repositories: [Repository]) throws -> [LocalRepositoryRecord] {
        try repositories.map(record(for:))
    }

    private func itemExists(at url: URL) -> Bool {
        if let fileSystem {
            return fileSystem.itemExists(at: url)
        }
        return fileManager?.fileExists(atPath: url.path) ?? false
    }

    private func recursiveByteCount(at directory: URL) throws -> Int64 {
        if let fileSystem {
            return try fileSystem.recursiveByteCount(at: directory)
        }
        guard let fileManager else {
            throw CocoaError(.fileReadUnknown)
        }
        let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey])
        guard directoryValues.isDirectory == true else {
            throw CocoaError(
                .fileReadUnknown,
                userInfo: [NSFilePathErrorKey: directory.path]
            )
        }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else {
            throw CocoaError(
                .fileReadUnknown,
                userInfo: [NSFilePathErrorKey: directory.path]
            )
        }

        var byteCount: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                byteCount += Int64(values.fileSize ?? 0)
            }
        }
        return byteCount
    }
}
