public enum OnboardingEvent: Equatable, Sendable {
    case loginRequested
    case enterpriseRequested
    case accountVerified(GitHubAccount)
    case permissionsConfirmed
    case repositoriesLoaded([Repository])
    case downloadConfigured(Set<Int64>)
    case syncConfigured([RepositorySyncPreference])
    case syncProgressUpdated(SyncProgress)
    case repositoryFailed(id: Int64, message: String)
    case networkLost
    case networkRestored
    case authorizationExpired(message: String)
    case reauthorized(GitHubAccount)
    case syncFinished
}

public struct OnboardingState: Equatable, Sendable {
    public var route: OnboardingRoute
    public var account: GitHubAccount?
    public var repositories: [Repository]
    public var selectedRepositoryIDs: Set<Int64>
    public var preferences: [RepositorySyncPreference]
    public var progress: SyncProgress
    public var canResumeSync: Bool
    public var failedRepositoryIDs: [Int64]
    public var errorMessage: String?

    public init(
        route: OnboardingRoute = .welcome,
        account: GitHubAccount? = nil,
        repositories: [Repository] = [],
        selectedRepositoryIDs: Set<Int64> = [],
        preferences: [RepositorySyncPreference] = [],
        progress: SyncProgress = SyncProgress(),
        canResumeSync: Bool = false,
        failedRepositoryIDs: [Int64] = [],
        errorMessage: String? = nil
    ) {
        self.route = route
        self.account = account
        self.repositories = repositories
        self.selectedRepositoryIDs = selectedRepositoryIDs
        self.preferences = preferences
        self.progress = progress
        self.canResumeSync = canResumeSync
        self.failedRepositoryIDs = failedRepositoryIDs
        self.errorMessage = errorMessage
    }

    public mutating func transition(_ event: OnboardingEvent) {
        switch event {
        case .loginRequested:
            route = .githubAuthorization

        case .enterpriseRequested:
            route = .enterpriseConnection

        case let .accountVerified(account):
            self.account = account
            errorMessage = nil
            route = .permissionReview

        case .permissionsConfirmed:
            route = .repositorySync

        case let .repositoriesLoaded(repositories):
            self.repositories = repositories

        case let .downloadConfigured(selectedRepositoryIDs):
            self.selectedRepositoryIDs = selectedRepositoryIDs
            progress = SyncProgress(
                completed: 0,
                total: selectedRepositoryIDs.count
            )
            route = .syncProgress

        case let .syncConfigured(preferences):
            self.preferences = preferences
            selectedRepositoryIDs = Set(
                preferences
                    .filter(\.shouldSyncInitially)
                    .map(\.repositoryID)
            )
            progress = SyncProgress(
                completed: 0,
                total: selectedRepositoryIDs.count
            )
            route = .syncProgress

        case let .syncProgressUpdated(progress):
            self.progress = progress
            route = .syncProgress

        case let .repositoryFailed(id, message):
            if !failedRepositoryIDs.contains(id) {
                failedRepositoryIDs.append(id)
            }
            errorMessage = message
            route = .syncError

        case .networkLost:
            canResumeSync = true
            errorMessage = "网络连接已中断"
            route = .networkInterrupted

        case .networkRestored:
            canResumeSync = false
            errorMessage = nil
            route = .syncProgress

        case let .authorizationExpired(message):
            canResumeSync = true
            errorMessage = message
            route = .authorizationExpired

        case let .reauthorized(account):
            self.account = account
            canResumeSync = false
            errorMessage = nil
            route = .syncProgress

        case .syncFinished:
            route = .complete
        }
    }
}
