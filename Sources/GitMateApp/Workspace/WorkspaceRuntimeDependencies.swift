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
    private let workspaceAPIOverride: (any GitHubWorkspaceAPI)?

    init(
        syncDestination: URL,
        cacheDirectory: URL,
        credentialStore: any CredentialStore = KeychainCredentialStore(),
        catalog: LocalRepositoryCatalog? = nil,
        localGit: any LocalGitReading = CommandLocalGitReader(
            executor: ProcessCommandExecutor()
        ),
        workspaceAPI: (any GitHubWorkspaceAPI)? = nil,
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

        let api: any GitHubWorkspaceAPI
        if let workspaceAPIOverride {
            api = workspaceAPIOverride
        } else if account.kind == .enterprise,
           let endpoint = try? EnterpriseEndpoint(serverURL: account.serverURL) {
            api = URLSessionGitHubWorkspaceAPI(baseURL: endpoint.apiBaseURL)
        } else {
            api = URLSessionGitHubWorkspaceAPI()
        }
        let content = WorkspaceContentService(
            catalog: catalog,
            localGit: localGit,
            github: api,
            cache: cache
        )
        contentServices[account.id] = content
        return content
    }
}
