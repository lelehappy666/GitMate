public enum WorkspaceRoute: Equatable, Sendable {
    case dashboard
    case repositories
    case repositoryOverview(repositoryID: Int64)
    case readme(repositoryID: Int64)
    case filesAndCommits(repositoryID: Int64)
    case commitGraph(repositoryID: Int64)

    public var pageNumber: Int {
        switch self {
        case .dashboard:
            10
        case .repositories:
            11
        case .repositoryOverview:
            12
        case .readme:
            13
        case .filesAndCommits:
            14
        case .commitGraph:
            15
        }
    }

    public var repositoryID: Int64? {
        switch self {
        case .dashboard, .repositories:
            nil
        case let .repositoryOverview(id),
             let .readme(id),
             let .filesAndCommits(id),
             let .commitGraph(id):
            id
        }
    }

    public func replacingRepositoryID(_ repositoryID: Int64) -> Self {
        switch self {
        case .dashboard, .repositories:
            self
        case .repositoryOverview:
            .repositoryOverview(repositoryID: repositoryID)
        case .readme:
            .readme(repositoryID: repositoryID)
        case .filesAndCommits:
            .filesAndCommits(repositoryID: repositoryID)
        case .commitGraph:
            .commitGraph(repositoryID: repositoryID)
        }
    }

    public func fallbackAfterCurrentRepositoryRemoval() -> Self {
        .repositories
    }
}
