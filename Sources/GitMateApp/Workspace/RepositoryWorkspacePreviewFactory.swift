import Foundation
import GitMateCore

@MainActor
enum RepositoryWorkspacePreviewFactory {
    static func make(
        page: Int,
        state: WorkspacePreviewState
    ) -> RepositoryWorkspaceRuntime {
        let workspaceViewModel = makeWorkspaceViewModel(
            page: page,
            state: state
        )
        let contentLoader = RepositoryWorkspacePreviewContentLoader(
            state: state
        )
        return RepositoryWorkspaceRuntime(
            workspaceViewModel: workspaceViewModel,
            overviewViewModel: RepositoryOverviewViewModel(
                repository: WorkspacePreviewData.repository,
                account: WorkspacePreviewData.account,
                token: "gitmate-preview-token",
                loader: contentLoader
            ),
            readmeViewModel: READMEViewModel(
                repository: WorkspacePreviewData.repository,
                account: WorkspacePreviewData.account,
                token: "gitmate-preview-token",
                loader: contentLoader
            ),
            imageAuthorization: READMEImageAuthorization(
                account: WorkspacePreviewData.account,
                accessToken: "gitmate-preview-token"
            )
        )
    }

    private static func makeWorkspaceViewModel(
        page: Int,
        state: WorkspacePreviewState
    ) -> RepositoryWorkspaceViewModel {
        let credentials = InMemoryCredentialStore()
        try? credentials.save(
            token: "gitmate-preview-token",
            accountID: WorkspacePreviewData.account.id
        )
        return RepositoryWorkspaceViewModel(
            context: RepositoryWorkspaceContext(
                account: WorkspacePreviewData.account,
                repository: WorkspacePreviewData.repository,
                localDirectory: URL(
                    filePath: "/Users/lele/GitMate/mac-client",
                    directoryHint: .isDirectory
                ),
                tokenAccountID: WorkspacePreviewData.account.id
            ),
            dependencies: RepositoryWorkspaceDependencies(
                localGit: WorkspacePreviewLocalGit(),
                branchesAPI: WorkspacePreviewBranchesAPI(),
                issuesAPI: WorkspacePreviewIssuesAPI(state: state),
                credentialStore: credentials,
                persistenceStore: InMemoryWorkspacePersistenceStore(),
                labelMergeService: WorkspacePreviewLabelMerger()
            ),
            initialRoute: route(for: page)
        )
    }

    private static func route(for page: Int) -> RepositoryWorkspaceRoute {
        switch page {
        case 12:
            .overview
        case 13:
            .readme
        case 17:
            .tags
        case 18:
            .branchRules
        case 19:
            .issues
        case 20:
            .issueDetail(number: 91)
        case 21:
            .newIssue
        case 22:
            .milestones
        case 23:
            .issueLabels
        default:
            .branches
        }
    }
}

