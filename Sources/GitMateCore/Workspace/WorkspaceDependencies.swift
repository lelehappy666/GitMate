import Foundation

public enum WorkspaceConnectivity: Equatable, Sendable {
    case online
    case offline
    case rateLimited(resetAt: Date)
    case authorizationRequired
}

public enum WorkspacePanel: Equatable, Sendable {
    case localRepository
    case localStatus
    case onlineSummary
    case readme
    case recentCommits
}

public struct WorkspacePanelError: Equatable, Sendable {
    public let panel: WorkspacePanel
    public let repositoryID: Int64?
    public let message: String

    public init(
        panel: WorkspacePanel,
        repositoryID: Int64?,
        message: String
    ) {
        self.panel = panel
        self.repositoryID = repositoryID
        self.message = message
    }
}

public struct RepositoryContent: Equatable, Sendable {
    public let repository: Repository
    public let localRecord: LocalRepositoryRecord
    public let localStatus: LocalRepositoryStatus?
    public let onlineSummary: RepositoryOnlineSummary?
    public let recentCommits: [GitCommit]
    public let readme: GitHubREADME?
    public let connectivity: WorkspaceConnectivity
    public let panelErrors: [WorkspacePanelError]

    public init(
        repository: Repository,
        localRecord: LocalRepositoryRecord,
        localStatus: LocalRepositoryStatus?,
        onlineSummary: RepositoryOnlineSummary?,
        recentCommits: [GitCommit],
        readme: GitHubREADME?,
        connectivity: WorkspaceConnectivity,
        panelErrors: [WorkspacePanelError]
    ) {
        self.repository = repository
        self.localRecord = localRecord
        self.localStatus = localStatus
        self.onlineSummary = onlineSummary
        self.recentCommits = recentCommits
        self.readme = readme
        self.connectivity = connectivity
        self.panelErrors = panelErrors
    }
}

public struct WorkspaceDashboardContent: Equatable, Sendable {
    public let account: GitHubAccount
    public let repositories: [RepositoryContent]
    public let connectivity: WorkspaceConnectivity
    public let panelErrors: [WorkspacePanelError]

    public init(
        account: GitHubAccount,
        repositories: [RepositoryContent],
        connectivity: WorkspaceConnectivity,
        panelErrors: [WorkspacePanelError]
    ) {
        self.account = account
        self.repositories = repositories
        self.connectivity = connectivity
        self.panelErrors = panelErrors
    }
}
