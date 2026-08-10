import Foundation
import GitMateCore

private let workspaceAccount = GitHubAccount(
    id: "github.com:1",
    login: "lele",
    name: "Lele",
    avatarURL: nil,
    serverURL: URL(string: "https://github.com")!,
    kind: .githubDotCom,
    scopes: ["repo"]
)

private let workspaceRepository = Repository(
    id: 101,
    name: "mac-client",
    fullName: "GitMate/mac-client",
    isPrivate: true,
    defaultBranch: "main",
    sizeInKilobytes: 2_457_600,
    cloneURL: URL(string: "https://github.com/GitMate/mac-client.git")!,
    ownerAvatarURL: nil
)

private let workspaceDirectory = URL(
    fileURLWithPath: "/tmp/GitMate-WorkspaceTests",
    isDirectory: true
)

private final class WorkspaceLocalGitFake:
    LocalRepositoryGitService,
    @unchecked Sendable
{
    var branchValues: [GitBranch] = []
    var tagValues: [GitTag] = []
    var comparisonValue = BranchComparison(aheadBy: 0, behindBy: 0)
    private(set) var deletedBranches: [String] = []
    private(set) var comparisons: [(local: String, remote: String)] = []

    func branches(at directory: URL) async throws -> [GitBranch] { branchValues }
    func tags(at directory: URL) async throws -> [GitTag] { tagValues }
    func workingTreeStatus(at directory: URL) async throws -> WorkingTreeStatus {
        WorkingTreeStatus(changedFiles: [])
    }
    func comparison(local: String, remote: String, at directory: URL) async throws -> BranchComparison {
        comparisons.append((local, remote))
        return comparisonValue
    }
    func createBranch(_ name: String, startPoint: String, at directory: URL) async throws {}
    func checkoutBranch(_ name: String, at directory: URL) async throws {}
    func mergeBranch(_ source: String, at directory: URL) async throws {}
    func setUpstream(branch: String, upstream: String, at directory: URL) async throws {}
    func pushBranch(_ name: String, remote: String, at directory: URL) async throws {}
    func deleteBranch(
        _ name: String,
        remote: String?,
        force: Bool,
        at directory: URL
    ) async throws {
        deletedBranches.append(remote.map { "\($0)/\(name)" } ?? name)
    }
    func createTag(_ name: String, target: String, message: String?, at directory: URL) async throws {}
    func pushTag(_ name: String, remote: String, at directory: URL) async throws {}
    func fetchTags(remote: String, at directory: URL) async throws {}
    func deleteTag(_ name: String, remote: String?, at directory: URL) async throws {}
}

private final class WorkspaceBranchesAPIFake:
    GitHubBranchesAPI,
    @unchecked Sendable
{
    var branchValues: [GitBranch] = []
    var tagValues: [GitTag] = []
    var rulesetValues: [RepositoryRuleset] = []
    var error: GitHubAPIError?

    func remoteBranches(token: String) async throws -> [GitBranch] {
        if let error { throw error }
        return branchValues
    }
    func remoteTags(token: String) async throws -> [GitTag] {
        if let error { throw error }
        return tagValues
    }
    func branchProtection(name: String, token: String) async throws -> BranchProtectionSummary? { nil }
    func rulesets(token: String) async throws -> [RepositoryRuleset] {
        if let error { throw error }
        return rulesetValues
    }
    func ruleset(id: Int64, token: String) async throws -> RepositoryRuleset {
        try rulesetValues.first(where: { $0.id == id }) ?? {
            throw GitHubAPIError.notFound("不存在")
        }()
    }
    func createRuleset(
        _ input: RepositoryRulesetInput,
        token: String
    ) async throws -> RepositoryRuleset {
        RepositoryRuleset(
            id: 1,
            name: input.name,
            enforcement: input.enforcement,
            source: .repository
        )
    }
    func updateRuleset(
        _ ruleset: RepositoryRuleset,
        input: RepositoryRulesetInput,
        token: String
    ) async throws -> RepositoryRuleset {
        ruleset
    }
    func deleteRuleset(_ ruleset: RepositoryRuleset, token: String) async throws {}
    func tagReleaseSummary(name: String, token: String) async throws -> TagReleaseSummary? { nil }
}

