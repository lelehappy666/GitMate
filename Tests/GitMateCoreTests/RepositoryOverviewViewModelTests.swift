import Foundation
import GitMateCore

let repositoryOverviewViewModelTests = [
    TestCase("本地仓库缺失时保留远程总览与安全 README") { @MainActor in
        let repository = overviewRepository(
            cloneURL: URL(
                string: "https://reader:token-value@github.example/GitMate/mac-client.git?access_token=token-value"
            )!
        )
        let content = overviewContent(
            repository: repository,
            availability: .missing,
            summary: overviewSummary(repositoryID: repository.id),
            readme: GitHubREADME(
                repositoryID: repository.id,
                path: "README.md",
                markdown: """
                # GitMate
                <script>token-value</script>
                可靠的 macOS GitHub 工作区。
                """,
                downloadURL: URL(
                    string: "https://raw.example/GitMate/mac-client/main/README.md"
                )
            )
        )
        let viewModel = RepositoryOverviewViewModel(
            repository: repository,
            account: overviewAccount(),
            token: "token-value",
            loader: OverviewLoaderStub(outcomes: [.success(content)])
        )

        await viewModel.load()

        try expectEqual(
            viewModel.state.repository.fullName,
            "GitMate/mac-client",
            "本地缺失时仍应显示远程仓库"
        )
        try expectEqual(
            viewModel.state.localAvailability,
            .missing,
            "本地缺失应提示重新同步"
        )
        try expect(viewModel.state.needsResync, "本地缺失应开放重新同步入口")
        try expectEqual(
            viewModel.state.onlineSummary,
            overviewSummary(repositoryID: repository.id),
            "本地缺失不得丢失在线摘要"
        )
        try expect(
            viewModel.state.readmePreview?.plainText.contains("可靠的 macOS") == true,
            "本地缺失不得丢失 README 简介"
        )
        try expect(
            viewModel.state.readmePreview?.plainText.contains("token-value") == false,
            "README 中的脚本和敏感值不得进入视图状态"
        )
        try expect(
            !viewModel.state.repository.cloneURL.absoluteString.contains("token-value"),
            "远程地址进入状态前必须移除用户、密码和查询参数"
        )
    },
    TestCase("仓库总览派生同步计数最近提交与页面十三至十五路由") { @MainActor in
        let repository = overviewRepository()
        let status = LocalRepositoryStatus(
            branch: "feature/readme",
            upstream: "origin/feature/readme",
            ahead: 2,
            behind: 1,
            stagedCount: 2,
            unstagedCount: 3,
            untrackedCount: 4,
            conflictCount: 1
        )
        let commits = [
            overviewCommit(index: 1),
            overviewCommit(index: 2)
        ]
        let viewModel = RepositoryOverviewViewModel(
            repository: repository,
            account: overviewAccount(),
            token: "secret",
            loader: OverviewLoaderStub(
                outcomes: [
                    .success(
                        overviewContent(
                            repository: repository,
                            status: status,
                            recentCommits: commits
                        )
                    )
                ]
            )
        )

        await viewModel.load()

        try expectEqual(
            viewModel.state.uncommittedChangeCount,
            10,
            "同步计数应汇总暂存、未暂存、未跟踪与冲突"
        )
        try expectEqual(
            viewModel.state.recentCommits,
            commits,
            "最近提交应完整保留"
        )
        try expectEqual(
            viewModel.state.lastInspectedAt,
            Date(timeIntervalSince1970: 2_000),
            "本地目录扫描时间应明确保留为最近检查时间"
        )
        try expectEqual(
            viewModel.state.lastSynchronizedAt,
            nil,
            "没有真实同步元数据时不得把扫描时间伪装成最后同步时间"
        )
        try expectEqual(
            viewModel.state.quickRoutes,
            [
                .readme(repositoryID: repository.id),
                .filesAndCommits(repositoryID: repository.id),
                .commitGraph(repositoryID: repository.id)
            ],
            "快捷入口只能连接页面十三至十五"
        )
    },
    TestCase("仓库总览先展示缓存并由刷新结果原位替换") { @MainActor in
        let repository = overviewRepository()
        let cachedSummary = RepositoryOnlineSummary(
            repositoryID: repository.id,
            primaryLanguage: "Swift",
            openIssueCount: 1,
            openPullRequestCount: 0,
            failedWorkflowCount: 0,
            remoteUpdatedAt: nil
        )
        let refreshedSummary = RepositoryOnlineSummary(
            repositoryID: repository.id,
            primaryLanguage: "Swift",
            openIssueCount: 9,
            openPullRequestCount: 2,
            failedWorkflowCount: 1,
            remoteUpdatedAt: Date(timeIntervalSince1970: 4_000)
        )
        let loader = ControlledOverviewUpdatesLoader()
        let viewModel = RepositoryOverviewViewModel(
            repository: repository,
            account: overviewAccount(),
            token: "secret",
            loader: loader
        )

        let load = Task { @MainActor in
            await viewModel.load()
        }
        await loader.waitUntilConnected()
        loader.yield(
            RepositoryContentUpdate(
                content: overviewContent(
                    repository: repository,
                    summary: cachedSummary
                ),
                freshness: .cached,
                isFinal: false
            )
        )
        while viewModel.state.loadPhase != .loaded {
            await Task.yield()
        }

        try expectEqual(viewModel.state.onlineSummary, cachedSummary, "缓存首帧应立即进入已加载状态")

        loader.yield(
            RepositoryContentUpdate(
                content: overviewContent(
                    repository: repository,
                    summary: refreshedSummary
                ),
                freshness: .refreshed,
                isFinal: true
            )
        )
        loader.finish()
        await load.value

        try expectEqual(
            viewModel.state.onlineSummary,
            refreshedSummary,
            "刷新结果必须原位替换缓存内容"
        )
        try expectEqual(viewModel.state.loadPhase, .loaded, "后台刷新不得切回全屏加载")
    },
    TestCase("仓库总览后台刷新失败保留缓存并追加非阻塞错误") { @MainActor in
        let repository = overviewRepository()
        let cachedSummary = overviewSummary(repositoryID: repository.id)
        let loader = ControlledOverviewUpdatesLoader()
        let viewModel = RepositoryOverviewViewModel(
            repository: repository,
            account: overviewAccount(),
            token: "secret",
            loader: loader
        )

        let load = Task { @MainActor in
            await viewModel.load()
        }
        await loader.waitUntilConnected()
        loader.yield(
            RepositoryContentUpdate(
                content: overviewContent(
                    repository: repository,
                    summary: cachedSummary
                ),
                freshness: .cached,
                isFinal: false
            )
        )
        while viewModel.state.loadPhase != .loaded {
            await Task.yield()
        }
        loader.finish(throwing: OverviewLoaderError.failed)
        await load.value

        try expectEqual(viewModel.state.loadPhase, .loaded, "刷新失败不得覆盖缓存加载状态")
        try expectEqual(viewModel.state.onlineSummary, cachedSummary, "刷新失败必须保留旧摘要")
        try expect(
            viewModel.state.panelErrors.contains {
                $0.panel == .onlineSummary
                    && $0.message == "后台刷新失败，已保留缓存内容。"
            },
            "刷新失败应追加不泄露底层错误的非阻塞提示"
        )

        let retry = Task { @MainActor in
            await viewModel.load()
        }
        await loader.waitUntilConnectionCount(2)
        try expectEqual(
            viewModel.state.loadPhase,
            .loaded,
            "已有缓存内容时重试不得闪回全屏加载"
        )
        loader.finish(throwing: OverviewLoaderError.failed)
        await retry.value
    },
    TestCase("仓库总览加载取消不污染状态且允许重新加载") { @MainActor in
        let repository = overviewRepository()
        let loader = PausableOverviewLoader()
        let viewModel = RepositoryOverviewViewModel(
            repository: repository,
            account: overviewAccount(),
            token: "secret",
            loader: loader
        )
        let stateBeforeLoad = viewModel.state

        let cancelledLoad = Task { @MainActor in
            await viewModel.load()
        }
        while await loader.loadCount < 1 {
            await Task.yield()
        }
        cancelledLoad.cancel()
        await loader.resumeNext(
            with: overviewContent(repository: repository)
        )
        await cancelledLoad.value

        try expectEqual(
            viewModel.state,
            stateBeforeLoad,
            "取消不得写入成功、失败或残留加载状态"
        )

        let retryLoad = Task { @MainActor in
            await viewModel.load()
        }
        while await loader.loadCount < 2 {
            await Task.yield()
        }
        await loader.resumeNext(
            with: overviewContent(repository: repository)
        )
        await retryLoad.value

        try expectEqual(
            viewModel.state.loadPhase,
            .loaded,
            "取消后重新加载应成功"
        )
    },
    TestCase("仓库总览失败可重试且成功后去重") { @MainActor in
        let repository = overviewRepository()
        let loader = OverviewLoaderStub(
            outcomes: [
                .failure(.failed),
                .success(overviewContent(repository: repository))
            ]
        )
        let viewModel = RepositoryOverviewViewModel(
            repository: repository,
            account: overviewAccount(),
            token: "secret",
            loader: loader
        )

        await viewModel.load()
        try expectEqual(
            viewModel.state.loadPhase,
            .failed(message: "暂时无法加载仓库总览，请稍后重试。"),
            "加载失败应使用不泄露底层信息的稳定提示"
        )
        try expectEqual(
            viewModel.state.retryAction,
            WorkspaceRetryAction(
                title: "重试",
                accessibilityLabel: "重新加载仓库总览",
                accessibilityIdentifier: "workspace.repository.overview.retry"
            ),
            "总览失败状态应提供稳定且可访问的真实重试动作"
        )

        await viewModel.load()
        await viewModel.load()

        try expectEqual(viewModel.state.loadPhase, .loaded, "失败后应允许成功重试")
        let loadCount = await loader.currentLoadCount()
        try expectEqual(
            loadCount,
            2,
            "成功后重复调用不得重新加载"
        )
    }
]

