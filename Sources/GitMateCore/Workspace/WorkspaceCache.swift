import Foundation

public struct WorkspaceCacheSnapshot: Codable, Equatable, Sendable {
    public var accountID: String
    public var repositoryRecords: [LocalRepositoryRecord]
    public var onlineSummaries: [Int64: RepositoryOnlineSummary]
    public var savedAt: Date

    public init(
        accountID: String,
        repositoryRecords: [LocalRepositoryRecord],
        onlineSummaries: [Int64: RepositoryOnlineSummary],
        savedAt: Date
    ) {
        self.accountID = accountID
        self.repositoryRecords = repositoryRecords
        self.onlineSummaries = onlineSummaries
        self.savedAt = savedAt
    }
}

public protocol WorkspaceCaching: Sendable {
    func load(accountID: String) throws -> WorkspaceCacheSnapshot?
    func save(_ snapshot: WorkspaceCacheSnapshot) throws
    func clear(accountID: String) throws
}

public enum WorkspaceCacheError: Error, LocalizedError, Sendable {
    case invalidAccountID

    public var errorDescription: String? {
        "工作区缓存账户标识无效。"
    }
}

public final class JSONWorkspaceCache: WorkspaceCaching, @unchecked Sendable {
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        rootDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appending(path: "GitMate/Cache", directoryHint: .isDirectory),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public func load(accountID: String) throws -> WorkspaceCacheSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        let url = try cacheURL(for: accountID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(WorkspaceCacheSnapshot.self, from: data)
    }

    public func save(_ snapshot: WorkspaceCacheSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }
        let url = try cacheURL(for: snapshot.accountID)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(snapshotForStorage(snapshot))
        try data.write(to: url, options: .atomic)
    }

    public func clear(accountID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let url = try cacheURL(for: accountID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func cacheURL(for accountID: String) throws -> URL {
        guard !accountID.isEmpty,
              accountID != ".",
              accountID != "..",
              !accountID.contains("/"),
              !accountID.contains(":"),
              !accountID.contains("\\")
        else {
            throw WorkspaceCacheError.invalidAccountID
        }

        return rootDirectory
            .appending(path: accountID, directoryHint: .isDirectory)
            .appending(path: "workspace.json")
    }

    private func snapshotForStorage(
        _ snapshot: WorkspaceCacheSnapshot
    ) -> WorkspaceCacheSnapshot {
        WorkspaceCacheSnapshot(
            accountID: snapshot.accountID,
            repositoryRecords: snapshot.repositoryRecords.map(sanitizedRecord),
            onlineSummaries: snapshot.onlineSummaries,
            savedAt: snapshot.savedAt
        )
    }

    private func sanitizedRecord(_ record: LocalRepositoryRecord) -> LocalRepositoryRecord {
        var components = URLComponents(
            url: record.repository.cloneURL,
            resolvingAgainstBaseURL: false
        )
        components?.user = nil
        components?.password = nil
        components?.query = nil
        components?.fragment = nil
        let cloneURL = components?.url ?? record.repository.cloneURL
        let repository = Repository(
            id: record.repository.id,
            name: record.repository.name,
            fullName: record.repository.fullName,
            isPrivate: record.repository.isPrivate,
            defaultBranch: record.repository.defaultBranch,
            sizeInKilobytes: record.repository.sizeInKilobytes,
            cloneURL: cloneURL,
            ownerAvatarURL: record.repository.ownerAvatarURL
        )

        return LocalRepositoryRecord(
            repository: repository,
            localURL: record.localURL,
            availability: record.availability,
            localSizeInBytes: record.localSizeInBytes,
            lastInspectedAt: record.lastInspectedAt
        )
    }
}
