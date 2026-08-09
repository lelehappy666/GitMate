import Foundation

public struct WorkspaceCacheSnapshot: Codable, Equatable, Sendable {
    public var accountID: String
    public var repositoryRecords: [LocalRepositoryRecord]
    public var onlineSummaries: [Int64: RepositoryOnlineSummary]
    public var savedAt: Date
    public var repositoryIdentityAliases: [Int64: Int64]

    public init(
        accountID: String,
        repositoryRecords: [LocalRepositoryRecord],
        onlineSummaries: [Int64: RepositoryOnlineSummary],
        savedAt: Date,
        repositoryIdentityAliases: [Int64: Int64] = [:]
    ) {
        self.accountID = accountID
        self.repositoryRecords = repositoryRecords
        self.onlineSummaries = onlineSummaries
        self.savedAt = savedAt
        self.repositoryIdentityAliases = repositoryIdentityAliases
    }

    private enum CodingKeys: String, CodingKey {
        case accountID
        case repositoryRecords
        case onlineSummaries
        case savedAt
        case repositoryIdentityAliases
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try container.decode(String.self, forKey: .accountID)
        repositoryRecords = try container.decode(
            [LocalRepositoryRecord].self,
            forKey: .repositoryRecords
        )
        onlineSummaries = try container.decode(
            [Int64: RepositoryOnlineSummary].self,
            forKey: .onlineSummaries
        )
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        repositoryIdentityAliases = try container.decodeIfPresent(
            [Int64: Int64].self,
            forKey: .repositoryIdentityAliases
        ) ?? [:]
    }

    public func resolvingRepositoryIdentities(
        inheriting inheritedAliases: [Int64: Int64] = [:]
    ) -> WorkspaceCacheSnapshot {
        var aliases = inheritedAliases
        aliases.merge(repositoryIdentityAliases) { _, newest in newest }
        aliases = Self.normalizedAliases(aliases)

        let directRepositoryPairs: [(Int64, Repository)] =
            repositoryRecords.compactMap { record in
                let canonicalID = Self.canonicalID(
                    for: record.repository.id,
                    aliases: aliases
                )
                guard canonicalID == record.repository.id else {
                    return nil
                }
                return (canonicalID, record.repository)
            }
        let directRepositories = Dictionary(
            directRepositoryPairs,
            uniquingKeysWith: { _, newest in newest }
        )
        var selectedRecords:
            [Int64: (
                record: LocalRepositoryRecord,
                isDirect: Bool,
                position: Int
            )] = [:]
        for (position, record) in repositoryRecords.enumerated() {
            let canonicalID = Self.canonicalID(
                for: record.repository.id,
                aliases: aliases
            )
            let canonicalRepository = directRepositories[canonicalID]
                ?? Self.repository(
                    record.repository,
                    replacingIDWith: canonicalID
                )
            let candidate = LocalRepositoryRecord(
                repository: canonicalRepository,
                localURL: record.localURL,
                availability: record.availability,
                localSizeInBytes: record.localSizeInBytes,
                lastInspectedAt: record.lastInspectedAt
            )
            let isDirect = record.repository.id == canonicalID
            if let existing = selectedRecords[canonicalID],
               existing.isDirect && !isDirect {
                continue
            }
            selectedRecords[canonicalID] = (
                record: candidate,
                isDirect: isDirect,
                position: position
            )
        }
        let records = selectedRecords.values
            .sorted { $0.position < $1.position }
            .map(\.record)

        var selectedSummaries:
            [Int64: (
                summary: RepositoryOnlineSummary,
                isDirect: Bool
            )] = [:]
        for (repositoryID, summary) in onlineSummaries {
            let canonicalID = Self.canonicalID(
                for: repositoryID,
                aliases: aliases
            )
            let isDirect = repositoryID == canonicalID
            if let existing = selectedSummaries[canonicalID],
               existing.isDirect && !isDirect {
                continue
            }
            selectedSummaries[canonicalID] = (
                summary: RepositoryOnlineSummary(
                    repositoryID: canonicalID,
                    primaryLanguage: summary.primaryLanguage,
                    openIssueCount: summary.openIssueCount,
                    openPullRequestCount: summary.openPullRequestCount,
                    failedWorkflowCount: summary.failedWorkflowCount,
                    remoteUpdatedAt: summary.remoteUpdatedAt
                ),
                isDirect: isDirect
            )
        }

        return WorkspaceCacheSnapshot(
            accountID: accountID,
            repositoryRecords: records,
            onlineSummaries: selectedSummaries.mapValues(\.summary),
            savedAt: savedAt,
            repositoryIdentityAliases: aliases
        )
    }

    private static func normalizedAliases(
        _ aliases: [Int64: Int64]
    ) -> [Int64: Int64] {
        var normalized: [Int64: Int64] = [:]
        for sourceID in aliases.keys {
            let targetID = canonicalID(for: sourceID, aliases: aliases)
            if sourceID != targetID {
                normalized[sourceID] = targetID
            }
        }
        return normalized
    }

    private static func canonicalID(
        for repositoryID: Int64,
        aliases: [Int64: Int64]
    ) -> Int64 {
        var currentID = repositoryID
        var visited = Set<Int64>()
        while let nextID = aliases[currentID],
              visited.insert(currentID).inserted {
            currentID = nextID
        }
        return currentID
    }

    private static func repository(
        _ repository: Repository,
        replacingIDWith id: Int64
    ) -> Repository {
        Repository(
            id: id,
            name: repository.name,
            fullName: repository.fullName,
            isPrivate: repository.isPrivate,
            defaultBranch: repository.defaultBranch,
            sizeInKilobytes: repository.sizeInKilobytes,
            cloneURL: repository.cloneURL,
            ownerAvatarURL: repository.ownerAvatarURL,
            primaryLanguage: repository.primaryLanguage
        )
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

            var aliases = currentSnapshot.repositoryIdentityAliases
            for repositoryID in removedRepositoryIDs
                where repositoryID != targetRepository.id {
                aliases[repositoryID] = targetRepository.id
            }
            return WorkspaceCacheSnapshot(
                accountID: accountID,
                repositoryRecords: records,
                onlineSummaries: summaries,
                savedAt: migratedAt,
                repositoryIdentityAliases: aliases
            ).resolvingRepositoryIdentities()
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
        let currentSnapshot = try? loadUnlocked(url: url)
        let resolvedSnapshot = snapshot.resolvingRepositoryIdentities(
            inheriting: currentSnapshot?.repositoryIdentityAliases ?? [:]
        )
        try saveUnlocked(resolvedSnapshot, url: url)
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
        let resolvedSnapshot = updatedSnapshot.resolvingRepositoryIdentities(
            inheriting: currentSnapshot?.repositoryIdentityAliases ?? [:]
        )
        try saveUnlocked(resolvedSnapshot, url: url)
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
            savedAt: snapshot.savedAt,
            repositoryIdentityAliases:
                snapshot.repositoryIdentityAliases
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
