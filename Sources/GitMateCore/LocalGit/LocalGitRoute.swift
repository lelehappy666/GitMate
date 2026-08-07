public enum LocalGitRoute: CaseIterable, Equatable, Sendable {
    case workingTree
    case commit
    case diff
    case stash
    case historyOperation
    case conflicts
    case remotes
    case transfer

    public var pageNumber: Int {
        switch self {
        case .workingTree: 30
        case .commit: 31
        case .diff: 32
        case .stash: 33
        case .historyOperation: 34
        case .conflicts: 35
        case .remotes: 36
        case .transfer: 37
        }
    }

    public init?(pageNumber: Int) {
        guard let route = Self.allCases.first(where: {
            $0.pageNumber == pageNumber
        }) else {
            return nil
        }
        self = route
    }
}
