import Foundation
import GitMateCore

private let contentRepositoryFixture = Repository(
    id: 201,
    name: "desktop",
    fullName: "GitMate/desktop",
    isPrivate: true,
    defaultBranch: "main",
    sizeInKilobytes: 4_096,
    cloneURL: URL(string: "https://github.com/GitMate/desktop.git")!,
    ownerAvatarURL: nil
)

private let secondContentRepositoryFixture = Repository(
    id: 202,
    name: "server",
    fullName: "GitMate/server",
    isPrivate: false,
    defaultBranch: "main",
    sizeInKilobytes: 2_048,
    cloneURL: URL(string: "https://github.com/GitMate/server.git")!,
    ownerAvatarURL: nil
)

private let contentAccountFixture = GitHubAccount(
    id: "github.com:9001",
    login: "octocat",
    name: "Octo Cat",
    avatarURL: nil,
    serverURL: URL(string: "https://github.com")!,
    kind: .githubDotCom,
    scopes: ["repo"]
)

private let contentStatusFixture = LocalRepositoryStatus(
    branch: "main",
    upstream: "origin/main",
    ahead: 1,
    behind: 0,
    stagedCount: 1,
    unstagedCount: 2,
    untrackedCount: 3,
    conflictCount: 0
)

private let contentSummaryFixture = RepositoryOnlineSummary(
    repositoryID: 201,
    primaryLanguage: "Swift",
    openIssueCount: 7,
    openPullRequestCount: 3,
    failedWorkflowCount: 1,
    remoteUpdatedAt: Date(timeIntervalSince1970: 1_785_319_200)
)

private let contentREADMEFixture = GitHubREADME(
    repositoryID: 201,
    path: "README.md",
    markdown: "# Desktop",
    downloadURL: URL(string: "https://raw.githubusercontent.com/GitMate/desktop/main/README.md")
)

private enum ContentFixtureError: Error, Sendable {
    case unavailable
}

private struct ContentRepositoryFileSystem: RepositoryFileSystem {
    let availabilityByName: [String: LocalRepositoryAvailability]

    func itemExists(at url: URL) -> Bool {
        let repositoryName = url.deletingLastPathComponent().lastPathComponent
        if url.lastPathComponent == ".git" {
            return availabilityByName[repositoryName] == .available
        }
        return availabilityByName[url.lastPathComponent] == .damaged
            || availabilityByName[url.lastPathComponent] == .available
    }

    func recursiveByteCount(at url: URL) throws -> Int64 {
        4_096
    }
}

private func makeContentCatalog(
    availability: [String: LocalRepositoryAvailability]
) -> LocalRepositoryCatalog {
    LocalRepositoryCatalog(
        rootDirectory: URL(fileURLWithPath: "/workspace"),
        fileSystem: ContentRepositoryFileSystem(
            availabilityByName: availability
        )
    )
}

private final class FixtureLocalGitReader: LocalGitReading, @unchecked Sendable {
    typealias StatusHandler = @Sendable (URL) async throws -> LocalRepositoryStatus
    typealias CommitsHandler = @Sendable (URL, String?, Int) async throws -> GitCommitPage

    private let statusHandler: StatusHandler
    private let commitsHandler: CommitsHandler
    private let lock = NSLock()
    private var commitLimits: [Int] = []

    init(
        status: @escaping StatusHandler = { _ in contentStatusFixture },
        commits: @escaping CommitsHandler = { _, _, _ in
            GitCommitPage(commits: [contentCommitFixture(0)], nextCursor: nil)
        }
    ) {
        statusHandler = status
        commitsHandler = commits
    }

    func status(repositoryURL: URL) async throws -> LocalRepositoryStatus {
        try await statusHandler(repositoryURL)
    }

    func commits(
        repositoryURL: URL,
        cursor: String?,
        limit: Int
    ) async throws -> GitCommitPage {
        lock.withLock {
            commitLimits.append(limit)
        }
        return try await commitsHandler(repositoryURL, cursor, limit)
    }

    var recordedCommitLimits: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return commitLimits
    }

    func tree(
        repositoryURL: URL,
        revision: String,
        path: String
    ) async throws -> [GitFileEntry] {
        throw ContentFixtureError.unavailable
    }

    func file(
        repositoryURL: URL,
        revision: String,
        path: String
    ) async throws -> GitFileContent {
        throw ContentFixtureError.unavailable
    }

    func commit(
        repositoryURL: URL,
        hash: String
    ) async throws -> GitCommitDetail {
        throw ContentFixtureError.unavailable
    }

    func diff(repositoryURL: URL, hash: String) async throws -> GitDiff {
        throw ContentFixtureError.unavailable
    }

    func graph(
        repositoryURL: URL,
        cursor: String?,
        limit: Int
    ) async throws -> CommitGraphPage {
        throw ContentFixtureError.unavailable
    }
}

private final class FixtureGitHubWorkspaceAPI: GitHubWorkspaceAPI, @unchecked Sendable {
    typealias SummaryHandler = @Sendable (
        Repository,
        String
    ) async throws -> RepositoryOnlineSummary
    typealias READMEHandler = @Sendable (
        Repository,
        String
    ) async throws -> GitHubREADME

    private let summaryHandler: SummaryHandler
    private let readmeHandler: READMEHandler
    private let lock = NSLock()
    private var summaryRequests = 0
    private var readmeRequests = 0

    init(
        summary: @escaping SummaryHandler,
        readme: @escaping READMEHandler
    ) {
        summaryHandler = summary
        readmeHandler = readme
    }

    func repositorySummary(
        repository: Repository,
        token: String
    ) async throws -> RepositoryOnlineSummary {
        lock.withLock {
            summaryRequests += 1
        }
        return try await summaryHandler(repository, token)
    }

    func readme(
        repository: Repository,
        token: String
    ) async throws -> GitHubREADME {
        lock.withLock {
            readmeRequests += 1
        }
        return try await readmeHandler(repository, token)
    }

    var readmeRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return readmeRequests
    }

    var summaryRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return summaryRequests
    }
}

private final class AdjustableContentClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var now: Date {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            value = value.addingTimeInterval(interval)
        }
    }
}