private struct RepositoryWorkspacePreviewContentLoader:
    RepositoryContentLoading
{
    let state: WorkspacePreviewState

    func repositoryContent(
        repository: Repository,
        account _: GitHubAccount,
        token _: String
    ) async throws -> RepositoryContent {
        let connectivity: WorkspaceConnectivity = switch state {
        case .normal, .error:
            .online
        case .offline:
            .offline
        }
        let errors: [WorkspacePanelError] = state == .error
            ? [
                WorkspacePanelError(
                    panel: .onlineSummary,
                    repositoryID: repository.id,
                    message: "暂时无法刷新 GitHub 摘要，已保留本地内容。"
                )
            ]
            : []
        let localURL = URL(
            filePath: "/Users/lele/GitMate/mac-client",
            directoryHint: .isDirectory
        )
        return RepositoryContent(
            repository: repository,
            localRecord: LocalRepositoryRecord(
                repository: repository,
                localURL: localURL,
                availability: .available,
                localSizeInBytes: 2_457_600_000,
                lastInspectedAt: .now
            ),
            localStatus: LocalRepositoryStatus(
                branch: "main",
                upstream: "origin/main",
                ahead: 0,
                behind: 0,
                stagedCount: 1,
                unstagedCount: 2,
                untrackedCount: 0,
                conflictCount: 0
            ),
            onlineSummary: RepositoryOnlineSummary(
                repositoryID: repository.id,
                primaryLanguage: "Swift",
                openIssueCount: 8,
                openPullRequestCount: 7,
                failedWorkflowCount: 2,
                remoteUpdatedAt: .now.addingTimeInterval(-120)
            ),
            recentCommits: [
                GitCommit(
                    shortHash: "a81c32f",
                    fullHash: "a81c32f43e7c8bb5fef670ac73c7d96f8c74d682",
                    subject: "修复网络恢复后的索引重复",
                    authorName: "Lele",
                    authorEmail: "lele@example.com",
                    authoredAt: .now.addingTimeInterval(-120),
                    parentHashes: ["8e1d04a"],
                    decorations: ["HEAD -> main", "origin/main"]
                ),
                GitCommit(
                    shortHash: "742fd81",
                    fullHash: "742fd817c178f9d42cd30a5b61b99d12d31b6cc1",
                    subject: "优化大型仓库的增量扫描",
                    authorName: "Mingxu",
                    authorEmail: "mingxu@example.com",
                    authoredAt: .now.addingTimeInterval(-1_680),
                    parentHashes: ["d6b03b4"],
                    decorations: ["feature/sync"]
                )
            ],
            readme: GitHubREADME(
                repositoryID: repository.id,
                path: "README.md",
                markdown: """
                # GitMate

                一款为 macOS 打造的原生 GitHub 仓库管理工具。

                ## 当前能力

                - 仓库同步与断点恢复
                - 分支、标签与保护规则
                - 议题、里程碑与标签管理

                > 预览内容完全来自本地假数据，不会访问真实 GitHub。
                """,
                downloadURL: URL(
                    string: "https://raw.githubusercontent.com/GitMate/mac-client/main/README.md"
                )
            ),
            connectivity: connectivity,
            panelErrors: errors
        )
    }
}

private enum WorkspacePreviewData {
    static let account = GitHubAccount(
        id: "github.com:100",
        login: "lele",
        name: "Lele",
        avatarURL: URL(
            string: "https://avatars.githubusercontent.com/u/9919"
        ),
        serverURL: URL(string: "https://github.com")!,
        kind: .githubDotCom,
        scopes: ["repo", "read:user", "workflow"]
    )

    static let repository = Repository(
        id: 101,
        name: "mac-client",
        fullName: "GitMate/mac-client",
        isPrivate: true,
        defaultBranch: "main",
        sizeInKilobytes: 2_457_600,
        cloneURL: URL(
            string: "https://github.com/GitMate/mac-client.git"
        )!,
        ownerAvatarURL: account.avatarURL
    )

    static let users = [
        IssueUser(
            databaseID: 100,
            login: "lele",
            name: "Lele",
            avatarURL: URL(
                string: "https://avatars.githubusercontent.com/u/9919"
            ),
            webURL: URL(string: "https://github.com/lele")
        ),
        IssueUser(
            databaseID: 101,
            login: "yuhan",
            name: "Yuhan",
            avatarURL: URL(
                string: "https://avatars.githubusercontent.com/u/583231"
            ),
            webURL: URL(string: "https://github.com/yuhan")
        ),
        IssueUser(
            databaseID: 102,
            login: "mingxu",
            name: "Mingxu",
            avatarURL: URL(
                string: "https://avatars.githubusercontent.com/u/69631"
            ),
            webURL: URL(string: "https://github.com/mingxu")
        )
    ]

    static let labels = [
        IssueLabel(
            id: 1,
            name: "错误",
            color: "D1242F",
            description: "需要修复的功能异常",
            isDefault: true,
            openIssueCount: 8,
            closedIssueCount: 24
        ),
        IssueLabel(
            id: 2,
            name: "功能建议",
            color: "2F81F7",
            description: "新的能力或产品体验建议",
            isDefault: true,
            openIssueCount: 12,
            closedIssueCount: 18
        ),
        IssueLabel(
            id: 3,
            name: "macOS",
            color: "8250DF",
            description: "与 macOS 系统行为相关",
            openIssueCount: 5,
            closedIssueCount: 9
        ),
        IssueLabel(
            id: 4,
            name: "同步",
            color: "1A7F37",
            description: "本地仓库与远端同步流程",
            openIssueCount: 6,
            closedIssueCount: 21
        ),
        IssueLabel(
            id: 5,
            name: "高优先级",
            color: "FBCA04",
            description: "当前版本需要优先处理",
            openIssueCount: 3,
            closedIssueCount: 7
        ),
        IssueLabel(
            id: 6,
            name: "待整理",
            color: "BFD4F2",
            description: "需要进一步确认范围",
            openIssueCount: 0,
            closedIssueCount: 0
        )
    ]

