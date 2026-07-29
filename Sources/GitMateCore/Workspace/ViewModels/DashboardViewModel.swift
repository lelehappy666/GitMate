import Foundation
import Observation

public protocol WorkspaceDashboardLoading: Sendable {
    func dashboard(
        account: GitHubAccount,
        repositories: [Repository],
        token: String
    ) async throws -> WorkspaceDashboardContent
}

extension WorkspaceContentService: WorkspaceDashboardLoading {}

public enum DashboardLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(message: String)
}

public struct DashboardAccountSummary: Equatable, Sendable {
    public let login: String
    public let displayName: String?
    public let avatarURL: URL?
    public let serverURL: URL

    public init(account: GitHubAccount) {
        login = account.login
        displayName = account.name
        avatarURL = account.avatarURL
        serverURL = account.serverURL
    }
}

public enum DashboardFocusKind: Equatable, Sendable {
    case authorizationRequired
    case syncFailure
    case failedWorkflow
    case localChanges
    case pendingPullRequest
    case recentActivity
    case neutral
}

public struct DashboardFocus: Equatable, Sendable {
    public let kind: DashboardFocusKind
    public let itemCount: Int?
    public let title: String
    public let message: String

    public init(
        kind: DashboardFocusKind,
        itemCount: Int?,
        title: String,
        message: String
    ) {
        self.kind = kind
        self.itemCount = itemCount
        self.title = title
        self.message = message
    }

    public static let neutral = DashboardFocus(
        kind: .neutral,
        itemCount: nil,
        title: "工作区状态平稳",
        message: "当前没有需要立即处理的事项。"
    )
}

public struct DashboardRepositorySummary: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let fullName: String
    public let availability: LocalRepositoryAvailability
    public let isHealthy: Bool
    public let localChangeCount: Int
    public let openIssueCount: Int
    public let openPullRequestCount: Int
    public let failedWorkflowCount: Int

    public init(
        id: Int64,
        fullName: String,
        availability: LocalRepositoryAvailability,
        isHealthy: Bool,
        localChangeCount: Int,
        openIssueCount: Int,
        openPullRequestCount: Int,
        failedWorkflowCount: Int
    ) {
        self.id = id
        self.fullName = fullName
        self.availability = availability
        self.isHealthy = isHealthy
        self.localChangeCount = localChangeCount
        self.openIssueCount = openIssueCount
        self.openPullRequestCount = openPullRequestCount
        self.failedWorkflowCount = failedWorkflowCount
    }
}

public struct WorkspaceActivity: Identifiable, Equatable, Sendable {
    public var id: String {
        "\(repositoryID):\(commit.fullHash)"
    }

    public let repositoryID: Int64
    public let repositoryFullName: String
    public let commit: GitCommit

    public init(
        repositoryID: Int64,
        repositoryFullName: String,
        commit: GitCommit
    ) {
        self.repositoryID = repositoryID
        self.repositoryFullName = repositoryFullName
        self.commit = commit
    }
}

public struct DashboardState: Equatable, Sendable {
    public var loadPhase: DashboardLoadPhase
    public var account: DashboardAccountSummary
    public var focus: DashboardFocus
    public var repositoryCount: Int
    public var healthyRepositoryCount: Int
    public var syncFailureCount: Int
    public var localChangeCount: Int
    public var openIssueCount: Int
    public var openPullRequestCount: Int
    public var failedWorkflowCount: Int
    public var repositorySummaries: [DashboardRepositorySummary]
    public var activities: [WorkspaceActivity]
    public var connectivity: WorkspaceConnectivity
    public var panelErrors: [WorkspacePanelError]

    public init(account: GitHubAccount) {
        loadPhase = .idle
        self.account = DashboardAccountSummary(account: account)
        focus = .neutral
        repositoryCount = 0
        healthyRepositoryCount = 0
        syncFailureCount = 0
        localChangeCount = 0
        openIssueCount = 0
        openPullRequestCount = 0
        failedWorkflowCount = 0
        repositorySummaries = []
        activities = []
        connectivity = .online
        panelErrors = []
    }
}

