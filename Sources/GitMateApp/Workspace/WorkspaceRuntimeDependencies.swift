import Foundation
import GitMateCore

enum WorkspaceAuthorization {
    case ready(token: String)
    case reauthorizationRequired
}

@MainActor
final class WorkspaceRuntimeDependencies {
    let credentialStore: any CredentialStore
    let catalog: LocalRepositoryCatalog
    let localGit: any LocalGitReading
    let cache: any WorkspaceCaching
    let coverCache: any RepositoryCoverCaching
    let coverLoader: any RepositoryCoverLoading

    private var contentServices: [String: WorkspaceContentService] = [:]
    private var workspaceAPIs: [String: any GitHubWorkspaceAPI] = [:]
    private var repositoryAPIs: [String: any GitHubAPI] = [:]
    private var rateLimitGates: [String: WorkspaceRateLimitGate] = [:]
    private var coverSchedulers:
        [String: RepositoryCoverViewportScheduler] = [:]
    private let workspaceAPIOverride: (any GitHubWorkspaceAPI)?
    private let workspaceAPIProvider: any GitHubWorkspaceAPIProviding
    private let repositoryAPIProvider: any GitHubAPIProviding

    init(
        syncDestination: URL,
        cacheDirectory: URL,
        credentialStore: any CredentialStore = KeychainCredentialStore(),
        catalog: LocalRepositoryCatalog? = nil,
        localGit: any LocalGitReading = CommandLocalGitReader(
            executor: ProcessCommandExecutor()
        ),
        workspaceAPI: (any GitHubWorkspaceAPI)? = nil,
        workspaceAPIProvider: any GitHubWorkspaceAPIProviding =
            DefaultGitHubWorkspaceAPIProvider(),
        repositoryAPIProvider: any GitHubAPIProviding =
            DefaultGitHubAPIProvider(),
        cache: (any WorkspaceCaching)? = nil,
        coverCache: (any RepositoryCoverCaching)? = nil,
        coverLoader: (any RepositoryCoverLoading)? = nil
    ) {
        self.credentialStore = credentialStore
        self.catalog = catalog ?? LocalRepositoryCatalog(
            rootDirectory: syncDestination
        )
        self.localGit = localGit
        workspaceAPIOverride = workspaceAPI
        self.workspaceAPIProvider = workspaceAPIProvider
        self.repositoryAPIProvider = repositoryAPIProvider

        let workspaceCache = cache ?? JSONWorkspaceCache(
            rootDirectory: cacheDirectory.appending(
                path: "Workspace",
                directoryHint: .isDirectory
            )
        )
        self.cache = workspaceCache

        let repositoryCoverCache = coverCache ?? RepositoryCoverCache(
            rootDirectory: cacheDirectory.appending(
                path: "RepositoryCovers",
                directoryHint: .isDirectory
            )
        )
        self.coverCache = repositoryCoverCache
        self.coverLoader = coverLoader ?? RepositoryCoverLoader(
            cache: repositoryCoverCache
        )
    }

    func authorization(for account: GitHubAccount) -> WorkspaceAuthorization {
        if account.kind == .enterprise {
            do {
                _ = try EnterpriseEndpoint(serverURL: account.serverURL)
            } catch {
                return .reauthorizationRequired
            }
        }

        do {
            guard let token = try credentialStore.token(accountID: account.id)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !token.isEmpty else {
                return .reauthorizationRequired
            }
            return .ready(token: token)
        } catch {
            return .reauthorizationRequired
        }
    }

    func contentService(for account: GitHubAccount) -> WorkspaceContentService {
        if let existing = contentServices[account.id] {
            return existing
        }

        let content = WorkspaceContentService(
            catalog: catalog,
            localGit: localGit,
            github: workspaceAPI(for: account),
            cache: cache,
            rateLimitGate: rateLimitGate(for: account)
        )
        contentServices[account.id] = content
        return content
    }

    func repositoryAPI(
        for account: GitHubAccount
    ) throws -> any GitHubAPI {
        if let existing = repositoryAPIs[account.id] {
            return existing
        }
        let api = try repositoryAPIProvider.api(for: account)
        repositoryAPIs[account.id] = api
        return api
    }

    func coverScheduler(
        for account: GitHubAccount
    ) -> RepositoryCoverViewportScheduler {
        if let existing = coverSchedulers[account.id] {
            return existing
        }
        let resolver = RepositoryCoverResolver(
            github: workspaceAPI(for: account),
            cache: coverCache,
            loader: coverLoader,
            rateLimitGate: rateLimitGate(for: account)
        )
        let scheduler = RepositoryCoverViewportScheduler(
            resolver: resolver,
            maximumConcurrentLoads: 3
        )
        coverSchedulers[account.id] = scheduler
        return scheduler
    }

    private func workspaceAPI(
        for account: GitHubAccount
    ) -> any GitHubWorkspaceAPI {
        if let existing = workspaceAPIs[account.id] {
            return existing
        }
        let api: any GitHubWorkspaceAPI
        if let workspaceAPIOverride {
            api = workspaceAPIOverride
        } else {
            do {
                api = try workspaceAPIProvider.api(for: account)
            } catch {
                api = ReauthorizationRequiredGitHubWorkspaceAPI()
            }
        }
        workspaceAPIs[account.id] = api
        return api
    }

    private func rateLimitGate(
        for account: GitHubAccount
    ) -> WorkspaceRateLimitGate {
        if let existing = rateLimitGates[account.id] {
            return existing
        }
        let gate = WorkspaceRateLimitGate()
        rateLimitGates[account.id] = gate
        return gate
    }
}