    static let milestones = [
        IssueMilestone(
            id: 201,
            number: 1,
            title: "v2.4 · 同步基础",
            description: "完成断点续传、自动同步和错误恢复。",
            state: .closed,
            openIssues: 0,
            closedIssues: 14,
            dueOn: date(days: -28),
            createdAt: date(days: -88),
            updatedAt: date(days: -25),
            closedAt: date(days: -25),
            creator: users[0]
        ),
        IssueMilestone(
            id: 202,
            number: 2,
            title: "v2.5 · 稳定性与企业体验",
            description: "完善 macOS 权限、SSO 和大型仓库性能。",
            state: .open,
            openIssues: 3,
            closedIssues: 7,
            dueOn: date(days: 18),
            createdAt: date(days: -40),
            updatedAt: date(days: -1),
            creator: users[0]
        ),
        IssueMilestone(
            id: 203,
            number: 3,
            title: "v2.6 · 协作工作流",
            description: "增强议题、审查和自动化的统一工作区。",
            state: .open,
            openIssues: 9,
            closedIssues: 2,
            dueOn: date(days: 52),
            createdAt: date(days: -12),
            updatedAt: date(days: -2),
            creator: users[1]
        ),
        IssueMilestone(
            id: 204,
            number: 4,
            title: "v3.0 · 本地智能",
            description: "规划中的本地分析与智能工作流。",
            state: .open,
            openIssues: 6,
            closedIssues: 0,
            dueOn: nil,
            createdAt: date(days: -4),
            updatedAt: date(days: -1),
            creator: users[2]
        )
    ]

    static let issues = [
        GitHubIssue(
            id: 301,
            number: 91,
            title: "处理 macOS 15 的本地网络权限提示",
            body: """
            ## 问题

            首次同步私有仓库时，系统权限提示缺少上下文，用户无法判断 GitMate 为什么需要访问本地网络。

            ## 目标

            - 在触发系统弹窗前显示解释
            - 授权失败后提供重新尝试入口
            - 保留当前同步进度
            """,
            state: .open,
            author: users[0],
            assignees: [users[0]],
            labels: [labels[0], labels[2], labels[4]],
            milestone: milestones[1],
            commentsCount: 3,
            isLocked: false,
            createdAt: date(days: -6),
            updatedAt: date(minutes: -12),
            webURL: URL(
                string: "https://github.com/GitMate/mac-client/issues/91"
            )
        ),
        GitHubIssue(
            id: 302,
            number: 86,
            title: "网络恢复后偶发重复建立文件索引",
            body: "断点续传任务需要增加幂等校验。",
            state: .open,
            author: users[1],
            assignees: [users[0], users[1]],
            labels: [labels[0], labels[3]],
            milestone: milestones[1],
            commentsCount: 8,
            createdAt: date(days: -10),
            updatedAt: date(hours: -2),
            webURL: URL(
                string: "https://github.com/GitMate/mac-client/issues/86"
            )
        ),
        GitHubIssue(
            id: 303,
            number: 79,
            title: "GitHub Enterprise SSO 回调偶发失败",
            body: "企业账户重新授权后未正确恢复同步。",
            state: .open,
            author: users[2],
            assignees: [users[2]],
            labels: [labels[0], labels[4]],
            milestone: milestones[1],
            commentsCount: 5,
            createdAt: date(days: -18),
            updatedAt: date(hours: -5),
            webURL: URL(
                string: "https://github.com/GitMate/mac-client/issues/79"
            )
        ),
        GitHubIssue(
            id: 304,
            number: 73,
            title: "降低大型仓库首次索引的内存占用",
            body: "对批量扫描任务增加背压。",
            state: .closed,
            author: users[0],
            assignees: [users[1]],
            labels: [labels[1], labels[3]],
            milestone: milestones[0],
            commentsCount: 11,
            createdAt: date(days: -30),
            updatedAt: date(days: -2),
            closedAt: date(days: -2),
            webURL: URL(
                string: "https://github.com/GitMate/mac-client/issues/73"
            )
        ),
        GitHubIssue(
            id: 305,
            number: 68,
            title: "分支规则页面增加组织继承来源",
            body: nil,
            state: .closed,
            author: users[1],
            assignees: [],
            labels: [labels[1]],
            milestone: milestones[0],
            commentsCount: 2,
            createdAt: date(days: -42),
            updatedAt: date(days: -9),
            closedAt: date(days: -9),
            webURL: URL(
                string: "https://github.com/GitMate/mac-client/issues/68"
            )
        )
    ]