private final class WorkspaceIssuesAPIFake:
    GitHubIssuesAPI,
    @unchecked Sendable
{
    var createError: GitHubAPIError?
    var commentError: GitHubAPIError?
    var milestoneError: GitHubAPIError?
    var firstIssuesPage = GitHubPage<GitHubIssue>(
        items: [],
        nextPageURL: nil
    )
    var additionalIssuesPage = GitHubPage<GitHubIssue>(
        items: [],
        nextPageURL: nil
    )
    var additionalPageDelayNanoseconds: UInt64 = 0
    private(set) var createdCommentBodies: [String] = []
    private(set) var requestedIssuePageURLs: [URL?] = []

    func issues(
        query: IssueQuery,
        pageURL: URL?,
        token: String
    ) async throws -> GitHubPage<GitHubIssue> {
        requestedIssuePageURLs.append(pageURL)
        if pageURL != nil {
            if additionalPageDelayNanoseconds > 0 {
                try await Task.sleep(
                    nanoseconds: additionalPageDelayNanoseconds
                )
            }
            return additionalIssuesPage
        }
        return firstIssuesPage
    }
    func issue(number: Int, token: String) async throws -> GitHubIssue {
        issueFixture(number: number)
    }
    func timeline(number: Int, token: String) async throws -> [IssueTimelineEvent] { [] }
    func comments(number: Int, token: String) async throws -> [IssueComment] { [] }
    func createIssue(_ input: CreateIssueInput, token: String) async throws -> GitHubIssue {
        if let createError { throw createError }
        return issueFixture(number: 91, title: input.title)
    }
    func updateIssue(
        number: Int,
        input: UpdateIssueInput,
        token: String
    ) async throws -> GitHubIssue {
        issueFixture(number: number, title: input.title)
    }
    func createComment(number: Int, body: String, token: String) async throws -> IssueComment {
        createdCommentBodies.append(body)
        if let commentError { throw commentError }
        return IssueComment(
            id: 1,
            body: body,
            author: IssueUser(login: "lele"),
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }
    func updateComment(id: Int64, body: String, token: String) async throws -> IssueComment {
        IssueComment(
            id: id,
            body: body,
            author: IssueUser(login: "lele"),
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }
    func lockIssue(number: Int, reason: IssueLockReason?, token: String) async throws {}
    func unlockIssue(number: Int, token: String) async throws {}
    func milestones(state: IssueState?, token: String) async throws -> [IssueMilestone] { [] }
    func createMilestone(_ input: MilestoneInput, token: String) async throws -> IssueMilestone {
        if let milestoneError { throw milestoneError }
        return IssueMilestone(id: 1, number: 1, title: input.title, state: input.state, openIssues: 0, closedIssues: 0)
    }
    func updateMilestone(
        number: Int,
        input: MilestoneInput,
        token: String
    ) async throws -> IssueMilestone {
        if let milestoneError { throw milestoneError }
        return IssueMilestone(id: 1, number: number, title: input.title, state: input.state, openIssues: 0, closedIssues: 0)
    }
    func deleteMilestone(number: Int, token: String) async throws {}
    func labels(token: String) async throws -> [IssueLabel] { [] }
    func labelUsage(token: String) async throws -> [String: IssueLabelUsage] {
        [:]
    }
    func createLabel(_ input: IssueLabelInput, token: String) async throws -> IssueLabel {
        IssueLabel(id: 1, name: input.name, color: input.color)
    }
    func updateLabel(name: String, input: IssueLabelInput, token: String) async throws -> IssueLabel {
        IssueLabel(id: 1, name: input.name, color: input.color)
    }
    func deleteLabel(name: String, token: String) async throws {}

    private func issueFixture(
        number: Int,
        title: String = "议题"
    ) -> GitHubIssue {
        GitHubIssue(
            id: Int64(number),
            number: number,
            title: title,
            body: nil,
            state: .open,
            author: IssueUser(login: "lele")
        )
    }
}

private final class CancellableWorkspaceIssuesAPIFake:
    GitHubIssuesAPI,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var pendingIssuesRequest:
        CheckedContinuation<GitHubPage<GitHubIssue>, Error>?
    private var didStartIssuesRequest = false
    private var didObserveCancellation = false

    private let firstIssuesPage: GitHubPage<GitHubIssue>?

    init(firstIssuesPage: GitHubPage<GitHubIssue>? = nil) {
        self.firstIssuesPage = firstIssuesPage
    }

    var issuesRequestStarted: Bool {
        lock.withLock { didStartIssuesRequest }
    }

    var issuesRequestObservedCancellation: Bool {
        lock.withLock { didObserveCancellation }
    }

    func completeIssuesRequest() {
        let continuation = lock.withLock {
            let continuation = pendingIssuesRequest
            pendingIssuesRequest = nil
            return continuation
        }
        continuation?.resume(
            returning: GitHubPage(
                items: [
                    GitHubIssue(
                        id: 99,
                        number: 99,
                        title: "过期议题",
                        body: nil,
                        state: .open,
                        author: IssueUser(login: "lele")
                    )
                ],
                nextPageURL: nil
            )
        )
    }

    func issues(
        query: IssueQuery,
        pageURL: URL?,
        token: String
    ) async throws -> GitHubPage<GitHubIssue> {
        if pageURL == nil, let firstIssuesPage {
            return firstIssuesPage
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    didStartIssuesRequest = true
                    pendingIssuesRequest = continuation
                }
            }
        } onCancel: {
            lock.withLock {
                didObserveCancellation = true
            }
        }
    }

    func issue(number: Int, token: String) async throws -> GitHubIssue {
        throw CancellationTestError.unexpectedRequest
    }

    func timeline(
        number: Int,
        token: String
    ) async throws -> [IssueTimelineEvent] {
        throw CancellationTestError.unexpectedRequest
    }

    func comments(
        number: Int,
        token: String
    ) async throws -> [IssueComment] {
        throw CancellationTestError.unexpectedRequest
    }

    func createIssue(
        _ input: CreateIssueInput,
        token: String
    ) async throws -> GitHubIssue {
        throw CancellationTestError.unexpectedRequest
    }

    func updateIssue(
        number: Int,
        input: UpdateIssueInput,
        token: String
    ) async throws -> GitHubIssue {
        throw CancellationTestError.unexpectedRequest
    }

    func createComment(
        number: Int,
        body: String,
        token: String
    ) async throws -> IssueComment {
        throw CancellationTestError.unexpectedRequest
    }

    func updateComment(
        id: Int64,
        body: String,
        token: String
    ) async throws -> IssueComment {
        throw CancellationTestError.unexpectedRequest
    }

    func lockIssue(
        number: Int,
        reason: IssueLockReason?,
        token: String
    ) async throws {
        throw CancellationTestError.unexpectedRequest
    }

    func unlockIssue(number: Int, token: String) async throws {
        throw CancellationTestError.unexpectedRequest
    }

    func milestones(
        state: IssueState?,
        token: String
    ) async throws -> [IssueMilestone] {
        throw CancellationTestError.unexpectedRequest
    }

    func createMilestone(
        _ input: MilestoneInput,
        token: String
    ) async throws -> IssueMilestone {
        throw CancellationTestError.unexpectedRequest
    }

    func updateMilestone(
        number: Int,
        input: MilestoneInput,
        token: String
    ) async throws -> IssueMilestone {
        throw CancellationTestError.unexpectedRequest
    }

    func deleteMilestone(number: Int, token: String) async throws {
        throw CancellationTestError.unexpectedRequest
    }

    func labels(token: String) async throws -> [IssueLabel] {
        throw CancellationTestError.unexpectedRequest
    }

    func labelUsage(token: String) async throws -> [String: IssueLabelUsage] {
        throw CancellationTestError.unexpectedRequest
    }

    func createLabel(
        _ input: IssueLabelInput,
        token: String
    ) async throws -> IssueLabel {
        throw CancellationTestError.unexpectedRequest
    }

    func updateLabel(
        name: String,
        input: IssueLabelInput,
        token: String
    ) async throws -> IssueLabel {
        throw CancellationTestError.unexpectedRequest
    }

    func deleteLabel(name: String, token: String) async throws {
        throw CancellationTestError.unexpectedRequest
    }
}

