import Foundation
import GitMateCore

let dashboardViewModelTests = [
    TestCase("工作台按固定优先级选择今日焦点并派生仓库指标") { @MainActor in
        let account = dashboardAccount()
        let repositories = [
            dashboardRepository(id: 1, fullName: "octo/healthy"),
            dashboardRepository(id: 2, fullName: "octo/missing"),
            dashboardRepository(id: 3, fullName: "octo/status-error")
        ]
        let duplicateSyncError = WorkspacePanelError(
            panel: .localRepository,
            repositoryID: 2,
            message: "本地仓库不存在。"
        )
        let statusError = WorkspacePanelError(
            panel: .localStatus,
            repositoryID: 3,
            message: "无法读取状态。"
        )
        let contents = [
            dashboardRepositoryContent(
                repository: repositories[0],
                availability: .available,
                status: dashboardStatus(staged: 1, unstaged: 2),
                onlineSummary: dashboardOnlineSummary(
                    repositoryID: 1,
                    issues: 4,
                    pullRequests: 7,
                    failedWorkflows: 2
                )
            ),
            dashboardRepositoryContent(
                repository: repositories[1],
                availability: .missing,
                panelErrors: [duplicateSyncError]
            ),
            dashboardRepositoryContent(
                repository: repositories[2],
                availability: .available,
                panelErrors: [statusError]
            )
        ]
        let loader = DashboardLoaderFixture(
            content: WorkspaceDashboardContent(
                account: account,
                repositories: contents,
                connectivity: .online,
                panelErrors: [duplicateSyncError, duplicateSyncError, statusError]
            )
        )
        let viewModel = DashboardViewModel(
            account: account,
            repositories: repositories,
            token: "不得进入状态的令牌",
            loader: loader
        )

        await viewModel.load()

        try expectEqual(viewModel.state.focus.kind, .syncFailure, "同步失败应优先于 Actions 失败")
        try expectEqual(viewModel.state.focus.itemCount, 1, "同步失败仓库应按仓库去重")
        try expectEqual(viewModel.state.repositoryCount, 3, "仓库总数应取已加载内容数")
        try expectEqual(viewModel.state.healthyRepositoryCount, 1, "本地状态面板失败不应计为健康")
        try expectEqual(viewModel.state.syncFailureCount, 1, "重复面板错误不应重复累计")
        try expectEqual(viewModel.state.localChangeCount, 3, "应汇总暂存和未暂存改动")
        try expectEqual(viewModel.state.openIssueCount, 4, "应汇总在线 Issue")
        try expectEqual(viewModel.state.openPullRequestCount, 7, "应汇总在线 PR")
        try expectEqual(viewModel.state.failedWorkflowCount, 2, "应汇总失败工作流")
    },
    TestCase("授权失效优先于所有仓库事项") { @MainActor in
        let account = dashboardAccount()
        let repository = dashboardRepository(id: 1, fullName: "octo/app")
        let content = dashboardRepositoryContent(
            repository: repository,
            availability: .missing,
            status: dashboardStatus(staged: 4),
            onlineSummary: dashboardOnlineSummary(
                repositoryID: 1,
                pullRequests: 5,
                failedWorkflows: 3
            ),
            connectivity: .authorizationRequired
        )
        let loader = DashboardLoaderFixture(
            content: WorkspaceDashboardContent(
                account: account,
                repositories: [content],
                connectivity: .authorizationRequired,
                panelErrors: content.panelErrors
            )
        )
        let viewModel = DashboardViewModel(
            account: account,
            repositories: [repository],
            token: "secret",
            loader: loader
        )

        await viewModel.load()

        try expectEqual(viewModel.state.focus.kind, .authorizationRequired, "授权失效必须是最高优先级")
        try expectEqual(viewModel.state.focus.itemCount, nil, "授权失效不是虚构的待处理数量")
    },
    TestCase("在线摘要失败时仍显示完整本地指标") { @MainActor in
        let account = dashboardAccount()
        let repository = dashboardRepository(id: 1, fullName: "octo/offline")
        let onlineError = WorkspacePanelError(
            panel: .onlineSummary,
            repositoryID: repository.id,
            message: "当前离线。"
        )
        let content = dashboardRepositoryContent(
            repository: repository,
            availability: .available,
            status: dashboardStatus(staged: 1, unstaged: 1, untracked: 1, conflicts: 1),
            connectivity: .offline,
            panelErrors: [onlineError]
        )
        let loader = DashboardLoaderFixture(
            content: WorkspaceDashboardContent(
                account: account,
                repositories: [content],
                connectivity: .offline,
                panelErrors: [onlineError]
            )
        )
        let viewModel = DashboardViewModel(
            account: account,
            repositories: [repository],
            token: "secret",
            loader: loader
        )

        await viewModel.load()

        try expectEqual(viewModel.state.localChangeCount, 4, "离线时应保留四类本地改动")
        try expectEqual(viewModel.state.connectivity, .offline, "应保留离线状态")
        try expectEqual(viewModel.state.focus.kind, .localChanges, "离线本身不应遮蔽本地待处理事项")
    },
    TestCase("跨仓库活动按时间倒序且最多保留十二条") { @MainActor in
        let account = dashboardAccount()
        let firstRepository = dashboardRepository(id: 1, fullName: "octo/first")
        let secondRepository = dashboardRepository(id: 2, fullName: "octo/second")
        let baseDate = Date(timeIntervalSince1970: 1_000)
        let firstCommits = (0..<7).map {
            dashboardCommit(index: $0, authoredAt: baseDate.addingTimeInterval(Double($0)))
        }
        let secondCommits = (7..<15).map {
            dashboardCommit(index: $0, authoredAt: baseDate.addingTimeInterval(Double($0)))
        }
        let loader = DashboardLoaderFixture(
            content: WorkspaceDashboardContent(
                account: account,
                repositories: [
                    dashboardRepositoryContent(
                        repository: firstRepository,
                        recentCommits: firstCommits
                    ),
                    dashboardRepositoryContent(
                        repository: secondRepository,
                        recentCommits: secondCommits
                    )
                ],
                connectivity: .online,
                panelErrors: []
            )
        )
        let viewModel = DashboardViewModel(
            account: account,
            repositories: [firstRepository, secondRepository],
            token: "secret",
            loader: loader
        )

        await viewModel.load()

        try expectEqual(viewModel.state.activities.count, 12, "活动只应保留最新十二条")
        try expectEqual(viewModel.state.activities.first?.commit.fullHash, "hash-14", "最新提交应排在第一条")
        try expectEqual(viewModel.state.activities.last?.commit.fullHash, "hash-3", "第十二条应是正确的时间边界")
        try expectEqual(viewModel.state.activities.first?.repositoryID, 2, "活动应保留来源仓库 ID")
        try expectEqual(viewModel.state.activities.first?.repositoryFullName, "octo/second", "活动应保留来源仓库全名")
        try expectEqual(viewModel.state.focus.kind, .recentActivity, "无待处理事项时应展示普通活动")
        try expectEqual(viewModel.state.focus.itemCount, nil, "普通活动不应伪装成待处理数量")
    },
    TestCase("没有事项或活动时使用中性焦点") { @MainActor in
        let account = dashboardAccount()
        let loader = DashboardLoaderFixture(
            content: WorkspaceDashboardContent(
                account: account,
                repositories: [],
                connectivity: .online,
                panelErrors: []
            )
        )
        let viewModel = DashboardViewModel(
            account: account,
            repositories: [],
            token: "secret",
            loader: loader
        )

        await viewModel.load()

        try expectEqual(viewModel.state.focus.kind, .neutral, "空工作台应展示中性焦点")
        try expectEqual(viewModel.state.focus.itemCount, nil, "中性焦点不得制造待处理数量")
    },
    TestCase("并发加载只发起一次请求并阻止旧结果覆盖") { @MainActor in
        let account = dashboardAccount()
        let repository = dashboardRepository(id: 1, fullName: "octo/app")
        let loader = DashboardLoaderFixture(
            content: WorkspaceDashboardContent(
                account: account,
                repositories: [dashboardRepositoryContent(repository: repository)],
                connectivity: .online,
                panelErrors: []
            ),
            delayNanoseconds: 40_000_000
        )
        let viewModel = DashboardViewModel(
            account: account,
            repositories: [repository],
            token: "secret",
            loader: loader
        )

        async let first: Void = viewModel.load()
        async let second: Void = viewModel.load()
        _ = await (first, second)

        let loadCount = await loader.loadCount
        try expectEqual(loadCount, 1, "并发 load 不应重复请求")
        try expectEqual(viewModel.state.repositoryCount, 1, "唯一请求结果应稳定写入状态")
    },
    TestCase("加载错误转为稳定状态且不泄露令牌") { @MainActor in
        let account = dashboardAccount()
        let secret = "ghp_do-not-leak"
        let loader = DashboardLoaderFixture(error: DashboardFixtureError.failed(secret))
        let viewModel = DashboardViewModel(
            account: account,
            repositories: [],
            token: secret,
            loader: loader
        )

        await viewModel.load()

        try expectEqual(
            viewModel.state.loadPhase,
            .failed(message: "暂时无法加载工作台，请稍后重试。"),
            "底层错误应转换为稳定提示"
        )
        try expect(
            !String(describing: viewModel.state).contains(secret),
            "DashboardState 不得包含访问令牌"
        )
    },
    TestCase("面板错误进入状态前移除令牌") { @MainActor in
        let account = dashboardAccount()
        let secret = "ghp_panel-secret"
        let panelError = WorkspacePanelError(
            panel: .onlineSummary,
            repositoryID: nil,
            message: "请求携带 \(secret) 时失败"
        )
        let loader = DashboardLoaderFixture(
            content: WorkspaceDashboardContent(
                account: account,
                repositories: [],
                connectivity: .offline,
                panelErrors: [panelError]
            )
        )
        let viewModel = DashboardViewModel(
            account: account,
            repositories: [],
            token: secret,
            loader: loader
        )

        await viewModel.load()

        try expect(
            !String(describing: viewModel.state).contains(secret),
            "面板错误不得把访问令牌带入 DashboardState"
        )
        try expectEqual(
            viewModel.state.panelErrors.first?.message,
            "请求携带 •••• 时失败",
            "面板错误应保留可诊断上下文并仅隐藏令牌"
        )
    }
]