    static let timeline = [
        IssueTimelineEvent(
            id: "event-1",
            kind: .labeled,
            actor: users[1],
            createdAt: date(days: -6),
            detail: "macOS"
        ),
        IssueTimelineEvent(
            id: "event-2",
            kind: .assigned,
            actor: users[1],
            createdAt: date(days: -5),
            detail: "@lele"
        ),
        IssueTimelineEvent(
            id: "event-3",
            kind: .milestoned,
            actor: users[0],
            createdAt: date(days: -4),
            detail: "v2.5 · 稳定性与企业体验"
        )
    ]

    static let comments = [
        IssueComment(
            id: 401,
            body: "我已经在干净安装的 macOS 15.1 上复现，系统弹窗出现前确实没有说明。",
            author: users[1],
            createdAt: date(days: -3),
            updatedAt: date(days: -3)
        ),
        IssueComment(
            id: 402,
            body: "建议把说明放在首次同步页，并在失败后保留当前仓库与文件进度。",
            author: users[0],
            createdAt: date(hours: -8),
            updatedAt: date(hours: -8)
        )
    ]

    static let localBranches = [
        GitBranch(
            name: "main",
            localSHA: "a81c32f6",
            remoteSHA: nil,
            upstreamName: "origin/main",
            authorName: "lele",
            isDefault: true,
            isProtected: true,
            lastCommitDate: date(minutes: -2),
            comparison: BranchComparison(aheadBy: 0, behindBy: 0)
        ),
        GitBranch(
            name: "feature/sync",
            localSHA: "31aa2b6e",
            remoteSHA: nil,
            upstreamName: "origin/feature/sync",
            authorName: "lele",
            lastCommitDate: date(hours: -1),
            comparison: BranchComparison(aheadBy: 2, behindBy: 0)
        ),
        GitBranch(
            name: "release/2.5",
            localSHA: "4e28c1aa",
            remoteSHA: nil,
            upstreamName: "origin/release/2.5",
            authorName: "yuhan",
            lastCommitDate: date(days: -1),
            comparison: BranchComparison(aheadBy: 1, behindBy: 2)
        ),
        GitBranch(
            name: "draft/performance",
            localSHA: "b014ce2a",
            remoteSHA: nil,
            upstreamName: nil,
            authorName: "mingxu",
            lastCommitDate: date(days: -2)
        )
    ]

    static let remoteBranches = [
        GitBranch(
            name: "main",
            localSHA: nil,
            remoteSHA: "a81c32f6",
            remoteName: "origin",
            upstreamName: "origin/main",
            authorName: "lele",
            isDefault: true,
            isProtected: true,
            lastCommitDate: date(minutes: -2)
        ),
        GitBranch(
            name: "feature/sync",
            localSHA: nil,
            remoteSHA: "2f90b217",
            remoteName: "origin",
            upstreamName: "origin/feature/sync",
            authorName: "lele",
            lastCommitDate: date(hours: -3)
        ),
        GitBranch(
            name: "release/2.5",
            localSHA: nil,
            remoteSHA: "071c9bee",
            remoteName: "origin",
            upstreamName: "origin/release/2.5",
            authorName: "yuhan",
            isProtected: true,
            lastCommitDate: date(days: -1)
        ),
        GitBranch(
            name: "dependabot/swift-nio",
            localSHA: nil,
            remoteSHA: "89cb7c2d",
            remoteName: "origin",
            upstreamName: "origin/dependabot/swift-nio",
            authorName: "dependabot",
            lastCommitDate: date(days: -3)
        )
    ]

