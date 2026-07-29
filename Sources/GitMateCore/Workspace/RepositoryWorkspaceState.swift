import Foundation

public enum RepositoryWorkspaceStatus: Equatable, Sendable {
    case idle
    case loading
    case ready
    case offline
    case authorizationExpired
    case failed
}

public struct RepositoryWorkspaceState: Equatable, Sendable {
    public var route: RepositoryWorkspaceRoute
    public var status: RepositoryWorkspaceStatus
    public var errorMessage: String?
    public var branches: [GitBranch]
    public var tags: [GitTag]
    public var rulesets: [RepositoryRuleset]
    public var issues: [GitHubIssue]
    public var nextIssuesPageURL: URL?
    public var issueQuery: IssueQuery
    public var selectedIssue: GitHubIssue?
    public var timeline: [IssueTimelineEvent]
    public var comments: [IssueComment]
    public var milestones: [IssueMilestone]
    public var labels: [IssueLabel]
    public var savedIssueViews: [SavedIssueView]
    public var issueDraft: IssueDraft?
    public var workingTreeStatus: WorkingTreeStatus?
    public var labelMergeProgress: LabelMergeProgress?

    public init(route: RepositoryWorkspaceRoute = .branches) {
        self.route = route
        status = .idle
        errorMessage = nil
        branches = []
        tags = []
        rulesets = []
        issues = []
        nextIssuesPageURL = nil
        issueQuery = IssueQuery()
        selectedIssue = nil
        timeline = []
        comments = []
        milestones = []
        labels = []
        savedIssueViews = []
        issueDraft = nil
        workingTreeStatus = nil
        labelMergeProgress = nil
    }
}
