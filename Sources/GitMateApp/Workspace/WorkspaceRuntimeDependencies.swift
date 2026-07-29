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
    private let workspaceAPIProvider: any GitHubWorkspaceAPIProviding

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