    static let tags = [
        GitTag(
            name: "v2.5.0-beta.2",
            objectSHA: "f902b17a",
            targetSHA: "f902b17a",
            kind: .annotated,
            existsLocally: true,
            existsRemotely: false,
            taggerName: "lele",
            createdAt: date(days: -1),
            message: "第二个稳定性测试版本"
        ),
        GitTag(
            name: "v2.4.0",
            objectSHA: "4e28c1aa",
            targetSHA: "071c9bee",
            kind: .annotated,
            existsLocally: true,
            existsRemotely: true,
            taggerName: "yuhan",
            createdAt: date(days: -28),
            message: "同步基础版本",
            releaseURL: URL(
                string: "https://github.com/GitMate/mac-client/releases/tag/v2.4.0"
            )
        ),
        GitTag(
            name: "v2.3.2",
            objectSHA: "d6b03b4a",
            kind: .lightweight,
            existsLocally: true,
            existsRemotely: true,
            createdAt: date(days: -52)
        ),
        GitTag(
            name: "archive/legacy",
            objectSHA: "742fd81a",
            kind: .lightweight,
            existsLocally: false,
            existsRemotely: true,
            createdAt: date(days: -120)
        )
    ]

    static let rulesets = [
        RepositoryRuleset(
            id: 501,
            name: "主分支保护",
            enforcement: .active,
            source: .repository,
            target: .branch,
            includedRefs: ["~DEFAULT_BRANCH"],
            rules: [
                RepositoryRule(
                    type: "pull_request",
                    parameters: [
                        "required_approving_review_count": .integer(2)
                    ]
                ),
                RepositoryRule(type: "required_linear_history"),
                RepositoryRule(type: "required_signatures"),
                RepositoryRule(type: "non_fast_forward")
            ]
        ),
        RepositoryRuleset(
            id: 502,
            name: "发布分支检查",
            enforcement: .evaluate,
            source: .repository,
            target: .branch,
            includedRefs: ["refs/heads/release/*"],
            rules: [
                RepositoryRule(type: "required_status_checks"),
                RepositoryRule(type: "non_fast_forward")
            ]
        ),
        RepositoryRuleset(
            id: 503,
            name: "企业安全基线",
            enforcement: .active,
            source: .organization(login: "GitMate"),
            target: .branch,
            includedRefs: ["~ALL"],
            rules: [
                RepositoryRule(type: "required_signatures"),
                RepositoryRule(type: "code_scanning")
            ],
            bypassActors: [
                RulesetBypassActorInput(
                    actorID: 42,
                    actorType: "Team",
                    bypassMode: "always"
                )
            ]
        )
    ]

    static func date(
        days: Int = 0,
        hours: Int = 0,
        minutes: Int = 0
    ) -> Date {
        Calendar.current.date(
            byAdding: DateComponents(
                day: days,
                hour: hours,
                minute: minutes
            ),
            to: .now
        ) ?? .now
    }
}

private struct WorkspacePreviewLocalGit: LocalRepositoryGitService {
    func branches(at directory: URL) async throws -> [GitBranch] {
        WorkspacePreviewData.localBranches
    }

    func tags(at directory: URL) async throws -> [GitTag] {
        WorkspacePreviewData.tags.filter(\.existsLocally)
    }

    func workingTreeStatus(
        at directory: URL
    ) async throws -> WorkingTreeStatus {
        WorkingTreeStatus(changedFiles: [])
    }

    func comparison(
        local: String,
        remote: String,
        at directory: URL
    ) async throws -> BranchComparison {
        BranchComparison(aheadBy: 0, behindBy: 0)
    }

    func createBranch(
        _ name: String,
        startPoint: String,
        at directory: URL
    ) async throws {}

    func checkoutBranch(_ name: String, at directory: URL) async throws {}
    func mergeBranch(_ source: String, at directory: URL) async throws {}

    func setUpstream(
        branch: String,
        upstream: String,
        at directory: URL
    ) async throws {}

    func pushBranch(
        _ name: String,
        remote: String,
        at directory: URL
    ) async throws {}

    func deleteBranch(
        _ name: String,
        remote: String?,
        force: Bool,
        at directory: URL
    ) async throws {}

    func createTag(
        _ name: String,
        target: String,
        message: String?,
        at directory: URL
    ) async throws {}

    func pushTag(
        _ name: String,
        remote: String,
        at directory: URL
    ) async throws {}

    func fetchTags(remote: String, at directory: URL) async throws {}

    func deleteTag(
        _ name: String,
        remote: String?,
        at directory: URL
    ) async throws {}
}

private struct WorkspacePreviewBranchesAPI: GitHubBranchesAPI {
    func remoteBranches(token: String) async throws -> [GitBranch] {
        WorkspacePreviewData.remoteBranches
    }

    func remoteTags(token: String) async throws -> [GitTag] {
        WorkspacePreviewData.tags.filter(\.existsRemotely).map { existing in
            var tag = existing
            tag.existsLocally = false
            return tag
        }
    }

