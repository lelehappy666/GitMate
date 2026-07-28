import Foundation
import GitMateCore

private final class FakeDeviceAuthorizer: GitHubDeviceAuthorizing, @unchecked Sendable {
    let deviceCode: DeviceCode
    let token: DeviceAccessToken

    init() throws {
        deviceCode = try JSONDecoder().decode(
            DeviceCode.self,
            from: Data(
                """
                {
                  "device_code": "device",
                  "user_code": "ABCD-EFGH",
                  "verification_uri": "https://github.com/login/device",
                  "expires_in": 900,
                  "interval": 1
                }
                """.utf8
            )
        )
        token = DeviceAccessToken(
            accessToken: "secret",
            tokenType: "bearer",
            scopes: ["repo", "read:user"]
        )
    }

    func start() async throws -> DeviceCode {
        deviceCode
    }

    func poll(deviceCode: String, interval: Int) async throws -> DeviceAccessToken {
        token
    }
}

private final class FakeGitHubAPI: GitHubAPI, @unchecked Sendable {
    let account: GitHubAccount
    let repositoryList: [Repository]

    init(account: GitHubAccount, repositories: [Repository]) {
        self.account = account
        repositoryList = repositories
    }

    func currentUser(token: String) async throws -> GitHubAccount {
        account
    }

    func repositories(token: String) async throws -> [Repository] {
        repositoryList
    }
}

private struct FakeAPIProvider: GitHubAPIProviding {
    let api: any GitHubAPI

    func api(for account: GitHubAccount) throws -> any GitHubAPI {
        api
    }
}

private final class FakeEnterpriseConnector: EnterpriseConnecting, @unchecked Sendable {
    let account: GitHubAccount

    init(account: GitHubAccount) {
        self.account = account
    }

    func verify(serverURL: URL, token: String) async throws -> GitHubAccount {
        account
    }
}

private struct FixedSyncService: RepositorySyncService {
    let events: [SyncEvent]

