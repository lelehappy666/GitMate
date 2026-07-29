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
        try await summaryHandler(repository, token)
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
        let service = WorkspaceContentService(
            catalog: makeContentCatalog(availability: ["desktop": .available]),
            localGit: localGit,
            github: offlineGitHubFixture(),
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
            [.onlineSummary, .readme],
            "在线模块失败应分别记录面板错误"
        )
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
                    201: RepositoryOnlineSummary(
                        repositoryID: 201,
                        primaryLanguage: nil,
                        openIssueCount: 0,
                        openPullRequestCount: 0,
                        failedWorkflowCount: 0,
                        remoteUpdatedAt: nil
                    ),
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
    TestCase("README 不进入缓存并且每次都重新请求") {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let github = FixtureGitHubWorkspaceAPI(
            summary: { _, _ in contentSummaryFixture },
            readme: { _, _ in contentREADMEFixture }
        )
        let service = WorkspaceContentService(
            catalog: makeContentCatalog(availability: ["desktop": .missing]),
            localGit: FixtureLocalGitReader(),
            github: github,
            cache: MemoryWorkspaceCache(),
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

        try expectEqual(github.readmeRequestCount, 2, "README 不得使用工作区缓存")
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
    TestCase("多个限流错误保留较晚恢复时间") {
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
            "多个限流模块应采用较晚恢复时间"
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
    }
]