private actor RepositoryContentRequestGate {
    private var isOpen = false
    private var requestCount = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func waitUntilOpened() async {
        requestCount += 1
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilRequestCount(_ expectedCount: Int) async {
        while requestCount < expectedCount {
            await Task.yield()
        }
    }

    func open() {
        isOpen = true
        let waiting = continuations
        continuations.removeAll()
        waiting.forEach { $0.resume() }
    }
}

private func collectRepositoryContentUpdates(
    _ updates: AsyncThrowingStream<RepositoryContentUpdate, Error>
) async throws -> [RepositoryContentUpdate] {
    var collected: [RepositoryContentUpdate] = []
    for try await update in updates {
        collected.append(update)
    }
    return collected
}

private final class MemoryWorkspaceCache: WorkspaceCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSnapshot: WorkspaceCacheSnapshot?
    private var loadedAccountIDs: [String] = []
    private var remainingLoadFailures: Int

    init(
        snapshot: WorkspaceCacheSnapshot? = nil,
        loadFailureCount: Int = 0
    ) {
        storedSnapshot = snapshot
        remainingLoadFailures = loadFailureCount
    }

    func load(accountID: String) throws -> WorkspaceCacheSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        loadedAccountIDs.append(accountID)
        if remainingLoadFailures > 0 {
            remainingLoadFailures -= 1
            throw ContentFixtureError.unavailable
        }
        return storedSnapshot?.accountID == accountID ? storedSnapshot : nil
    }

    func save(_ snapshot: WorkspaceCacheSnapshot) throws {
        lock.lock()
        storedSnapshot = snapshot
        lock.unlock()
    }

    func clear(accountID: String) throws {
        lock.lock()
        if storedSnapshot?.accountID == accountID {
            storedSnapshot = nil
        }
        lock.unlock()
    }

    func update(
        accountID: String,
        _ transform: @Sendable (
            WorkspaceCacheSnapshot?
        ) throws -> WorkspaceCacheSnapshot
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        storedSnapshot = try transform(storedSnapshot)
    }

    var snapshot: WorkspaceCacheSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return storedSnapshot
    }

    var accountIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return loadedAccountIDs
    }
}

private final class InterleavingWorkspaceCache: WorkspaceCaching, @unchecked Sendable {
    private let condition = NSCondition()
    private var storedSnapshot: WorkspaceCacheSnapshot?
    private var loadCount = 0
    private var transactionLoadArrivals = 0

    func load(accountID: String) throws -> WorkspaceCacheSnapshot? {
        condition.lock()
        defer { condition.unlock() }
        loadCount += 1
        let captured = storedSnapshot
        guard loadCount > 2 else {
            return captured
        }

        transactionLoadArrivals += 1
        if transactionLoadArrivals == 2 {
            condition.broadcast()
        } else {
            while transactionLoadArrivals < 2 {
                condition.wait()
            }
        }
        return captured
    }

    func save(_ snapshot: WorkspaceCacheSnapshot) throws {
        condition.lock()
        storedSnapshot = snapshot
        condition.unlock()
    }

    func clear(accountID: String) throws {
        condition.lock()
        if storedSnapshot?.accountID == accountID {
            storedSnapshot = nil
        }
        condition.unlock()
    }

    func update(
        accountID: String,
        _ transform: @Sendable (
            WorkspaceCacheSnapshot?
        ) throws -> WorkspaceCacheSnapshot
    ) throws {
        condition.lock()
        defer { condition.unlock() }
        storedSnapshot = try transform(storedSnapshot)
    }

    var snapshot: WorkspaceCacheSnapshot? {
        condition.lock()
        defer { condition.unlock() }
        return storedSnapshot
    }
}