private enum OverviewLoaderError: Error, Sendable {
    case failed
}

private final class ControlledOverviewUpdatesLoader:
    RepositoryContentLoading,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var continuation:
        AsyncThrowingStream<RepositoryContentUpdate, Error>.Continuation?
    private var connectionCount = 0

    func repositoryContent(
        repository _: Repository,
        account _: GitHubAccount,
        token _: String
    ) async throws -> RepositoryContent {
        throw OverviewLoaderError.failed
    }

    func repositoryContentUpdates(
        repository _: Repository,
        account _: GitHubAccount,
        token _: String
    ) -> AsyncThrowingStream<RepositoryContentUpdate, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock {
                self.continuation = continuation
                self.connectionCount += 1
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock {
                    self?.continuation = nil
                }
            }
        }
    }

    func waitUntilConnected() async {
        while lock.withLock({ continuation == nil }) {
            await Task.yield()
        }
    }

    func waitUntilConnectionCount(_ expectedCount: Int) async {
        while lock.withLock({ connectionCount < expectedCount }) {
            await Task.yield()
        }
    }

    func yield(_ update: RepositoryContentUpdate) {
        lock.withLock { continuation }?.yield(update)
    }

    func finish(throwing error: Error? = nil) {
        lock.withLock { continuation }?.finish(throwing: error)
    }
}