private enum CancellationTestError: Error {
    case unexpectedRequest
}

private actor EmptyLabelMergeAPI: LabelMergeAPI {
    func issueNumbers(labelName: String, token: String) async throws -> [Int] { [] }
    func addLabels(to issueNumber: Int, names: [String], token: String) async throws {}
    func removeLabel(from issueNumber: Int, name: String, token: String) async throws {}
    func deleteLabel(name: String, token: String) async throws {}
}

private actor WorkspaceLabelMergerFake: LabelMerging {
    struct Call: Sendable {
        let source: String
        let target: String
        let completedIssueNumbers: [Int]
    }

    private(set) var calls: [Call] = []

    func merge(
        source: String,
        into target: String,
        token: String,
        completedIssueNumbers: [Int]
    ) async throws -> LabelMergeProgress {
        calls.append(
            Call(
                source: source,
                target: target,
                completedIssueNumbers: completedIssueNumbers
            )
        )
        return LabelMergeProgress(
            source: source,
            target: target,
            completedIssueNumbers: completedIssueNumbers + [91],
            failedIssueNumbers: [92]
        )
    }

    func snapshot() -> [Call] {
        calls
    }
}

@MainActor
private func makeWorkspaceViewModel(
    localGit: WorkspaceLocalGitFake = WorkspaceLocalGitFake(),
    branchesAPI: WorkspaceBranchesAPIFake = WorkspaceBranchesAPIFake(),
    issuesAPI: WorkspaceIssuesAPIFake = WorkspaceIssuesAPIFake(),
    persistence: InMemoryWorkspacePersistenceStore = InMemoryWorkspacePersistenceStore(),
    labelMergeService: (any LabelMerging)? = nil
) throws -> (
    RepositoryWorkspaceViewModel,
    WorkspaceLocalGitFake,
    WorkspaceBranchesAPIFake,
    WorkspaceIssuesAPIFake,
    InMemoryWorkspacePersistenceStore
) {
    let credentials = InMemoryCredentialStore()
    try credentials.save(token: "secret", accountID: workspaceAccount.id)
    let context = RepositoryWorkspaceContext(
        account: workspaceAccount,
        repository: workspaceRepository,
        localDirectory: workspaceDirectory,
        tokenAccountID: workspaceAccount.id
    )
    let dependencies = RepositoryWorkspaceDependencies(
        localGit: localGit,
        branchesAPI: branchesAPI,
        issuesAPI: issuesAPI,
        credentialStore: credentials,
        persistenceStore: persistence,
        labelMergeService: labelMergeService
            ?? LabelMergeService(api: EmptyLabelMergeAPI())
    )
    return (
        RepositoryWorkspaceViewModel(
            context: context,
            dependencies: dependencies
        ),
        localGit,
        branchesAPI,
        issuesAPI,
        persistence
    )
}