    func sync(
        repositories: [Repository],
        preferences: [RepositorySyncPreference],
        destination: URL,
        accessToken: String?
    ) -> AsyncThrowingStream<SyncEvent, Error> {
        AsyncThrowingStream(SyncEvent.self, bufferingPolicy: .unbounded) { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private struct SilentNetworkMonitor: NetworkMonitoring {
    func statusUpdates() -> AsyncStream<NetworkStatus> {
        AsyncStream { _ in }
    }
}

private let viewModelAccount = GitHubAccount(
    id: "github.com:1",
    login: "lele",
    name: "Lele",
    avatarURL: URL(string: "https://avatars.githubusercontent.com/u/1"),
    serverURL: URL(string: "https://github.com")!,
    kind: .githubDotCom,
    scopes: ["repo", "read:user"]
)

private let viewModelRepository = Repository(
    id: 101,
    name: "mac-client",
    fullName: "GitMate/mac-client",
    isPrivate: true,
    defaultBranch: "main",
    sizeInKilobytes: 2_457_600,
    cloneURL: URL(string: "https://github.com/GitMate/mac-client.git")!,
    ownerAvatarURL: URL(string: "https://avatars.githubusercontent.com/u/1")
)

@MainActor
private func makeViewModel(
    syncEvents: [SyncEvent] = [.finished]
) throws -> (OnboardingViewModel, InMemoryCredentialStore) {
    let credentialStore = InMemoryCredentialStore()
    let api = FakeGitHubAPI(
        account: viewModelAccount,
        repositories: [viewModelRepository]
    )
    let dependencies = OnboardingDependencies(
        deviceAuthorizer: try FakeDeviceAuthorizer(),
        apiProvider: FakeAPIProvider(api: api),
        enterpriseConnector: FakeEnterpriseConnector(account: viewModelAccount),
        credentialStore: credentialStore,
        syncService: FixedSyncService(events: syncEvents),
        networkMonitor: SilentNetworkMonitor(),
        syncDestination: FileManager.default.temporaryDirectory
    )
    return (OnboardingViewModel(dependencies: dependencies), credentialStore)
}

let onboardingViewModelTests = [
    TestCase("GitHub 登录保存令牌并进入权限确认页") { @MainActor in
        let (viewModel, credentialStore) = try makeViewModel()

        await viewModel.startGitHubLogin()

        try expectEqual(viewModel.state.route, .permissionReview, "登录成功后应进入第 4 页")
        try expectEqual(viewModel.state.account?.login, "lele", "应保存 GitHub 账户")
        try expectEqual(viewModel.deviceCode?.userCode, "ABCD-EFGH", "第 2 页应显示设备验证码")
        let token = try credentialStore.token(accountID: viewModelAccount.id)
        try expectEqual(token, "secret", "访问令牌应保存到凭据存储")
    },
    TestCase("确认权限后加载仓库和默认自动同步偏好") { @MainActor in
        let (viewModel, _) = try makeViewModel()
        await viewModel.startGitHubLogin()

        await viewModel.confirmPermissions()

        try expectEqual(viewModel.state.route, .repositorySync, "应进入第 5 页")
        try expectEqual(viewModel.state.repositories, [viewModelRepository], "应加载账户仓库")
        try expectEqual(
            viewModel.state.preferences,
            [RepositorySyncPreference(repositoryID: 101, mode: .automatic)],
            "首次加载应默认开启自动同步"
        )
    },
    TestCase("同步事件实时更新当前文件与长条进度") { @MainActor in
        let progress = SyncProgress(completed: 1, total: 1)
        let (viewModel, _) = try makeViewModel(syncEvents: [
            .repositoryStarted(viewModelRepository),
            .fileChanged(repositoryID: 101, path: "Sources/App.swift"),
            .progress(progress),
            .finished
        ])
        await viewModel.startGitHubLogin()
        await viewModel.confirmPermissions()

        await viewModel.startSync()

        try expectEqual(viewModel.state.route, .complete, "同步完成后应退出引导")
        try expectEqual(viewModel.state.progress.completed, 1, "应更新完成数量")
        try expectEqual(viewModel.state.progress.currentFile, "Sources/App.swift", "应保留最后同步文件")
    },
    TestCase("同步断网进入第 8 页并允许恢复") { @MainActor in
        let (viewModel, _) = try makeViewModel(syncEvents: [
            .repositoryFailed(
                repositoryID: 101,
                failure: .networkInterrupted("网络连接中断")
            )
        ])
        await viewModel.startGitHubLogin()
        await viewModel.confirmPermissions()

        await viewModel.startSync()

        try expectEqual(viewModel.state.route, .networkInterrupted, "网络异常应进入第 8 页")
        try expect(viewModel.state.canResumeSync, "断网页应允许恢复同步")
    },
    TestCase("同步授权失效进入第 9 页") { @MainActor in
        let (viewModel, _) = try makeViewModel(syncEvents: [
            .repositoryFailed(
                repositoryID: 101,
                failure: .authorizationExpired("令牌已失效")
            )
        ])
        await viewModel.startGitHubLogin()
        await viewModel.confirmPermissions()

        await viewModel.startSync()

        try expectEqual(viewModel.state.route, .authorizationExpired, "授权异常应进入第 9 页")
        try expectEqual(viewModel.state.errorMessage, "令牌已失效", "应显示可读原因")
    },
    TestCase("普通仓库失败进入第 7 页") { @MainActor in
        let (viewModel, _) = try makeViewModel(syncEvents: [
            .repositoryFailed(
                repositoryID: 101,
                failure: .commandFailed("仓库数据损坏")
            )
        ])
        await viewModel.startGitHubLogin()
        await viewModel.confirmPermissions()

        await viewModel.startSync()

        try expectEqual(viewModel.state.route, .syncError, "普通同步错误应进入第 7 页")
        try expectEqual(viewModel.state.failedRepositoryIDs, [101], "应记录失败仓库")
    }
]