    func branchProtection(
        name: String,
        token: String
    ) async throws -> BranchProtectionSummary? {
        BranchProtectionSummary(
            requiredApprovingReviews: 2,
            requiredStatusChecks: ["build", "tests"],
            requiresStrictStatusChecks: true,
            dismissesStaleReviews: true,
            requiresCodeOwnerReview: true,
            enforcesAdmins: true,
            hasPushRestrictions: false
        )
    }

    func rulesets(token: String) async throws -> [RepositoryRuleset] {
        WorkspacePreviewData.rulesets
    }

    func ruleset(
        id: Int64,
        token: String
    ) async throws -> RepositoryRuleset {
        WorkspacePreviewData.rulesets.first { $0.id == id }
            ?? WorkspacePreviewData.rulesets[0]
    }

    func createRuleset(
        _ input: RepositoryRulesetInput,
        token: String
    ) async throws -> RepositoryRuleset {
        RepositoryRuleset(
            id: 999,
            name: input.name,
            enforcement: input.enforcement,
            source: .repository,
            target: input.target,
            includedRefs: input.includedRefs,
            excludedRefs: input.excludedRefs,
            rules: input.rules
        )
    }

    func updateRuleset(
        _ ruleset: RepositoryRuleset,
        input: RepositoryRulesetInput,
        token: String
    ) async throws -> RepositoryRuleset {
        RepositoryRuleset(
            id: ruleset.id,
            name: input.name,
            enforcement: input.enforcement,
            source: ruleset.source,
            target: input.target,
            includedRefs: input.includedRefs,
            excludedRefs: input.excludedRefs,
            rules: input.rules,
            bypassActors: ruleset.bypassActors
        )
    }

    func deleteRuleset(
        _ ruleset: RepositoryRuleset,
        token: String
    ) async throws {}

    func tagReleaseSummary(
        name: String,
        token: String
    ) async throws -> TagReleaseSummary? {
        guard let url = URL(
            string: "https://github.com/GitMate/mac-client/releases/tag/\(name)"
        ) else {
            return nil
        }
        return TagReleaseSummary(
            id: 801,
            tagName: name,
            name: name,
            isDraft: false,
            isPrerelease: name.contains("beta"),
            publishedAt: .now,
            webURL: url
        )
    }
}

private struct WorkspacePreviewIssuesAPI: GitHubIssuesAPI {
    let state: WorkspacePreviewState

    func issues(
        query: IssueQuery,
        pageURL: URL?,
        token: String
    ) async throws -> GitHubPage<GitHubIssue> {
        var issues = WorkspacePreviewData.issues
        if let state = query.state {
            issues = issues.filter { $0.state == state }
        }
        if let search = query.search, !search.isEmpty {
            issues = issues.filter {
                $0.title.localizedCaseInsensitiveContains(search)
                    || ($0.body?
                        .localizedCaseInsensitiveContains(search) == true)
            }
        }
        return GitHubPage(items: issues, nextPageURL: nil)
    }

    func issue(number: Int, token: String) async throws -> GitHubIssue {
        WorkspacePreviewData.issues.first { $0.number == number }
            ?? WorkspacePreviewData.issues[0]
    }

    func timeline(
        number: Int,
        token: String
    ) async throws -> [IssueTimelineEvent] {
        WorkspacePreviewData.timeline
    }

    func comments(
        number: Int,
        token: String
    ) async throws -> [IssueComment] {
        WorkspacePreviewData.comments
    }

    func createIssue(
        _ input: CreateIssueInput,
        token: String
    ) async throws -> GitHubIssue {
        GitHubIssue(
            id: 999,
            number: 99,
            title: input.title,
            body: input.body,
            state: .open,
            author: WorkspacePreviewData.users[0],
            assignees: WorkspacePreviewData.users.filter {
                input.assigneeLogins.contains($0.login)
            },
            labels: WorkspacePreviewData.labels.filter {
                input.labelNames.contains($0.name)
            },
            milestone: WorkspacePreviewData.milestones.first {
                $0.number == input.milestoneNumber
            },
            createdAt: .now,
            updatedAt: .now
        )
    }

