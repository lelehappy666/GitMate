import Foundation

public protocol GitHubAPIProviding: Sendable {
    func api(for account: GitHubAccount) throws -> any GitHubAPI
}

public struct DefaultGitHubAPIProvider: GitHubAPIProviding, @unchecked Sendable {
    private let githubDotComAPI: any GitHubAPI
    private let session: URLSession

    public init(
        githubDotComAPI: any GitHubAPI = URLSessionGitHubAPI(),
        session: URLSession = .shared
    ) {
        self.githubDotComAPI = githubDotComAPI
        self.session = session
    }

    public func api(for account: GitHubAccount) throws -> any GitHubAPI {
        switch account.kind {
        case .githubDotCom:
            return githubDotComAPI
        case .enterprise:
            let endpoint = try EnterpriseEndpoint(serverURL: account.serverURL)
            return URLSessionGitHubAPI(
                session: session,
                apiBaseURL: endpoint.apiBaseURL,
                serverURL: endpoint.serverURL,
                accountKind: .enterprise
            )
        }
    }
}

public struct OnboardingDependencies: Sendable {
    public let apiProvider: any GitHubAPIProviding
    public let enterpriseConnector: any EnterpriseConnecting
    public let credentialStore: any CredentialStore
    public let accountSessionStore: any AccountSessionStore
    public let syncService: any RepositorySyncService
    public let networkMonitor: any NetworkMonitoring
    public let syncDestination: URL
    public let workspaceCache: (any WorkspaceCaching)?
    public let repositorySyncPreferenceStore:
        any RepositorySyncPreferenceStoring

    public init(
        apiProvider: any GitHubAPIProviding,
        enterpriseConnector: any EnterpriseConnecting,
        credentialStore: any CredentialStore,
        accountSessionStore: any AccountSessionStore,
        syncService: any RepositorySyncService,
        networkMonitor: any NetworkMonitoring,
        syncDestination: URL,
        workspaceCache: (any WorkspaceCaching)? = nil,
        repositorySyncPreferenceStore:
            any RepositorySyncPreferenceStoring =
                UserDefaultsRepositorySyncPreferenceStore()
    ) {
        self.apiProvider = apiProvider
        self.enterpriseConnector = enterpriseConnector
        self.credentialStore = credentialStore
        self.accountSessionStore = accountSessionStore
        self.syncService = syncService
        self.networkMonitor = networkMonitor
        self.syncDestination = syncDestination
        self.workspaceCache = workspaceCache
        self.repositorySyncPreferenceStore = repositorySyncPreferenceStore
    }
}