@MainActor
private func makeCancellableWorkspaceViewModel(
    issuesAPI: CancellableWorkspaceIssuesAPIFake
) throws -> RepositoryWorkspaceViewModel {
    let credentials = InMemoryCredentialStore()
    try credentials.save(token: "secret", accountID: workspaceAccount.id)
    return RepositoryWorkspaceViewModel(
        context: RepositoryWorkspaceContext(
            account: workspaceAccount,
            repository: workspaceRepository,
            localDirectory: workspaceDirectory,
            tokenAccountID: workspaceAccount.id
        ),
        dependencies: RepositoryWorkspaceDependencies(
            localGit: WorkspaceLocalGitFake(),
            branchesAPI: WorkspaceBranchesAPIFake(),
            issuesAPI: issuesAPI,
            credentialStore: credentials,
            persistenceStore: InMemoryWorkspacePersistenceStore(),
            labelMergeService: LabelMergeService(api: EmptyLabelMergeAPI())
        ),
        initialRoute: .issues
    )
}

private func waitForIssuesRequestStart(
    _ issuesAPI: CancellableWorkspaceIssuesAPIFake
) async throws {
    for _ in 0..<10_000 {
        if issuesAPI.issuesRequestStarted {
            return
        }
        await Task.yield()
    }
    throw TestFailure(description: "议题读取任务未在有界等待内开始")
}

