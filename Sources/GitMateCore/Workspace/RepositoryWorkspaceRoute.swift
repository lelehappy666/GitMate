public enum RepositoryWorkspaceRoute: Hashable, Codable, Sendable, Identifiable {
    case branches
    case tags
    case branchRules
    case issues
    case issueDetail(number: Int)
    case newIssue
    case milestones
    case issueLabels

    public var id: String {
        switch self {
        case .branches:
            "branches"
        case .tags:
            "tags"
        case .branchRules:
            "branch-rules"
        case .issues:
            "issues"
        case let .issueDetail(number):
            "issue-\(number)"
        case .newIssue:
            "new-issue"
        case .milestones:
            "milestones"
        case .issueLabels:
            "issue-labels"
        }
    }

    public var pageNumber: Int {
        switch self {
        case .branches:
            16
        case .tags:
            17
        case .branchRules:
            18
        case .issues:
            19
        case .issueDetail:
            20
        case .newIssue:
            21
        case .milestones:
            22
        case .issueLabels:
            23
        }
    }
}
