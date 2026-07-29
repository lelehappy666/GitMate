import Foundation
import GitMateCore

@MainActor
enum OnboardingPreviewFactory {
    static func make(page: Int) -> OnboardingViewModel {
        let repositories = previewRepositories
        let preferences = repositories.enumerated().map { index, repository in
            RepositorySyncPreference(
                repositoryID: repository.id,
                mode: index == 2 ? .never : .automatic
            )
        }
        var state = OnboardingState(
            route: route(for: page),
            account: previewAccount,
            repositories: repositories,
            preferences: preferences,
            progress: SyncProgress(
                completed: 1,
                total: 3,
                currentRepository: "GitMate/mac-client",
                currentFile: "Sources/Sync/SyncRecovery.swift"
            )
        )

        if page == 1 || page == 2 || page == 3 {
            state.account = nil
        }
        if page == 7 {
            state.failedRepositoryIDs = [102]
            state.errorMessage = "远程仓库返回了不完整的数据包，请重试该仓库。"
        } else if page == 8 {
            state.canResumeSync = true
            state.errorMessage = "网络连接中断，Git 操作已暂停。"
        } else if page == 9 {
            state.canResumeSync = true
            state.errorMessage = "访问令牌已失效，请重新授权。"
        }

        let dependencies = OnboardingDependencies(
            apiProvider: PreviewAPIProvider(),
            enterpriseConnector: PreviewEnterpriseConnector(),
            credentialStore: InMemoryCredentialStore(),
            accountSessionStore: InMemoryAccountSessionStore(),
            syncService: PreviewSyncService(),
            networkMonitor: PreviewNetworkMonitor(),
            syncDestination: FileManager.default.temporaryDirectory
        )
        return OnboardingViewModel(
            dependencies: dependencies,
            initialState: state
        )
    }

    private static func route(for page: Int) -> OnboardingRoute {
        switch page {
        case 2: .githubAuthorization
        case 3: .enterpriseConnection
        case 4: .permissionReview
        case 5: .repositorySync
        case 6: .syncProgress
        case 7: .syncError
        case 8: .networkInterrupted
        case 9: .authorizationExpired
        default: .welcome
        }
    }

    private static let previewAccount = GitHubAccount(
        id: "github.com:100",
        login: "lele",
        name: "Lele",
        avatarURL: URL(string: "https://avatars.githubusercontent.com/u/9919"),
        serverURL: URL(string: "https://github.com")!,
        kind: .githubDotCom,
        scopes: ["repo", "read:user", "workflow"]
    )

    private static let previewRepositories = [
        Repository(
            id: 101,
            name: "mac-client",
            fullName: "GitMate/mac-client",
            isPrivate: true,
            defaultBranch: "main",
            sizeInKilobytes: 2_457_600,
            cloneURL: URL(string: "https://github.com/GitMate/mac-client.git")!,
            ownerAvatarURL: previewAccount.avatarURL
        ),
        Repository(
            id: 102,
            name: "design-system",
            fullName: "dafone/design-system",
            isPrivate: true,
            defaultBranch: "develop",
            sizeInKilobytes: 684_000,
            cloneURL: URL(string: "https://github.com/dafone/design-system.git")!,
            ownerAvatarURL: nil
        ),
        Repository(
            id: 103,
            name: "asset-console",
            fullName: "studio/asset-console",
            isPrivate: false,
            defaultBranch: "main",
            sizeInKilobytes: 1_126_400,
            cloneURL: URL(string: "https://github.com/studio/asset-console.git")!,
            ownerAvatarURL: nil
        )
    ]
}

private struct PreviewGitHubAPI: GitHubAPI {
    func currentUser(token: String) async throws -> GitHubAccount {
        throw GitHubAPIError.invalidResponse
    }

    func repositories(token: String) async throws -> [Repository] {
        []
    }
}

private struct PreviewAPIProvider: GitHubAPIProviding {
    func api(for account: GitHubAccount) throws -> any GitHubAPI {
        PreviewGitHubAPI()
    }
}

private struct PreviewEnterpriseConnector: EnterpriseConnecting {
    func verify(serverURL: URL, token: String) async throws -> GitHubAccount {
        throw EnterpriseConnectionError.connectionFailed("预览模式不连接服务器。")
    }
}

private struct PreviewSyncService: RepositorySyncService {
    func sync(
        repositories: [Repository],
        preferences: [RepositorySyncPreference],
        destination: URL,
        accessToken: String?
    ) -> AsyncThrowingStream<SyncEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private struct PreviewNetworkMonitor: NetworkMonitoring {
    func statusUpdates() -> AsyncStream<NetworkStatus> {
        AsyncStream { _ in }
    }
}