private actor DashboardLoaderFixture: WorkspaceDashboardLoading {
    private let content: WorkspaceDashboardContent?
    private let error: (any Error)?
    private let delayNanoseconds: UInt64
    private(set) var loadCount = 0

    init(
        content: WorkspaceDashboardContent? = nil,
        error: (any Error)? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.content = content
        self.error = error
        self.delayNanoseconds = delayNanoseconds
    }

    func dashboard(
        account: GitHubAccount,
        repositories: [Repository],
        token: String
    ) async throws -> WorkspaceDashboardContent {
        loadCount += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let error {
            throw error
        }
        guard let content else {
            throw DashboardFixtureError.missingContent
        }
        return content
    }
}

private enum DashboardFixtureError: Error {
    case failed(String)
    case missingContent
}

private func dashboardAccount() -> GitHubAccount {
    GitHubAccount(
        id: "account-1",
        login: "octocat",
        name: "Octo Cat",
        avatarURL: URL(string: "https://avatars.example/octocat.png"),
        serverURL: URL(string: "https://github.example")!,
        kind: .enterprise,
        scopes: ["repo"]
    )
}

private func dashboardRepository(id: Int64, fullName: String) -> Repository {
    Repository(
        id: id,
        name: fullName.split(separator: "/").last.map(String.init) ?? fullName,
        fullName: fullName,
        isPrivate: false,
        defaultBranch: "main",
        sizeInKilobytes: 1_024,
        cloneURL: URL(string: "https://github.example/\(fullName).git")!,
        ownerAvatarURL: nil
    )
}

