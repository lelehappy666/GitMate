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
    func update(
        accountID: String,
        _ transform: @Sendable (
            WorkspaceCacheSnapshot?
        ) throws -> WorkspaceCacheSnapshot
    ) throws
}

public extension WorkspaceCaching {
    func migrateRepositoryIdentity(
        accountID: String,
        from sourceRepository: Repository,
        to targetRepository: Repository,
        localURL: URL,
        migratedAt: Date = Date()
    ) throws {
        try update(accountID: accountID) { snapshot in
            let currentSnapshot = snapshot ?? WorkspaceCacheSnapshot(
                accountID: accountID,
                repositoryRecords: [],
                onlineSummaries: [:],
                savedAt: migratedAt
            )
            let matchingRecords = currentSnapshot.repositoryRecords.filter {
                $0.repository.id == sourceRepository.id
                    || $0.repository.id == targetRepository.id
                    || $0.repository.normalizedFullName
                        == sourceRepository.normalizedFullName
                    || $0.repository.normalizedFullName
                        == targetRepository.normalizedFullName
            }
            let sourceRecord = matchingRecords.last {
                $0.repository.id == sourceRepository.id
            } ?? matchingRecords.last {
                $0.localURL.standardizedFileURL
                    == localURL.standardizedFileURL
            } ?? matchingRecords.last

            var records = currentSnapshot.repositoryRecords
            let removedRepositoryIDs = Set(
                matchingRecords.map(\.repository.id)
            ).union([
                sourceRepository.id,
                targetRepository.id
            ])
            records.removeAll {
                removedRepositoryIDs.contains($0.repository.id)
                    || $0.repository.normalizedFullName
                        == sourceRepository.normalizedFullName
                    || $0.repository.normalizedFullName
                        == targetRepository.normalizedFullName
            }
            records.append(
                LocalRepositoryRecord(
                    repository: targetRepository,
                    localURL: localURL,
                    availability: sourceRecord?.availability ?? .available,
                    localSizeInBytes: sourceRecord?.localSizeInBytes ?? 0,
                    lastInspectedAt:
                        sourceRecord?.lastInspectedAt ?? .distantPast
                )
            )

            let summary = currentSnapshot.onlineSummaries[
                targetRepository.id
            ] ?? currentSnapshot.onlineSummaries[
                sourceRepository.id
            ] ?? matchingRecords.reversed().compactMap {
                currentSnapshot.onlineSummaries[$0.repository.id]
            }.first
            var summaries = currentSnapshot.onlineSummaries
            for repositoryID in removedRepositoryIDs {
                summaries.removeValue(forKey: repositoryID)
            }
            if let summary {
                summaries[targetRepository.id] = RepositoryOnlineSummary(
                    repositoryID: targetRepository.id,
                    primaryLanguage: summary.primaryLanguage,
                    openIssueCount: summary.openIssueCount,
                    openPullRequestCount: summary.openPullRequestCount,
                    failedWorkflowCount: summary.failedWorkflowCount,
                    remoteUpdatedAt: summary.remoteUpdatedAt
                )
            }

            return WorkspaceCacheSnapshot(
                accountID: accountID,
                repositoryRecords: records,
                onlineSummaries: summaries,
                savedAt: migratedAt
            )
        }
    }
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
        return try loadUnlocked(url: url)
    }

    public func save(_ snapshot: WorkspaceCacheSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }
        let url = try cacheURL(for: snapshot.accountID)
        try saveUnlocked(snapshot, url: url)
    }

    public func clear(accountID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let url = try cacheURL(for: accountID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    public func update(
        accountID: String,
        _ transform: @Sendable (
            WorkspaceCacheSnapshot?
        ) throws -> WorkspaceCacheSnapshot
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        let url = try cacheURL(for: accountID)
        let currentSnapshot: WorkspaceCacheSnapshot?
        do {
            currentSnapshot = try loadUnlocked(url: url)
        } catch {
            currentSnapshot = nil
        }
        let updatedSnapshot = try transform(currentSnapshot)
        guard updatedSnapshot.accountID == accountID else {
            throw WorkspaceCacheError.invalidAccountID
        }
        try saveUnlocked(updatedSnapshot, url: url)
    }

    private func loadUnlocked(url: URL) throws -> WorkspaceCacheSnapshot? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(WorkspaceCacheSnapshot.self, from: data)
    }

    private func saveUnlocked(
        _ snapshot: WorkspaceCacheSnapshot,
        url: URL
    ) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(snapshotForStorage(snapshot))
        try data.write(to: url, options: .atomic)
    }

    private func cacheURL(for accountID: String) throws -> URL {
        guard !accountID.isEmpty,
              accountID != ".",
              accountID != "..",
              !accountID.contains("/"),
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
        let repository = Repository(
            id: record.repository.id,
            name: record.repository.name,
            fullName: record.repository.fullName,
            isPrivate: record.repository.isPrivate,
            defaultBranch: record.repository.defaultBranch,
            sizeInKilobytes: record.repository.sizeInKilobytes,
            cloneURL: sanitizedURL(record.repository.cloneURL),
            ownerAvatarURL: record.repository.ownerAvatarURL.map(sanitizedURL),
            primaryLanguage: record.repository.primaryLanguage
        )

        return LocalRepositoryRecord(
            repository: repository,
            localURL: sanitizedURL(record.localURL),
            availability: record.availability,
            localSizeInBytes: record.localSizeInBytes,
            lastInspectedAt: record.lastInspectedAt
        )
    }

    private func sanitizedURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? url
    }
}