private actor OverviewLoaderStub: RepositoryContentLoading {
    enum Outcome: Sendable {
        case success(RepositoryContent)
        case failure(OverviewLoaderError)
    }

    private var outcomes: [Outcome]
    private var loadCount = 0

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func repositoryContent(
        repository _: Repository,
        account _: GitHubAccount,
        token _: String
    ) async throws -> RepositoryContent {
        loadCount += 1
        guard !outcomes.isEmpty else {
            throw OverviewLoaderError.failed
        }
        switch outcomes.removeFirst() {
        case let .success(content):
            return content
        case let .failure(error):
            throw error
        }
    }

    func currentLoadCount() -> Int {
        loadCount
    }
}

private actor PausableOverviewLoader: RepositoryContentLoading {
    private(set) var loadCount = 0
    private var continuations: [
        CheckedContinuation<RepositoryContent, Never>
    ] = []

    func repositoryContent(
        repository _: Repository,
        account _: GitHubAccount,
        token _: String
    ) async throws -> RepositoryContent {
        loadCount += 1
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeNext(with content: RepositoryContent) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: content)
    }
}

private func overviewAccount() -> GitHubAccount {
    GitHubAccount(
        id: "overview-account",
        login: "lele",
        name: "Lele",
        avatarURL: URL(string: "https://avatars.example/lele.png"),
        serverURL: URL(string: "https://github.example")!,
        kind: .enterprise,
        scopes: ["repo"]
    )
}