private func dashboardStatus(
    staged: Int = 0,
    unstaged: Int = 0,
    untracked: Int = 0,
    conflicts: Int = 0
) -> LocalRepositoryStatus {
    LocalRepositoryStatus(
        branch: "main",
        upstream: "origin/main",
        ahead: 0,
        behind: 0,
        stagedCount: staged,
        unstagedCount: unstaged,
        untrackedCount: untracked,
        conflictCount: conflicts
    )
}

private func dashboardOnlineSummary(
    repositoryID: Int64,
    issues: Int = 0,
    pullRequests: Int = 0,
    failedWorkflows: Int = 0
) -> RepositoryOnlineSummary {
    RepositoryOnlineSummary(
        repositoryID: repositoryID,
        primaryLanguage: "Swift",
        openIssueCount: issues,
        openPullRequestCount: pullRequests,
        failedWorkflowCount: failedWorkflows,
        remoteUpdatedAt: nil
    )
}

private func dashboardRepositoryContent(
    repository: Repository,
    availability: LocalRepositoryAvailability = .available,
    status: LocalRepositoryStatus? = dashboardStatus(),
    onlineSummary: RepositoryOnlineSummary? = nil,
    recentCommits: [GitCommit] = [],
    connectivity: WorkspaceConnectivity = .online,
    panelErrors: [WorkspacePanelError] = []
) -> RepositoryContent {
    RepositoryContent(
        repository: repository,
        localRecord: LocalRepositoryRecord(
            repository: repository,
            localURL: URL(filePath: "/tmp/\(repository.name)"),
            availability: availability,
            localSizeInBytes: 1_024,
            lastInspectedAt: Date(timeIntervalSince1970: 1_000)
        ),
        localStatus: status,
        onlineSummary: onlineSummary,
        recentCommits: recentCommits,
        readme: nil,
        connectivity: connectivity,
        panelErrors: panelErrors
    )
}

private func dashboardCommit(index: Int, authoredAt: Date) -> GitCommit {
    GitCommit(
        shortHash: "h\(index)",
        fullHash: "hash-\(index)",
        subject: "提交 \(index)",
        authorName: "开发者",
        authorEmail: "dev@example.com",
        authoredAt: authoredAt,
        parentHashes: [],
        decorations: []
    )
}