private actor SummaryRequestBarrier {
    private var arrivals = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func waitForBothRequests() async {
        arrivals += 1
        if arrivals == 2 {
            let waiting = continuations
            continuations.removeAll()
            for continuation in waiting {
                continuation.resume()
            }
            return
        }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}

private struct CancellationRepositoryFileSystem: RepositoryFileSystem {
    func itemExists(at url: URL) -> Bool {
        true
    }

    func recursiveByteCount(at url: URL) throws -> Int64 {
        throw CancellationError()
    }
}

private final class CancellationWorkspaceCache: WorkspaceCaching, @unchecked Sendable {
    enum Stage: Equatable {
        case load
        case update
    }

    private let stage: Stage

    init(stage: Stage) {
        self.stage = stage
    }

    func load(accountID: String) throws -> WorkspaceCacheSnapshot? {
        if stage == .load {
            throw CancellationError()
        }
        return nil
    }

    func save(_ snapshot: WorkspaceCacheSnapshot) throws {}

    func clear(accountID: String) throws {}

    func update(
        accountID: String,
        _ transform: @Sendable (
            WorkspaceCacheSnapshot?
        ) throws -> WorkspaceCacheSnapshot
    ) throws {
        if stage == .update {
            throw CancellationError()
        }
        _ = try transform(nil)
    }
}

private func expectWorkspaceCancellation(
    _ message: String,
    operation: () async throws -> Void
) async throws {
    do {
        try await operation()
        throw TestFailure(description: "\(message)：操作未抛出 CancellationError")
    } catch is CancellationError {
        return
    } catch {
        throw TestFailure(
            description: "\(message)：实际错误为 \(String(describing: error))"
        )
    }
}

private func contentCommitFixture(_ index: Int) -> GitCommit {
    GitCommit(
        shortHash: "abc\(index)",
        fullHash: String(repeating: "\(index % 10)", count: 40),
        subject: "提交 \(index)",
        authorName: "Octo Cat",
        authorEmail: "octo@example.com",
        authoredAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
        parentHashes: [],
        decorations: []
    )
}

private func cachedSnapshot(
    savedAt: Date,
    summaries: [Int64: RepositoryOnlineSummary] = [201: contentSummaryFixture]
) -> WorkspaceCacheSnapshot {
    WorkspaceCacheSnapshot(
        accountID: contentAccountFixture.id,
        repositoryRecords: [],
        onlineSummaries: summaries,
        savedAt: savedAt
    )
}

private func offlineGitHubFixture() -> FixtureGitHubWorkspaceAPI {
    FixtureGitHubWorkspaceAPI(
        summary: { _, _ in throw URLError(.notConnectedToInternet) },
        readme: { _, _ in throw URLError(.notConnectedToInternet) }
    )
}

let workspaceContentServiceTests = [
    TestCase("离线时保留本地事实与有效缓存") {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let localGit = FixtureLocalGitReader(
            commits: { _, _, _ in
                GitCommitPage(
                    commits: (0..<10).map(contentCommitFixture),
                    nextCursor: nil
                )
            }
        )
        let cache = MemoryWorkspaceCache(
            snapshot: cachedSnapshot(savedAt: now.addingTimeInterval(-900))
        )
        let github = offlineGitHubFixture()
        let service = WorkspaceContentService(
            catalog: makeContentCatalog(availability: ["desktop": .available]),
            localGit: localGit,
            github: github,
            cache: cache,
            now: { now }
        )

        let content = try await service.repositoryContent(
            repository: contentRepositoryFixture,
            account: contentAccountFixture,
            token: "secret"
        )

        try expectEqual(content.connectivity, .offline, "普通网络失败应标记离线")
        try expectEqual(content.localStatus, contentStatusFixture, "离线时应保留本地状态")
        try expectEqual(content.onlineSummary, contentSummaryFixture, "900 秒边界缓存仍有效")
        try expectEqual(content.recentCommits.count, 8, "最近提交结果最多返回 8 条")
        try expectEqual(localGit.recordedCommitLimits, [8], "最近提交请求固定为 8 条")
        try expectEqual(
            content.panelErrors.map(\.panel),
            [.readme],
            "有效磁盘摘要不刷新，README 离线失败应单独记录"
        )
        try expectEqual(github.summaryRequestCount, 0, "有效磁盘摘要不得立即刷新")
        try expectEqual(cache.accountIDs, [contentAccountFixture.id], "缓存必须按账户编号读取")
    },
    TestCase("过期和未来缓存都不能作为离线摘要") {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        for savedAt in [
            now.addingTimeInterval(-900.001),
            now.addingTimeInterval(1)
        ] {
            let service = WorkspaceContentService(
                catalog: makeContentCatalog(availability: ["desktop": .missing]),
                localGit: FixtureLocalGitReader(),
                github: offlineGitHubFixture(),
                cache: MemoryWorkspaceCache(
                    snapshot: cachedSnapshot(savedAt: savedAt)
                ),
                now: { now }
            )

            let content = try await service.repositoryContent(
                repository: contentRepositoryFixture,
                account: contentAccountFixture,
                token: "secret"
            )

            try expectEqual(content.onlineSummary, nil, "缓存仅允许 0...900 秒年龄")
        }
    },
    TestCase("在线成功更新目标摘要并保留其他缓存条目") {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let otherSummary = RepositoryOnlineSummary(
            repositoryID: 202,
            primaryLanguage: "Go",
            openIssueCount: 1,
            openPullRequestCount: 2,
            failedWorkflowCount: 0,
            remoteUpdatedAt: nil
        )
        let cache = MemoryWorkspaceCache(
            snapshot: cachedSnapshot(
                savedAt: now.addingTimeInterval(-30),
                summaries: [
                    202: otherSummary
                ]
            )
        )
        let github = FixtureGitHubWorkspaceAPI(
            summary: { repository, token in
                try expectEqual(token, "secret", "在线请求应原样使用调用令牌")
                return contentSummaryFixture
            },
            readme: { _, _ in contentREADMEFixture }
        )
        let service = WorkspaceContentService(
            catalog: makeContentCatalog(availability: ["desktop": .available]),
            localGit: FixtureLocalGitReader(),
            github: github,
            cache: cache,
            now: { now }
        )

        let content = try await service.repositoryContent(
            repository: contentRepositoryFixture,
            account: contentAccountFixture,
            token: "secret"
        )

        try expectEqual(content.connectivity, .online, "在线模块成功应标记在线")
        try expectEqual(content.onlineSummary, contentSummaryFixture, "在线摘要优先于缓存")
        try expectEqual(content.readme, contentREADMEFixture, "README 应来自在线 API")
        try expectEqual(cache.snapshot?.onlineSummaries[201], contentSummaryFixture, "应更新目标摘要")
        try expectEqual(cache.snapshot?.onlineSummaries[202], otherSummary, "应保留其他摘要")
        try expectEqual(cache.snapshot?.savedAt, now, "在线成功后应刷新缓存时间")
    },
    TestCase("在线保存不得复活过期快照中的其他摘要") {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expiredOtherSummary = RepositoryOnlineSummary(
            repositoryID: 202,
            primaryLanguage: "Go",
            openIssueCount: 99,
            openPullRequestCount: 99,
            failedWorkflowCount: 99,
            remoteUpdatedAt: nil
        )
        let cache = MemoryWorkspaceCache(
            snapshot: cachedSnapshot(
                savedAt: now.addingTimeInterval(-901),
                summaries: [202: expiredOtherSummary]
            )
        )
        let service = WorkspaceContentService(
            catalog: makeContentCatalog(availability: ["desktop": .missing]),
            localGit: FixtureLocalGitReader(),
            github: FixtureGitHubWorkspaceAPI(
                summary: { _, _ in contentSummaryFixture },
                readme: { _, _ in contentREADMEFixture }
            ),
            cache: cache,
            now: { now }
        )

        _ = try await service.repositoryContent(
            repository: contentRepositoryFixture,
            account: contentAccountFixture,
            token: "secret"
        )

        try expectEqual(
            cache.snapshot?.onlineSummaries[202],
            nil,
            "过期快照中的其他摘要不得因目标仓库刷新而复活"
        )
        try expectEqual(
            cache.snapshot?.onlineSummaries[201],
            contentSummaryFixture,
            "目标仓库的新摘要仍应写入"
        )
    },
    TestCase("在线成功可以覆盖无法解码的旧缓存") {
        let cache = MemoryWorkspaceCache(loadFailureCount: 2)
        let service = WorkspaceContentService(
            catalog: makeContentCatalog(availability: ["desktop": .missing]),
            localGit: FixtureLocalGitReader(),
            github: FixtureGitHubWorkspaceAPI(
                summary: { _, _ in contentSummaryFixture },
                readme: { _, _ in contentREADMEFixture }
            ),
            cache: cache
        )

        let content = try await service.repositoryContent(
            repository: contentRepositoryFixture,
            account: contentAccountFixture,
            token: "secret"
        )

        try expectEqual(content.onlineSummary, contentSummaryFixture, "在线摘要不应受坏缓存影响")
        try expectEqual(
            cache.snapshot?.onlineSummaries[201],
            contentSummaryFixture,
            "坏缓存应被新的有效快照覆盖"
        )
    },
    TestCase("README 不写入磁盘但五分钟内复用完整内存缓存") {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let github = FixtureGitHubWorkspaceAPI(
            summary: { _, _ in contentSummaryFixture },
            readme: { _, _ in contentREADMEFixture }
        )
        let serviceCache = MemoryWorkspaceCache()
        let service = WorkspaceContentService(
            catalog: makeContentCatalog(availability: ["desktop": .missing]),
            localGit: FixtureLocalGitReader(),
            github: github,
            cache: serviceCache,
            now: { now }
        )

        _ = try await service.repositoryContent(
            repository: contentRepositoryFixture,
            account: contentAccountFixture,
            token: "secret"
        )
        _ = try await service.repositoryContent(
            repository: contentRepositoryFixture,
            account: contentAccountFixture,
            token: "secret"
        )

        try expectEqual(github.readmeRequestCount, 1, "五分钟内 README 应复用进程内完整缓存")
        try expectEqual(
            serviceCache.snapshot?.onlineSummaries[contentRepositoryFixture.id],
            contentSummaryFixture,
            "磁盘缓存仍只保存公开摘要"
        )
    },
    TestCase("总览与README并发访问合并同仓库完整内容刷新") {
        let gate = RepositoryContentRequestGate()
        let github = FixtureGitHubWorkspaceAPI(
            summary: { _, _ in
                await gate.waitUntilOpened()
                return contentSummaryFixture
            },
            readme: { _, _ in
                await gate.waitUntilOpened()
                return contentREADMEFixture
            }
        )
        let service = WorkspaceContentService(
            catalog: makeContentCatalog(availability: ["desktop": .available]),
            localGit: FixtureLocalGitReader(),
            github: github,
            cache: MemoryWorkspaceCache()
        )

        async let overviewUpdates = collectRepositoryContentUpdates(
            service.repositoryContentUpdates(
                repository: contentRepositoryFixture,
                account: contentAccountFixture,
                token: "secret"
            )
        )
        async let readmeUpdates = collectRepositoryContentUpdates(
            service.repositoryContentUpdates(
                repository: contentRepositoryFixture,
                account: contentAccountFixture,
                token: "secret"
            )
        )

        await gate.waitUntilRequestCount(2)
        try expectEqual(github.summaryRequestCount, 1, "并发页面不得重复请求摘要")
        try expectEqual(github.readmeRequestCount, 1, "并发页面不得重复请求 README")
        await gate.open()

        let (overview, readme) = try await (overviewUpdates, readmeUpdates)
        try expectEqual(overview.map(\.freshness), [.refreshed], "首个页面应收到刷新结果")
        try expectEqual(readme.map(\.freshness), [.refreshed], "共享页面应收到同一刷新结果")
    },
    TestCase("完整内容缓存五分钟内命中并在过期后先陈旧后刷新") {
        let clock = AdjustableContentClock(
            Date(timeIntervalSince1970: 2_000_000_000)
        )
        let github = FixtureGitHubWorkspaceAPI(
            summary: { _, _ in contentSummaryFixture },
            readme: { _, _ in contentREADMEFixture }
        )
        let cache = MemoryWorkspaceCache()
        let service = WorkspaceContentService(
            catalog: makeContentCatalog(availability: ["desktop": .available]),
            localGit: FixtureLocalGitReader(),
            github: github,
            cache: cache,
            now: { clock.now }
        )

        _ = try await collectRepositoryContentUpdates(
            service.repositoryContentUpdates(
                repository: contentRepositoryFixture,
                account: contentAccountFixture,
                token: "secret"
            )
        )
        clock.advance(by: 299)
        let freshCacheUpdates = try await collectRepositoryContentUpdates(
            service.repositoryContentUpdates(
                repository: contentRepositoryFixture,
                account: contentAccountFixture,
                token: "secret"
            )
        )

        try expectEqual(
            freshCacheUpdates.map(\.freshness),
            [.cached],
            "299 秒时必须直接命中完整内容缓存"
        )
        try expectEqual(github.summaryRequestCount, 1, "新鲜缓存不得刷新摘要")
        try expectEqual(github.readmeRequestCount, 1, "新鲜缓存不得刷新 README")

        try cache.clear(accountID: contentAccountFixture.id)
        clock.advance(by: 2)
        let staleUpdates = try await collectRepositoryContentUpdates(
            service.repositoryContentUpdates(
                repository: contentRepositoryFixture,
                account: contentAccountFixture,
                token: "secret"
            )
        )

        try expectEqual(
            staleUpdates.map(\.freshness),
            [.cached, .refreshed],
            "过期缓存必须先显示再刷新"
        )
        try expectEqual(github.summaryRequestCount, 2, "301 秒时只启动一次摘要刷新")
        try expectEqual(github.readmeRequestCount, 2, "301 秒时只启动一次 README 刷新")
    },
    TestCase("冷启动有效磁盘摘要立即复用且不请求摘要接口") {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let github = FixtureGitHubWorkspaceAPI(
            summary: { _, _ in contentSummaryFixture },
            readme: { _, _ in contentREADMEFixture }
        )
        let service = WorkspaceContentService(
            catalog: makeContentCatalog(availability: ["desktop": .available]),
            localGit: FixtureLocalGitReader(),
            github: github,
            cache: MemoryWorkspaceCache(
                snapshot: WorkspaceCacheSnapshot(
                    accountID: contentAccountFixture.id,
                    repositoryRecords: [
                        LocalRepositoryRecord(
                            repository: contentRepositoryFixture,
                            localURL: URL(filePath: "/workspace/desktop"),
                            availability: .available,
                            localSizeInBytes: 123,
                            lastInspectedAt: now.addingTimeInterval(-60)
                        )
                    ],
                    onlineSummaries: [
                        contentRepositoryFixture.id: contentSummaryFixture
                    ],
                    savedAt: now.addingTimeInterval(-899)
                )
            ),
            now: { now }
        )

        let updates = try await collectRepositoryContentUpdates(
            service.repositoryContentUpdates(
                repository: contentRepositoryFixture,
                account: contentAccountFixture,
                token: "secret"
            )
        )

        try expectEqual(
            updates.last?.content.onlineSummary,
            contentSummaryFixture,
            "冷启动必须立即复用有效磁盘摘要"
        )
        try expectEqual(
            updates.last?.content.localRecord.localSizeInBytes,
            123,
            "仓库大小必须优先复用有效磁盘记录"
        )
        try expectEqual(
            github.summaryRequestCount,
            0,
            "有效磁盘摘要不得立即刷新"
        )
        try expectEqual(github.readmeRequestCount, 1, "README 仍只保存在进程内")
    },
    TestCase("工作台刷新不请求 README") {
        let github = FixtureGitHubWorkspaceAPI(
            summary: { repository, _ in
                RepositoryOnlineSummary(
                    repositoryID: repository.id,
                    primaryLanguage: "Swift",
                    openIssueCount: 0,
                    openPullRequestCount: 0,
                    failedWorkflowCount: 0,
                    remoteUpdatedAt: nil
                )
            },
            readme: { _, _ in contentREADMEFixture }
        )
        let service = WorkspaceContentService(
            catalog: makeContentCatalog(
                availability: [
                    "desktop": .available,
                    "server": .available
                ]
            ),
            localGit: FixtureLocalGitReader(),
            github: github,
            cache: MemoryWorkspaceCache()
        )

        _ = try await service.dashboard(
            account: contentAccountFixture,
            repositories: [
                contentRepositoryFixture,
                secondContentRepositoryFixture
            ],
            token: "secret"
        )

        try expectEqual(
            github.readmeRequestCount,
            0,
            "工作台只读取本地事实与在线摘要，不得批量请求 README"
        )
    },
    TestCase("工作台收到限流后停止启动后续在线请求") {
        let resetAt = Date(timeIntervalSince1970: 2_000)
        let github = FixtureGitHubWorkspaceAPI(
            summary: { _, _ in
                throw WorkspaceAPIError.rateLimited(resetAt: resetAt)
            },
            readme: { _, _ in contentREADMEFixture }
        )
        let rateLimitGate = WorkspaceRateLimitGate()
        let service = WorkspaceContentService(
            catalog: makeContentCatalog(
                availability: [
                    "desktop": .available,
                    "server": .available
                ]
            ),
            localGit: FixtureLocalGitReader(),
            github: github,
            cache: MemoryWorkspaceCache(),
            now: { Date(timeIntervalSince1970: 1_000) },
            maximumConcurrentRepositoryRefreshes: 1,
            rateLimitGate: rateLimitGate
        )

        let dashboard = try await service.dashboard(
            account: contentAccountFixture,
            repositories: [
                contentRepositoryFixture,
                secondContentRepositoryFixture
            ],
            token: "secret"
        )

        try expectEqual(
            github.summaryRequestCount,
            1,
            "首个限流响应后不得再启动第二个摘要请求"
        )
        try expectEqual(
            dashboard.connectivity,
            .rateLimited(resetAt: resetAt),
            "被限流拦截的仓库也应保留恢复时间"
        )
    },
    TestCase("并发刷新不同仓库不会覆盖已保存摘要") {
        let barrier = SummaryRequestBarrier()
        let cache = MemoryWorkspaceCache()
        let github = FixtureGitHubWorkspaceAPI(
            summary: { repository, _ in
                await barrier.waitForBothRequests()
                return RepositoryOnlineSummary(
                    repositoryID: repository.id,
                    primaryLanguage: repository.id == 201 ? "Swift" : "Go",
                    openIssueCount: 0,
                    openPullRequestCount: 0,
                    failedWorkflowCount: 0,
                    remoteUpdatedAt: nil
                )
            },
            readme: { repository, _ in
                GitHubREADME(
                    repositoryID: repository.id,
                    path: "README.md",
                    markdown: "# \(repository.name)",
                    downloadURL: nil
                )
            }
        )
        let service = WorkspaceContentService(
            catalog: makeContentCatalog(
                availability: [
                    "desktop": .missing,
                    "server": .missing
                ]
            ),
            localGit: FixtureLocalGitReader(),
            github: github,
            cache: cache
        )

        async let first = service.repositoryContent(
            repository: contentRepositoryFixture,
            account: contentAccountFixture,
            token: "secret"
        )
        async let second = service.repositoryContent(
            repository: secondContentRepositoryFixture,
            account: contentAccountFixture,
            token: "secret"
        )
        _ = try await (first, second)

        try expectEqual(
            cache.snapshot.map {
                Set($0.onlineSummaries.keys)
            } ?? [],
            Set([201, 202]),
            "并发保存必须原子保留两个成功摘要"
        )
    },
    TestCase("两个服务共享缓存时并发刷新不会丢失摘要") {
        let barrier = SummaryRequestBarrier()
        let cache = InterleavingWorkspaceCache()
        let github = FixtureGitHubWorkspaceAPI(
            summary: { repository, _ in
                await barrier.waitForBothRequests()
                return RepositoryOnlineSummary(
                    repositoryID: repository.id,
                    primaryLanguage: repository.id == 201 ? "Swift" : "Go",
                    openIssueCount: 0,
                    openPullRequestCount: 0,
                    failedWorkflowCount: 0,
                    remoteUpdatedAt: nil
                )
            },
            readme: { repository, _ in
                GitHubREADME(
                    repositoryID: repository.id,
                    path: "README.md",
                    markdown: "# \(repository.name)",
                    downloadURL: nil
                )
            }
        )
        let catalog = makeContentCatalog(
            availability: [
                "desktop": .missing,
                "server": .missing
            ]
        )
        let firstService = WorkspaceContentService(
            catalog: catalog,
            localGit: FixtureLocalGitReader(),
            github: github,
            cache: cache
        )
        let secondService = WorkspaceContentService(
            catalog: catalog,
            localGit: FixtureLocalGitReader(),
            github: github,
            cache: cache
        )

        async let first = firstService.repositoryContent(
            repository: contentRepositoryFixture,
            account: contentAccountFixture,
            token: "secret"
        )
        async let second = secondService.repositoryContent(
            repository: secondContentRepositoryFixture,
            account: contentAccountFixture,
            token: "secret"
        )
        _ = try await (first, second)

        try expectEqual(
            cache.snapshot.map {
                Set($0.onlineSummaries.keys)
            } ?? [],
            Set([201, 202]),
            "共享缓存必须原子保留两个服务的成功摘要"
        )
    },
    TestCase("本地缺失和损坏仍返回在线摘要与 README") {
        for availability in [
            LocalRepositoryAvailability.missing,
            LocalRepositoryAvailability.damaged
        ] {
            let github = FixtureGitHubWorkspaceAPI(
                summary: { _, _ in contentSummaryFixture },
                readme: { _, _ in contentREADMEFixture }
            )
            let service = WorkspaceContentService(
                catalog: makeContentCatalog(availability: ["desktop": availability]),
                localGit: FixtureLocalGitReader(
                    status: { _ in throw ContentFixtureError.unavailable },
                    commits: { _, _, _ in throw ContentFixtureError.unavailable }
                ),
                github: github,
                cache: MemoryWorkspaceCache()
            )

            let content = try await service.repositoryContent(
                repository: contentRepositoryFixture,
                account: contentAccountFixture,
                token: "secret"
            )

            try expectEqual(content.localRecord.availability, availability, "应保留本地可用性")
            try expectEqual(content.localStatus, nil, "不可用本地仓库不读取状态")
            try expectEqual(content.onlineSummary, contentSummaryFixture, "应保留在线摘要")
            try expectEqual(content.readme, contentREADMEFixture, "应保留在线 README")
            try expectEqual(content.panelErrors.first?.panel, .localRepository, "应记录本地面板错误")
        }
    },
    TestCase("授权与限流映射为独立连接状态") {
        let resetAt = Date(timeIntervalSince1970: 2_000_000_900)
        let scenarios: [(
            WorkspaceAPIError,
            WorkspaceConnectivity,
            String
        )] = [
            (
                .authorizationRequired,
                .authorizationRequired,
                "GitHub 授权已失效，请重新授权。"
            ),
            (
                .rateLimited(resetAt: resetAt),
                .rateLimited(resetAt: resetAt),
                "GitHub API 已达到速率限制，请在恢复后重试。"
            )
        ]

        for (apiError, expectedConnectivity, expectedMessage) in scenarios {
            let github = FixtureGitHubWorkspaceAPI(
                summary: { _, _ in throw apiError },
                readme: { _, _ in throw apiError }
            )
            let service = WorkspaceContentService(
                catalog: makeContentCatalog(availability: ["desktop": .missing]),
                localGit: FixtureLocalGitReader(),
                github: github,
                cache: MemoryWorkspaceCache()
            )

            let content = try await service.repositoryContent(
                repository: contentRepositoryFixture,
                account: contentAccountFixture,
                token: "secret"
            )

            try expectEqual(content.connectivity, expectedConnectivity, "连接状态应保留错误语义")
            try expect(
                content.panelErrors
                    .filter {
                        $0.panel == .onlineSummary || $0.panel == .readme
                    }
                    .allSatisfy { $0.message == expectedMessage },
                "面板错误应使用稳定中文消息"
            )
        }
    },
    TestCase("并发在线模块合并限流恢复时间") {
        let earlier = Date(timeIntervalSince1970: 2_000_000_100)
        let later = Date(timeIntervalSince1970: 2_000_000_200)
        let service = WorkspaceContentService(
            catalog: makeContentCatalog(availability: ["desktop": .missing]),
            localGit: FixtureLocalGitReader(),
            github: FixtureGitHubWorkspaceAPI(
                summary: { _, _ in
                    throw WorkspaceAPIError.rateLimited(resetAt: earlier)
                },
                readme: { _, _ in
                    throw WorkspaceAPIError.rateLimited(resetAt: later)
                }
            ),
            cache: MemoryWorkspaceCache()
        )

        let content = try await service.repositoryContent(
            repository: contentRepositoryFixture,
            account: contentAccountFixture,
            token: "secret"
        )

        try expectEqual(
            content.connectivity,
            .rateLimited(resetAt: later),
            "并发在线模块应保留较晚的限流恢复时间"
        )
    },
    TestCase("工作台单模块失败不丢弃其他仓库内容") {
        let github = FixtureGitHubWorkspaceAPI(
            summary: { repository, _ in
                if repository.id == 202 {
                    throw WorkspaceAPIError.httpStatus(500, "volatile server text")
                }
                return contentSummaryFixture
            },
            readme: { repository, _ in
                GitHubREADME(
                    repositoryID: repository.id,
                    path: "README.md",
                    markdown: "# \(repository.name)",
                    downloadURL: nil
                )
            }
        )
        let localGit = FixtureLocalGitReader(
            status: { url in
                if url.lastPathComponent == "server" {
                    throw ContentFixtureError.unavailable
                }
                return contentStatusFixture
            }
        )
        let service = WorkspaceContentService(
            catalog: makeContentCatalog(
                availability: [
                    "desktop": .available,
                    "server": .available
                ]
            ),
            localGit: localGit,
            github: github,
            cache: MemoryWorkspaceCache()
        )

        let dashboard = try await service.dashboard(
            account: contentAccountFixture,
            repositories: [
                contentRepositoryFixture,
                secondContentRepositoryFixture
            ],
            token: "secret"
        )

        try expectEqual(dashboard.account, contentAccountFixture, "应保留账户")
        try expectEqual(dashboard.repositories.count, 2, "单模块失败不得丢弃仓库")
        try expectEqual(
            dashboard.repositories.first?.onlineSummary,
            contentSummaryFixture,
            "其他仓库在线摘要应保留"
        )
        try expect(
            dashboard.panelErrors.contains {
                $0.panel == .localStatus && $0.repositoryID == 202
            },
            "应聚合带仓库编号的本地状态错误"
        )
        try expect(
            dashboard.panelErrors.contains {
                $0.panel == .onlineSummary
                    && $0.repositoryID == 202
                    && $0.message == "无法加载 GitHub 在线摘要。"
            },
            "应聚合稳定的在线摘要错误"
        )
    },
    TestCase("单仓库目录读取异常不终止工作台其他仓库") {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "GitMateTask4CatalogFailure-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not-a-directory".utf8).write(
            to: directory.appending(path: "desktop")
        )
        let github = FixtureGitHubWorkspaceAPI(
            summary: { repository, _ in
                RepositoryOnlineSummary(
                    repositoryID: repository.id,
                    primaryLanguage: "Swift",
                    openIssueCount: 0,
                    openPullRequestCount: 0,
                    failedWorkflowCount: 0,
                    remoteUpdatedAt: nil
                )
            },
            readme: { repository, _ in
                GitHubREADME(
                    repositoryID: repository.id,
                    path: "README.md",
                    markdown: "# \(repository.name)",
                    downloadURL: nil
                )
            }
        )
        let service = WorkspaceContentService(
            catalog: LocalRepositoryCatalog(rootDirectory: directory),
            localGit: FixtureLocalGitReader(),
            github: github,
            cache: MemoryWorkspaceCache()
        )

        let dashboard = try await service.dashboard(
            account: contentAccountFixture,
            repositories: [
                contentRepositoryFixture,
                secondContentRepositoryFixture
            ],
            token: "secret"
        )

        try expectEqual(
            dashboard.repositories.map(\.repository.id),
            [201, 202],
            "目录异常仓库及后续仓库内容都应保留"
        )
        try expectEqual(
            dashboard.repositories.first?.onlineSummary?.repositoryID,
            201,
            "目录异常仓库仍应保留在线摘要"
        )
        try expect(
            dashboard.panelErrors.contains {
                $0.panel == .localRepository
                    && $0.repositoryID == 201
                    && $0.message == "无法读取本地仓库。"
            },
            "目录异常应记录稳定的仓库面板错误"
        )
    },
    TestCase("工作台增量流先发布缓存首屏并限四仓库并发逐仓库刷新") {
        let repositories = (0..<6).map(progressiveRepository)
        let availability = Dictionary(
            uniqueKeysWithValues: repositories.map {
                ($0.name, LocalRepositoryAvailability.available)
            }
        )
        let cachedRepository = repositories[0]
        let cachedSummary = progressiveSummary(
            repositoryID: cachedRepository.id,
            issueCount: 999
        )
        let cache = MemoryWorkspaceCache(
            snapshot: WorkspaceCacheSnapshot(
                accountID: String(contentAccountFixture.id),
                repositoryRecords: [
                    LocalRepositoryRecord(
                        repository: cachedRepository,
                        localURL: URL(
                            filePath: "/workspace/\(cachedRepository.name)"
                        ),
                        availability: .available,
                        localSizeInBytes: 123,
                        lastInspectedAt: Date(timeIntervalSince1970: 1_000)
                    )
                ],
                onlineSummaries: [cachedRepository.id: cachedSummary],
                savedAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        let gate = ProgressiveRefreshGate()
        let github = FixtureGitHubWorkspaceAPI(
            summary: { repository, _ in
                await gate.waitUntilOpened()
                return progressiveSummary(
                    repositoryID: repository.id,
                    issueCount: Int(repository.id)
                )
            },
            readme: { repository, _ in
                await gate.waitUntilOpened()
                return GitHubREADME(
                    repositoryID: repository.id,
                    path: "README.md",
                    markdown: "# \(repository.name)",
                    downloadURL: nil
                )
            }
        )
        let service = WorkspaceContentService(
            catalog: makeContentCatalog(availability: availability),
            localGit: FixtureLocalGitReader(),
            github: github,
            cache: cache,
            now: { Date(timeIntervalSince1970: 1_100) },
            maximumConcurrentRepositoryRefreshes: 4
        )
        var iterator = service.dashboardUpdates(
            account: contentAccountFixture,
            repositories: repositories,
            token: "secret"
        ).makeAsyncIterator()

        guard let first = try await iterator.next() else {
            throw TestFailure(description: "增量流必须发布首屏")
        }

        try expectEqual(first.repositories.count, 6, "首屏应立即包含全部本地仓库记录")
        try expectEqual(
            first.repositories[0].onlineSummary,
            cachedSummary,
            "首屏应在远程刷新前使用有效缓存摘要"
        )
        try expect(
            first.repositories.allSatisfy { $0.localStatus == nil },
            "首屏不得等待本地 Git 状态请求"
        )

        await gate.waitUntilRequestCount(4)
        let maximumActiveRequestCount = await gate.maximumActiveRequestCount
        try expectEqual(
            maximumActiveRequestCount,
            4,
            "远程模块未释放时全局最多只能有四个仓库刷新"
        )
        await gate.open()

        var snapshots = [first]
        while let snapshot = try await iterator.next() {
            snapshots.append(snapshot)
        }

        try expectEqual(
            snapshots.count,
            repositories.count + 1,
            "首屏后每完成一个仓库都应发布一次增量快照"
        )
        try expectEqual(
            snapshots.last?.repositories.map(\.repository.id),
            repositories.map(\.id),
            "并发完成不得改变仓库稳定顺序"
        )
        try expect(
            snapshots.last?.repositories.enumerated().allSatisfy {
                index, content in
                let expectedIssueCount = index == 0
                    ? 999
                    : Int(content.repository.id)
                return content.onlineSummary?.openIssueCount == expectedIssueCount
                    && content.readme == nil
            } == true,
            "最终快照应复用有效摘要、刷新缺失摘要且不批量读取 README"
        )
    },
    TestCase("仓库目录统计异常仍返回在线仓库内容") {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "GitMateTask4RepositoryFallback-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not-a-directory".utf8).write(
            to: directory.appending(path: "desktop")
        )
        let service = WorkspaceContentService(
            catalog: LocalRepositoryCatalog(rootDirectory: directory),
            localGit: FixtureLocalGitReader(),
            github: FixtureGitHubWorkspaceAPI(
                summary: { _, _ in contentSummaryFixture },
                readme: { _, _ in contentREADMEFixture }
            ),
            cache: MemoryWorkspaceCache()
        )

        let content = try await service.repositoryContent(
            repository: contentRepositoryFixture,
            account: contentAccountFixture,
            token: "secret"
        )

        try expectEqual(content.localRecord.availability, .damaged, "异常本地记录应降级为损坏")
        try expectEqual(
            content.localRecord.localURL,
            directory.appending(path: "desktop", directoryHint: .isDirectory),
            "fallback 应保留安全本地目录映射"
        )
        try expectEqual(content.onlineSummary, contentSummaryFixture, "应继续返回在线摘要")
        try expectEqual(content.readme, contentREADMEFixture, "应继续返回在线 README")
        try expect(
            content.panelErrors.contains {
                $0.panel == .localRepository
                    && $0.repositoryID == 201
                    && $0.message == "无法读取本地仓库。"
            },
            "应记录稳定的本地仓库面板错误"
        )
    },
    TestCase("工作区内容服务所有模块都向上传播取消") {
        func service(
            localGit: FixtureLocalGitReader = FixtureLocalGitReader(),
            github: FixtureGitHubWorkspaceAPI = FixtureGitHubWorkspaceAPI(
                summary: { _, _ in contentSummaryFixture },
                readme: { _, _ in contentREADMEFixture }
            ),
            cache: any WorkspaceCaching = MemoryWorkspaceCache(),
            catalog: LocalRepositoryCatalog = makeContentCatalog(
                availability: ["desktop": .available]
            )
        ) -> WorkspaceContentService {
            WorkspaceContentService(
                catalog: catalog,
                localGit: localGit,
                github: github,
                cache: cache
            )
        }

        try await expectWorkspaceCancellation("本地目录模块不得吞掉取消") {
            let cancellationService = service(
                catalog: LocalRepositoryCatalog(
                    rootDirectory: URL(filePath: "/workspace"),
                    fileSystem: CancellationRepositoryFileSystem()
                )
            )
            _ = try await cancellationService.repositoryContent(
                repository: contentRepositoryFixture,
                account: contentAccountFixture,
                token: "secret"
            )
        }

        try await expectWorkspaceCancellation("缓存读取模块不得吞掉取消") {
            let cancellationService = service(
                cache: CancellationWorkspaceCache(stage: .load)
            )
            _ = try await cancellationService.repositoryContent(
                repository: contentRepositoryFixture,
                account: contentAccountFixture,
                token: "secret"
            )
        }

        try await expectWorkspaceCancellation("本地状态模块不得吞掉取消") {
            let cancellationService = service(
                localGit: FixtureLocalGitReader(
                    status: { _ in throw CancellationError() }
                )
            )
            _ = try await cancellationService.repositoryContent(
                repository: contentRepositoryFixture,
                account: contentAccountFixture,
                token: "secret"
            )
        }

        try await expectWorkspaceCancellation("最近提交模块不得吞掉取消") {
            let cancellationService = service(
                localGit: FixtureLocalGitReader(
                    commits: { _, _, _ in throw CancellationError() }
                )
            )
            _ = try await cancellationService.repositoryContent(
                repository: contentRepositoryFixture,
                account: contentAccountFixture,
                token: "secret"
            )
        }

        try await expectWorkspaceCancellation("在线摘要模块不得吞掉取消") {
            let cancellationService = service(
                github: FixtureGitHubWorkspaceAPI(
                    summary: { _, _ in throw CancellationError() },
                    readme: { _, _ in contentREADMEFixture }
                )
            )
            _ = try await cancellationService.repositoryContent(
                repository: contentRepositoryFixture,
                account: contentAccountFixture,
                token: "secret"
            )
        }

        try await expectWorkspaceCancellation("缓存保存模块不得吞掉取消") {
            let cancellationService = service(
                cache: CancellationWorkspaceCache(stage: .update)
            )
            _ = try await cancellationService.repositoryContent(
                repository: contentRepositoryFixture,
                account: contentAccountFixture,
                token: "secret"
            )
        }

        try await expectWorkspaceCancellation("README 模块不得吞掉取消") {
            let cancellationService = service(
                github: FixtureGitHubWorkspaceAPI(
                    summary: { _, _ in contentSummaryFixture },
                    readme: { _, _ in throw CancellationError() }
                )
            )
            _ = try await cancellationService.repositoryContent(
                repository: contentRepositoryFixture,
                account: contentAccountFixture,
                token: "secret"
            )
        }

        try await expectWorkspaceCancellation("工作台聚合层不得吞掉取消") {
            let cancellationService = service(
                localGit: FixtureLocalGitReader(
                    status: { _ in throw CancellationError() }
                )
            )
            _ = try await cancellationService.dashboard(
                account: contentAccountFixture,
                repositories: [contentRepositoryFixture],
                token: "secret"
            )
        }
    }
]

private actor ProgressiveRefreshGate {
    private var isOpen = false
    private var activeRequestCount = 0
    private var maximumCount = 0
    private var requestCount = 0
    private var openContinuations: [CheckedContinuation<Void, Never>] = []

    var maximumActiveRequestCount: Int {
        maximumCount
    }

    func waitUntilOpened() async {
        requestCount += 1
        activeRequestCount += 1
        maximumCount = max(maximumCount, activeRequestCount)
        if !isOpen {
            await withCheckedContinuation { continuation in
                openContinuations.append(continuation)
            }
        }
        activeRequestCount -= 1
    }

    func waitUntilRequestCount(_ expectedCount: Int) async {
        while requestCount < expectedCount {
            await Task.yield()
        }
    }

    func open() {
        isOpen = true
        let continuations = openContinuations
        openContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private func progressiveRepository(_ index: Int) -> Repository {
    Repository(
        id: Int64(300 + index),
        name: "repository-\(index)",
        fullName: "GitMate/repository-\(index)",
        isPrivate: false,
        defaultBranch: "main",
        sizeInKilobytes: 1_024,
        cloneURL: URL(
            string: "https://github.com/GitMate/repository-\(index).git"
        )!,
        ownerAvatarURL: nil
    )
}

private func progressiveSummary(
    repositoryID: Int64,
    issueCount: Int
) -> RepositoryOnlineSummary {
    RepositoryOnlineSummary(
        repositoryID: repositoryID,
        primaryLanguage: "Swift",
        openIssueCount: issueCount,
        openPullRequestCount: 0,
        failedWorkflowCount: 0,
        remoteUpdatedAt: Date(timeIntervalSince1970: TimeInterval(repositoryID))
    )
}