@MainActor
@Observable
public final class DashboardViewModel {
    public private(set) var state: DashboardState

    @ObservationIgnored
    private let account: GitHubAccount

    @ObservationIgnored
    private let repositories: [Repository]

    @ObservationIgnored
    private let token: String

    @ObservationIgnored
    private let loader: any WorkspaceDashboardLoading

    @ObservationIgnored
    private var isLoading = false

    @ObservationIgnored
    private var hasLoadedSuccessfully = false

    public init(
        account: GitHubAccount,
        repositories: [Repository],
        token: String,
        loader: any WorkspaceDashboardLoading
    ) {
        self.account = account
        self.repositories = repositories
        self.token = token
        self.loader = loader
        state = DashboardState(account: account)
    }

    public func load() async {
        guard !isLoading, !hasLoadedSuccessfully else {
            return
        }

        isLoading = true
        state.loadPhase = .loading
        defer { isLoading = false }

        do {
            let content = try await loader.dashboard(
                account: account,
                repositories: repositories,
                token: token
            )
            state = Self.makeState(
                from: content,
                sensitiveValue: token
            )
            hasLoadedSuccessfully = true
        } catch {
            var failedState = DashboardState(account: account)
            failedState.loadPhase = .failed(
                message: "暂时无法加载工作台，请稍后重试。"
            )
            state = failedState
        }
    }

    private static func makeState(
        from content: WorkspaceDashboardContent,
        sensitiveValue: String
    ) -> DashboardState {
        let panelErrors = uniquePanelErrors(
            content.panelErrors
                + content.repositories.flatMap(\.panelErrors)
        ).map {
            sanitizedPanelError($0, sensitiveValue: sensitiveValue)
        }
        let repositorySummaries = content.repositories.map { repositoryContent in
            repositorySummary(
                from: repositoryContent,
                panelErrors: panelErrors
            )
        }
        let syncFailureRepositoryIDs = Set(
            repositorySummaries.compactMap { summary in
                summary.availability == .available ? nil : summary.id
            }
            + panelErrors.compactMap { error in
                error.panel == .localRepository ? error.repositoryID : nil
            }
        )
        let activities = Array(
            content.repositories
                .flatMap { repositoryContent in
                    repositoryContent.recentCommits.map { commit in
                        WorkspaceActivity(
                            repositoryID: repositoryContent.repository.id,
                            repositoryFullName: repositoryContent.repository.fullName,
                            commit: commit
                        )
                    }
                }
                .sorted(by: activityComesFirst)
                .prefix(12)
        )
        let localChangeCount = repositorySummaries.reduce(0) {
            $0 + $1.localChangeCount
        }
        let openIssueCount = repositorySummaries.reduce(0) {
            $0 + $1.openIssueCount
        }
        let openPullRequestCount = repositorySummaries.reduce(0) {
            $0 + $1.openPullRequestCount
        }
        let failedWorkflowCount = repositorySummaries.reduce(0) {
            $0 + $1.failedWorkflowCount
        }
        let focus = makeFocus(
            connectivity: content.connectivity,
            syncFailureCount: syncFailureRepositoryIDs.count,
            failedWorkflowCount: failedWorkflowCount,
            localChangeCount: localChangeCount,
            openPullRequestCount: openPullRequestCount,
            activities: activities
        )

        var state = DashboardState(account: content.account)
        state.loadPhase = .loaded
        state.focus = focus
        state.repositoryCount = content.repositories.count
        state.healthyRepositoryCount = repositorySummaries.filter(\.isHealthy).count
        state.syncFailureCount = syncFailureRepositoryIDs.count
        state.localChangeCount = localChangeCount
        state.openIssueCount = openIssueCount
        state.openPullRequestCount = openPullRequestCount
        state.failedWorkflowCount = failedWorkflowCount
        state.repositorySummaries = repositorySummaries
        state.activities = activities
        state.connectivity = content.connectivity
        state.panelErrors = panelErrors
        return state
    }