let repositoryWorkspaceViewModelTests = [
    TestCase("加载分支时合并本地远端和保护状态") { @MainActor in
        let local = WorkspaceLocalGitFake()
        local.branchValues = [
            GitBranch(
                name: "main",
                localSHA: "abc",
                remoteSHA: nil,
                upstreamName: "origin/main"
            )
        ]
        let remote = WorkspaceBranchesAPIFake()
        remote.branchValues = [
            GitBranch(
                name: "main",
                localSHA: nil,
                remoteSHA: "def",
                upstreamName: nil,
                isProtected: true
            )
        ]
        let (viewModel, _, _, _, _) = try makeWorkspaceViewModel(
            localGit: local,
            branchesAPI: remote
        )

        await viewModel.loadCurrentRoute()

        let branch = try viewModel.state.branches.first ?? {
            throw TestFailure(description: "应加载 main 分支")
        }()
        try expectEqual(branch.localSHA, "abc", "应保留本地提交")
        try expectEqual(branch.remoteSHA, "def", "应合并远端提交")
        try expect(branch.isProtected, "应合并 GitHub 保护状态")
        try expect(branch.isDefault, "应使用仓库默认分支标记 main")
        try expectEqual(viewModel.state.status, .ready, "加载成功后应就绪")
    },
    TestCase("加载分支时计算真实领先落后数量") { @MainActor in
        let local = WorkspaceLocalGitFake()
        local.branchValues = [
            GitBranch(
                name: "main",
                localSHA: "local-sha",
                remoteSHA: nil,
                upstreamName: "origin/main"
            )
        ]
        local.comparisonValue = BranchComparison(aheadBy: 2, behindBy: 1)
        let remote = WorkspaceBranchesAPIFake()
        remote.branchValues = [
            GitBranch(
                name: "main",
                localSHA: nil,
                remoteSHA: "remote-sha",
                upstreamName: nil
            )
        ]
        let (viewModel, _, _, _, _) = try makeWorkspaceViewModel(
            localGit: local,
            branchesAPI: remote
        )

        await viewModel.loadCurrentRoute()

        let branch = try viewModel.state.branches.first ?? {
            throw TestFailure(description: "应加载 main 分支")
        }()
        try expectEqual(
            branch.comparison,
            BranchComparison(aheadBy: 2, behindBy: 1),
            "提交不一致时应通过 Git 计算领先落后"
        )
        try expectEqual(local.comparisons.count, 1, "每个不一致分支应比较一次")
        try expectEqual(local.comparisons.first?.local, "local-sha", "应比较精确本地提交")
        try expectEqual(local.comparisons.first?.remote, "remote-sha", "应比较精确远端提交")
    },
    TestCase("加载标签时合并本地与远端存在状态") { @MainActor in
        let local = WorkspaceLocalGitFake()
        local.tagValues = [
            GitTag(
                name: "v2.4.0",
                objectSHA: "same",
                kind: .annotated,
                existsLocally: true,
                existsRemotely: false,
                taggerName: "lele"
            )
        ]
        let remote = WorkspaceBranchesAPIFake()
        remote.tagValues = [
            GitTag(
                name: "v2.4.0",
                objectSHA: "same",
                kind: .annotated,
                existsLocally: false,
                existsRemotely: true
            ),
            GitTag(
                name: "nightly",
                objectSHA: "remote",
                kind: .lightweight,
                existsLocally: false,
                existsRemotely: true
            )
        ]
        let (viewModel, _, _, _, _) = try makeWorkspaceViewModel(
            localGit: local,
            branchesAPI: remote
        )
        viewModel.navigate(to: .tags)

        await viewModel.loadCurrentRoute()

        try expectEqual(viewModel.state.tags.map(\.name), ["nightly", "v2.4.0"], "应合并并排序标签")
        let synchronized = try viewModel.state.tags.first {
            $0.name == "v2.4.0"
        } ?? {
            throw TestFailure(description: "应保留同名标签")
        }()
        try expectEqual(synchronized.remoteStatus, .synchronized, "同名标签应标记已同步")
        try expectEqual(synchronized.taggerName, "lele", "应保留本地附注元数据")
        let remoteOnly = try viewModel.state.tags.first {
            $0.name == "nightly"
        } ?? {
            throw TestFailure(description: "应加载仅远端标签")
        }()
        try expectEqual(remoteOnly.remoteStatus, .remoteOnly, "仅远端标签应正确标记")
    },
    TestCase("删除分支先产生确认请求确认后才执行") { @MainActor in
        let (viewModel, local, _, _, _) = try makeWorkspaceViewModel()

        viewModel.requestDeleteLocalBranch(name: "old", force: true)

        try expectEqual(local.deletedBranches, [], "请求阶段不得执行删除")
        guard case let .deleteLocalBranch(name, force) =
            viewModel.pendingDangerousOperation?.action
        else {
            throw TestFailure(description: "应生成本地分支删除确认")
        }
        try expectEqual(name, "old", "确认请求应锁定精确分支")
        try expect(force, "确认请求应保留强制删除选项")

        await viewModel.confirmDangerousOperation()

        try expectEqual(local.deletedBranches, ["old"], "确认后才应执行删除")
        try expectEqual(viewModel.pendingDangerousOperation, nil, "完成后应清空确认")
    },
    TestCase("不同标签合并任务不能复用旧任务进度") { @MainActor in
        let merger = WorkspaceLabelMergerFake()
        let (viewModel, _, _, _, _) = try makeWorkspaceViewModel(
            labelMergeService: merger
        )

        viewModel.requestMergeLabels(
            source: "legacy",
            target: "bug",
            affectedIssues: 2
        )
        await viewModel.confirmDangerousOperation()
        viewModel.requestMergeLabels(
            source: "needs-review",
            target: "triage",
            affectedIssues: 2
        )
        await viewModel.confirmDangerousOperation()

        let calls = await merger.snapshot()
        try expectEqual(calls.count, 2, "应执行两次独立合并")
        try expectEqual(
            calls[1].completedIssueNumbers,
            [],
            "新来源和目标不得继承旧任务已完成议题"
        )
    },
    TestCase("连续点击加载更多只请求并追加一次") { @MainActor in
        let issues = WorkspaceIssuesAPIFake()
        let nextURL = URL(
            string: "https://api.github.com/repos/GitMate/mac-client/issues?page=2"
        )!
        issues.firstIssuesPage = GitHubPage(
            items: [
                GitHubIssue(
                    id: 1,
                    number: 91,
                    title: "第一页",
                    body: nil,
                    state: .open,
                    author: IssueUser(login: "lele")
                )
            ],
            nextPageURL: nextURL
        )
        issues.additionalIssuesPage = GitHubPage(
            items: [
                GitHubIssue(
                    id: 2,
                    number: 92,
                    title: "第二页",
                    body: nil,
                    state: .open,
                    author: IssueUser(login: "lele")
                )
            ],
            nextPageURL: nil
        )
        issues.additionalPageDelayNanoseconds = 20_000_000
        let (viewModel, _, _, _, _) = try makeWorkspaceViewModel(
            issuesAPI: issues
        )
        viewModel.navigate(to: .issues)
        await viewModel.loadCurrentRoute()

        async let first: Void = viewModel.loadMoreIssues()
        async let second: Void = viewModel.loadMoreIssues()
        _ = await (first, second)

        try expectEqual(
            issues.requestedIssuePageURLs.compactMap { $0 }.count,
            1,
            "同一页处于请求中时不得重复请求"
        )
        try expectEqual(
            viewModel.state.issues.map(\.number),
            [91, 92],
            "第二页议题只能追加一次"
        )
    },
    TestCase("取消外层当前页面加载会取消内部读取且不写入过期状态") { @MainActor in
        let issues = CancellableWorkspaceIssuesAPIFake()
        let viewModel = try makeCancellableWorkspaceViewModel(
            issuesAPI: issues
        )
        let load = Task { @MainActor in
            await viewModel.loadCurrentRoute()
        }
        try await waitForIssuesRequestStart(issues)

        load.cancel()
        issues.completeIssuesRequest()
        await load.value

        try expect(
            issues.issuesRequestObservedCancellation,
            "外层取消必须传递到底层议题读取任务"
        )
        try expectEqual(
            viewModel.state.issues,
            [],
            "取消后返回的过期议题不得写入状态"
        )
        try expectEqual(
            viewModel.state.status,
            .idle,
            "取消后的页面加载应结束并回到空闲状态"
        )
    },
    TestCase("显式取消当前页面读取会终止底层任务且不写入过期状态") { @MainActor in
        let issues = CancellableWorkspaceIssuesAPIFake()
        let viewModel = try makeCancellableWorkspaceViewModel(
            issuesAPI: issues
        )
        let load = Task { @MainActor in
            await viewModel.loadCurrentRoute()
        }
        try await waitForIssuesRequestStart(issues)

        viewModel.cancelPageLoads()
        issues.completeIssuesRequest()
        await load.value

        try expect(
            issues.issuesRequestObservedCancellation,
            "显式取消必须传递到底层议题读取任务"
        )
        try expectEqual(
            viewModel.state.issues,
            [],
            "显式取消后返回的过期议题不得写入状态"
        )
        try expectEqual(
            viewModel.state.status,
            .idle,
            "显式取消后的页面加载应结束并回到空闲状态"
        )
    },
    TestCase("显式取消页面读取会终止加载更多且不追加过期页") { @MainActor in
        let nextURL = URL(
            string: "https://api.github.com/repos/GitMate/mac-client/issues?page=2"
        )!
        let issues = CancellableWorkspaceIssuesAPIFake(
            firstIssuesPage: GitHubPage(
                items: [
                    GitHubIssue(
                        id: 1,
                        number: 91,
                        title: "第一页",
                        body: nil,
                        state: .open,
                        author: IssueUser(login: "lele")
                    )
                ],
                nextPageURL: nextURL
            )
        )
        let viewModel = try makeCancellableWorkspaceViewModel(
            issuesAPI: issues
        )
        await viewModel.loadCurrentRoute()
        let loadMore = Task { @MainActor in
            await viewModel.loadMoreIssues()
        }
        try await waitForIssuesRequestStart(issues)

        viewModel.cancelPageLoads()
        issues.completeIssuesRequest()
        await loadMore.value

        try expect(
            issues.issuesRequestObservedCancellation,
            "显式取消必须传递到底层加载更多任务"
        )
        try expectEqual(
            viewModel.state.issues.map(\.number),
            [91],
            "显式取消后返回的过期页不得追加"
        )
        try expectEqual(
            viewModel.state.nextIssuesPageURL,
            nextURL,
            "取消加载更多后应保留原分页游标"
        )
    },
    TestCase("取消外层加载更多会取消内部读取且不追加过期页") { @MainActor in
        let nextURL = URL(
            string: "https://api.github.com/repos/GitMate/mac-client/issues?page=2"
        )!
        let issues = CancellableWorkspaceIssuesAPIFake(
            firstIssuesPage: GitHubPage(
                items: [
                    GitHubIssue(
                        id: 1,
                        number: 91,
                        title: "第一页",
                        body: nil,
                        state: .open,
                        author: IssueUser(login: "lele")
                    )
                ],
                nextPageURL: nextURL
            )
        )
        let viewModel = try makeCancellableWorkspaceViewModel(
            issuesAPI: issues
        )
        await viewModel.loadCurrentRoute()
        let loadMore = Task { @MainActor in
            await viewModel.loadMoreIssues()
        }
        try await waitForIssuesRequestStart(issues)

        loadMore.cancel()
        issues.completeIssuesRequest()
        await loadMore.value

        try expect(
            issues.issuesRequestObservedCancellation,
            "外层取消必须传递到底层加载更多任务"
        )
        try expectEqual(
            viewModel.state.issues.map(\.number),
            [91],
            "外层取消后返回的过期页不得追加"
        )
        try expectEqual(
            viewModel.state.nextIssuesPageURL,
            nextURL,
            "取消加载更多后应保留原分页游标"
        )
    },
    TestCase("401 响应转为工作区授权失效状态") { @MainActor in
        let remote = WorkspaceBranchesAPIFake()
        remote.error = .httpStatus(401, "Bad credentials")
        let (viewModel, _, _, _, _) = try makeWorkspaceViewModel(
            branchesAPI: remote
        )

        await viewModel.loadCurrentRoute()

        try expectEqual(
            viewModel.state.status,
            .authorizationExpired,
            "401 应要求重新授权"
        )
        try expect(viewModel.state.errorMessage?.contains("授权") == true, "应显示中文原因")
    },
    TestCase("议题发布失败保留账户仓库草稿") { @MainActor in
        let issues = WorkspaceIssuesAPIFake()
        issues.createError = .validationFailed(
            message: "Validation Failed",
            details: [
                GitHubValidationErrorDetail(
                    resource: "Issue",
                    field: "title",
                    code: "missing_field",
                    message: nil
                )
            ]
        )
        let persistence = InMemoryWorkspacePersistenceStore()
        let (viewModel, _, _, _, store) = try makeWorkspaceViewModel(
            issuesAPI: issues,
            persistence: persistence
        )
        let input = CreateIssueInput(
            title: "网络恢复异常",
            body: "正文",
            labelNames: ["bug"]
        )

        await viewModel.publishIssue(input)

        let draft = try store.issueDraft(
            accountID: workspaceAccount.id,
            repositoryID: workspaceRepository.id
        )
        try expectEqual(draft?.title, "网络恢复异常", "失败后必须保留标题")
        try expectEqual(draft?.labelNames, ["bug"], "失败后必须保留发布设置")
        try expect(viewModel.state.errorMessage != nil, "应显示发布错误")
    },
    TestCase("创建里程碑成功返回结果并追加到画布") { @MainActor in
        let issues = WorkspaceIssuesAPIFake()
        let (viewModel, _, _, _, _) = try makeWorkspaceViewModel(
            issuesAPI: issues
        )
        let input = MilestoneInput(
            title: "v2.5",
            description: nil,
            state: .open,
            dueOn: nil
        )

        let succeeded = await viewModel.createMilestone(input)

        try expect(succeeded, "成功创建应返回 true")
        try expectEqual(
            viewModel.state.milestones.map(\.title),
            ["v2.5"],
            "成功后应追加到里程碑画布"
        )
    },
    TestCase("里程碑字段错误返回失败并保留详细原因") { @MainActor in
        let issues = WorkspaceIssuesAPIFake()
        issues.milestoneError = .validationFailed(
            message: "Validation Failed",
            details: [
                GitHubValidationErrorDetail(
                    resource: "Milestone",
                    field: "due_on",
                    code: "invalid",
                    message: "must be in the future"
                )
            ]
        )
        let (viewModel, _, _, _, _) = try makeWorkspaceViewModel(
            issuesAPI: issues
        )

        let succeeded = await viewModel.createMilestone(
            MilestoneInput(
                title: "v2.5",
                description: "稳定性",
                state: .open,
                dueOn: .now
            )
        )

        try expect(!succeeded, "422 应返回 false")
        try expect(viewModel.state.milestones.isEmpty, "失败不得追加里程碑")
        try expect(
            viewModel.state.errorMessage?.contains("Milestone.due_on") == true,
            "应显示 GitHub 返回的字段详情"
        )
    },
    TestCase("里程碑权限不足提示所需写权限") { @MainActor in
        let issues = WorkspaceIssuesAPIFake()
        issues.milestoneError = .forbidden(
            "Resource not accessible by personal access token"
        )
        let (viewModel, _, _, _, _) = try makeWorkspaceViewModel(
            issuesAPI: issues
        )

        let succeeded = await viewModel.createMilestone(
            MilestoneInput(
                title: "v2.5",
                description: nil,
                state: .open,
                dueOn: nil
            )
        )

        try expect(!succeeded, "403 应返回 false")
        try expect(viewModel.state.milestones.isEmpty, "权限不足不得追加里程碑")
        try expect(
            viewModel.state.errorMessage?.contains(
                "Issues 或 Pull Requests 写权限"
            ) == true,
            "应说明创建里程碑所需的令牌权限"
        )
    },
    TestCase("评论失败返回失败结果并保留重试依据") { @MainActor in
        let issues = WorkspaceIssuesAPIFake()
        issues.commentError = .forbidden("没有评论权限")
        let (viewModel, _, _, _, _) = try makeWorkspaceViewModel(
            issuesAPI: issues
        )
        viewModel.navigate(to: .issueDetail(number: 91))
        await viewModel.loadCurrentRoute()

        let succeeded = await viewModel.addComment(body: "请保留这段评论")

        try expect(!succeeded, "评论失败时应返回失败结果")
        try expectEqual(
            issues.createdCommentBodies,
            ["请保留这段评论"],
            "失败后应保留可重试的原始正文"
        )
        try expect(viewModel.state.errorMessage != nil, "失败原因应反馈到页面")
    }
]
