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
    private(set) var deletedBranches: [String] = []

    func branches(at directory: URL) async throws -> [GitBranch] { branchValues }
    func tags(at directory: URL) async throws -> [GitTag] { tagValues }
    func workingTreeStatus(at directory: URL) async throws -> WorkingTreeStatus {
        WorkingTreeStatus(changedFiles: [])
    }
    func comparison(local: String, remote: String, at directory: URL) async throws -> BranchComparison {
        BranchComparison(aheadBy: 0, behindBy: 0)
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
    var rulesetValues: [RepositoryRuleset] = []
    var error: GitHubAPIError?

    func remoteBranches(token: String) async throws -> [GitBranch] {
        if let error { throw error }
        return branchValues
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

    func issues(
        query: IssueQuery,
        pageURL: URL?,
        token: String
    ) async throws -> GitHubPage<GitHubIssue> {
        GitHubPage(items: [], nextPageURL: nil)
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
        IssueComment(
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
        IssueMilestone(id: 1, number: 1, title: input.title, state: input.state, openIssues: 0, closedIssues: 0)
    }
    func updateMilestone(
        number: Int,
        input: MilestoneInput,
        token: String
    ) async throws -> IssueMilestone {
        IssueMilestone(id: 1, number: number, title: input.title, state: input.state, openIssues: 0, closedIssues: 0)
    }
    func deleteMilestone(number: Int, token: String) async throws {}
    func labels(token: String) async throws -> [IssueLabel] { [] }
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

private actor EmptyLabelMergeAPI: LabelMergeAPI {
    func issueNumbers(labelName: String, token: String) async throws -> [Int] { [] }
    func addLabels(to issueNumber: Int, names: [String], token: String) async throws {}
    func removeLabel(from issueNumber: Int, name: String, token: String) async throws {}
    func deleteLabel(name: String, token: String) async throws {}
}

@MainActor
private func makeWorkspaceViewModel(
    localGit: WorkspaceLocalGitFake = WorkspaceLocalGitFake(),
    branchesAPI: WorkspaceBranchesAPIFake = WorkspaceBranchesAPIFake(),
    issuesAPI: WorkspaceIssuesAPIFake = WorkspaceIssuesAPIFake(),
    persistence: InMemoryWorkspacePersistenceStore = InMemoryWorkspacePersistenceStore()
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
        labelMergeService: LabelMergeService(api: EmptyLabelMergeAPI())
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
        try expectEqual(viewModel.state.status, .ready, "加载成功后应就绪")
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
            fields: ["title"]
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
    }
]
