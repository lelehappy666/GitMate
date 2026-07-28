public enum OnboardingRoute: Equatable, Sendable {
    case welcome
    case githubAuthorization
    case enterpriseConnection
    case permissionReview
    case repositorySync
    case syncProgress
    case syncError
    case networkInterrupted
    case authorizationExpired
    case complete

    public var pageNumber: Int? {
        switch self {
        case .welcome:
            1
        case .githubAuthorization:
            2
        case .enterpriseConnection:
            3
        case .permissionReview:
            4
        case .repositorySync:
            5
        case .syncProgress:
            6
        case .syncError:
            7
        case .networkInterrupted:
            8
        case .authorizationExpired:
            9
        case .complete:
            nil
        }
    }
}