private func overviewRepository(
    cloneURL: URL = URL(
        string: "https://github.example/GitMate/mac-client.git"
    )!
) -> Repository {
    Repository(
        id: 101,
        name: "mac-client",
        fullName: "GitMate/mac-client",
        isPrivate: true,
        defaultBranch: "main",
        sizeInKilobytes: 4_096,
        cloneURL: cloneURL,
        ownerAvatarURL: URL(
            string: "https://avatars.example/GitMate.png?token=avatar-secret"
        )
    )
}

private func overviewSummary(
    repositoryID: Int64
) -> RepositoryOnlineSummary {
    RepositoryOnlineSummary(
        repositoryID: repositoryID,
        primaryLanguage: "Swift",
        openIssueCount: 8,
        openPullRequestCount: 3,
        failedWorkflowCount: 1,
        remoteUpdatedAt: Date(timeIntervalSince1970: 3_000)
    )
}

private func overviewContent(
    repository: Repository,
    availability: LocalRepositoryAvailability = .available,
    status: LocalRepositoryStatus? = LocalRepositoryStatus(
        branch: "main",
        upstream: "origin/main",
        ahead: 0,
        behind: 0,
        stagedCount: 0,
        unstagedCount: 0,
        untrackedCount: 0,
        conflictCount: 0
    ),
    summary: RepositoryOnlineSummary? = nil,
    recentCommits: [GitCommit] = [],
    readme: GitHubREADME? = nil
) -> RepositoryContent {
    RepositoryContent(
        repository: repository,
        localRecord: LocalRepositoryRecord(
            repository: repository,
            localURL: URL(filePath: "/tmp/\(repository.name)"),
            availability: availability,
            localSizeInBytes: 7_168,
            lastInspectedAt: Date(timeIntervalSince1970: 2_000)
        ),
        localStatus: status,
        onlineSummary: summary,
        recentCommits: recentCommits,
        readme: readme,
        connectivity: .online,
        panelErrors: availability == .available
            ? []
            : [
                WorkspacePanelError(
                    panel: .localRepository,
                    repositoryID: repository.id,
                    message: "本地仓库不存在，请重新同步。"
                )
            ]
    )
}

private func overviewCommit(index: Int) -> GitCommit {
    GitCommit(
        shortHash: "abc\(index)",
        fullHash: "full-hash-\(index)",
        subject: "提交 \(index)",
        authorName: "Lele",
        authorEmail: "lele@example.com",
        authoredAt: Date(timeIntervalSince1970: Double(1_000 + index)),
        parentHashes: [],
        decorations: index == 1 ? ["HEAD -> main"] : []
    )
}