    private static func repositorySummary(
        from content: RepositoryContent,
        panelErrors: [WorkspacePanelError]
    ) -> DashboardRepositorySummary {
        let repositoryID = content.repository.id
        let hasHealthError = panelErrors.contains {
            $0.repositoryID == repositoryID
                && ($0.panel == .localRepository || $0.panel == .localStatus)
        }
        let localChangeCount = content.localStatus.map {
            $0.stagedCount
                + $0.unstagedCount
                + $0.untrackedCount
                + $0.conflictCount
        } ?? 0

        return DashboardRepositorySummary(
            id: repositoryID,
            fullName: content.repository.fullName,
            availability: content.localRecord.availability,
            isHealthy: content.localRecord.availability == .available
                && !hasHealthError,
            localChangeCount: localChangeCount,
            openIssueCount: content.onlineSummary?.openIssueCount ?? 0,
            openPullRequestCount: content.onlineSummary?.openPullRequestCount ?? 0,
            failedWorkflowCount: content.onlineSummary?.failedWorkflowCount ?? 0
        )
    }

    private static func activityComesFirst(
        _ lhs: WorkspaceActivity,
        _ rhs: WorkspaceActivity
    ) -> Bool {
        if lhs.commit.authoredAt != rhs.commit.authoredAt {
            return lhs.commit.authoredAt > rhs.commit.authoredAt
        }
        if lhs.repositoryFullName != rhs.repositoryFullName {
            return lhs.repositoryFullName < rhs.repositoryFullName
        }
        return lhs.commit.fullHash < rhs.commit.fullHash
    }

    private static func uniquePanelErrors(
        _ errors: [WorkspacePanelError]
    ) -> [WorkspacePanelError] {
        errors.reduce(into: []) { result, error in
            if !result.contains(error) {
                result.append(error)
            }
        }
    }

    private static func sanitizedPanelError(
        _ error: WorkspacePanelError,
        sensitiveValue: String
    ) -> WorkspacePanelError {
        guard !sensitiveValue.isEmpty else {
            return error
        }
        return WorkspacePanelError(
            panel: error.panel,
            repositoryID: error.repositoryID,
            message: error.message.replacingOccurrences(
                of: sensitiveValue,
                with: "••••"
            )
        )
    }

    private static func makeFocus(
        connectivity: WorkspaceConnectivity,
        syncFailureCount: Int,
        failedWorkflowCount: Int,
        localChangeCount: Int,
        openPullRequestCount: Int,
        activities: [WorkspaceActivity]
    ) -> DashboardFocus {
        if connectivity == .authorizationRequired {
            return DashboardFocus(
                kind: .authorizationRequired,
                itemCount: nil,
                title: "GitHub 授权需要更新",
                message: "重新授权后才能继续获取在线状态。"
            )
        }
        if syncFailureCount > 0 {
            return DashboardFocus(
                kind: .syncFailure,
                itemCount: syncFailureCount,
                title: "有仓库需要重新同步",
                message: "\(syncFailureCount) 个仓库的本地副本缺失或损坏。"
            )
        }
        if failedWorkflowCount > 0 {
            return DashboardFocus(
                kind: .failedWorkflow,
                itemCount: failedWorkflowCount,
                title: "Actions 运行需要关注",
                message: "\(failedWorkflowCount) 个工作流最近运行失败。"
            )
        }
        if localChangeCount > 0 {
            return DashboardFocus(
                kind: .localChanges,
                itemCount: localChangeCount,
                title: "本地改动等待整理",
                message: "跨仓库共有 \(localChangeCount) 项未提交改动。"
            )
        }
        if openPullRequestCount > 0 {
            return DashboardFocus(
                kind: .pendingPullRequest,
                itemCount: openPullRequestCount,
                title: "Pull Request 等待处理",
                message: "当前共有 \(openPullRequestCount) 个开放的 Pull Request。"
            )
        }
        if let latestActivity = activities.first {
            return DashboardFocus(
                kind: .recentActivity,
                itemCount: nil,
                title: "最近有新的本地提交",
                message: "\(latestActivity.repositoryFullName)：\(latestActivity.commit.subject)"
            )
        }
        return .neutral
    }
}