    func updateIssue(
        number: Int,
        input: UpdateIssueInput,
        token: String
    ) async throws -> GitHubIssue {
        var issue = try await issue(number: number, token: token)
        issue.title = input.title
        issue.body = input.body
        issue.state = input.state
        issue.assignees = WorkspacePreviewData.users.filter {
            input.assigneeLogins.contains($0.login)
        }
        issue.labels = WorkspacePreviewData.labels.filter {
            input.labelNames.contains($0.name)
        }
        issue.milestone = WorkspacePreviewData.milestones.first {
            $0.number == input.milestoneNumber
        }
        issue.updatedAt = .now
        return issue
    }

    func createComment(
        number: Int,
        body: String,
        token: String
    ) async throws -> IssueComment {
        IssueComment(
            id: 999,
            body: body,
            author: WorkspacePreviewData.users[0],
            createdAt: .now,
            updatedAt: .now
        )
    }

    func updateComment(
        id: Int64,
        body: String,
        token: String
    ) async throws -> IssueComment {
        IssueComment(
            id: id,
            body: body,
            author: WorkspacePreviewData.users[0],
            createdAt: .now,
            updatedAt: .now
        )
    }

    func lockIssue(
        number: Int,
        reason: IssueLockReason?,
        token: String
    ) async throws {}

    func unlockIssue(number: Int, token: String) async throws {}

    func milestones(
        state: IssueState?,
        token: String
    ) async throws -> [IssueMilestone] {
        guard let state else {
            return WorkspacePreviewData.milestones
        }
        return WorkspacePreviewData.milestones.filter { $0.state == state }
    }

    func createMilestone(
        _ input: MilestoneInput,
        token: String
    ) async throws -> IssueMilestone {
        if state == .error {
            throw GitHubAPIError.validationFailed(
                message: "Invalid request.",
                details: [
                    GitHubValidationErrorDetail(
                        resource: "Milestone",
                        field: "due_on",
                        code: "invalid",
                        message: "截止日期必须晚于当前时间"
                    )
                ]
            )
        }
        return IssueMilestone(
            id: 999,
            number: 99,
            title: input.title,
            description: input.description,
            state: input.state,
            openIssues: 0,
            closedIssues: 0,
            dueOn: input.dueOn,
            createdAt: .now,
            updatedAt: .now,
            creator: WorkspacePreviewData.users[0]
        )
    }

    func updateMilestone(
        number: Int,
        input: MilestoneInput,
        token: String
    ) async throws -> IssueMilestone {
        let original = WorkspacePreviewData.milestones.first {
            $0.number == number
        }
        return IssueMilestone(
            id: original?.id ?? 999,
            number: number,
            title: input.title,
            description: input.description,
            state: input.state,
            openIssues: original?.openIssues ?? 0,
            closedIssues: original?.closedIssues ?? 0,
            dueOn: input.dueOn,
            createdAt: original?.createdAt ?? .now,
            updatedAt: .now,
            closedAt: input.state == .closed ? .now : nil,
            creator: original?.creator
        )
    }

    func deleteMilestone(number: Int, token: String) async throws {}

    func labels(token: String) async throws -> [IssueLabel] {
        WorkspacePreviewData.labels
    }

    func labelUsage(token: String) async throws -> [String: IssueLabelUsage] {
        Dictionary(
            uniqueKeysWithValues: WorkspacePreviewData.labels.map {
                (
                    $0.name,
                    IssueLabelUsage(
                        openIssueCount: $0.openIssueCount,
                        closedIssueCount: $0.closedIssueCount
                    )
                )
            }
        )
    }

    func createLabel(
        _ input: IssueLabelInput,
        token: String
    ) async throws -> IssueLabel {
        IssueLabel(
            id: 999,
            name: input.name,
            color: input.color,
            description: input.description
        )
    }

    func updateLabel(
        name: String,
        input: IssueLabelInput,
        token: String
    ) async throws -> IssueLabel {
        IssueLabel(
            id: WorkspacePreviewData.labels.first {
                $0.name == name
            }?.id ?? 999,
            name: input.name,
            color: input.color,
            description: input.description
        )
    }

    func deleteLabel(name: String, token: String) async throws {}
}

private struct WorkspacePreviewLabelMerger: LabelMerging {
    func merge(
        source: String,
        into target: String,
        token: String,
        completedIssueNumbers: [Int]
    ) async throws -> LabelMergeProgress {
        LabelMergeProgress(
            source: source,
            target: target,
            completedIssueNumbers: Array(
                Set(completedIssueNumbers + [68, 73, 79])
            ).sorted(),
            failedIssueNumbers: []
        )
    }
}
