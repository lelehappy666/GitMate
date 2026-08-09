import Foundation

public struct WorkspaceSession: Equatable, Sendable {
    public let account: GitHubAccount
    public var repositories: [Repository]
    public var route: WorkspaceRoute

    public init(
        account: GitHubAccount,
        repositories: [Repository],
        route: WorkspaceRoute
    ) {
        self.account = account
        self.repositories = repositories
        self.route = route
    }
}

public struct WorkspaceSelection: Equatable, Sendable {
    public var route: WorkspaceRoute

    public init(route: WorkspaceRoute) {
        self.route = route
    }
}

public struct RepositoryOnlineSummary: Equatable, Codable, Sendable {
    public let repositoryID: Int64
    public let primaryLanguage: String?
    public let openIssueCount: Int
    public let openPullRequestCount: Int
    public let failedWorkflowCount: Int
    public let remoteUpdatedAt: Date?

    public init(
        repositoryID: Int64,
        primaryLanguage: String?,
        openIssueCount: Int,
        openPullRequestCount: Int,
        failedWorkflowCount: Int,
        remoteUpdatedAt: Date?
    ) {
        self.repositoryID = repositoryID
        self.primaryLanguage = primaryLanguage
        self.openIssueCount = openIssueCount
        self.openPullRequestCount = openPullRequestCount
        self.failedWorkflowCount = failedWorkflowCount
        self.remoteUpdatedAt = remoteUpdatedAt
    }
}
