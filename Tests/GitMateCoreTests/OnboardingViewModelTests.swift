import Foundation
import GitMateCore

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

    func repositoryPage(
        token: String,
        page: Int,
        perPage: Int
    ) async throws -> GitHubRepositoryPage {
        let normalizedPage = max(page, 1)
        let normalizedPerPage = max(perPage, 1)
        let start = (normalizedPage - 1) * normalizedPerPage
        let pageRepositories: [Repository]
        if start < repositoryList.count {
            pageRepositories = Array(
                repositoryList.dropFirst(start).prefix(normalizedPerPage)
            )
        } else {
            pageRepositories = []
        }
        return GitHubRepositoryPage(
            repositories: pageRepositories,
            page: normalizedPage,
            hasNextPage: start + pageRepositories.count
                < repositoryList.count
        )
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

private struct OfflineGitHubAPI: GitHubAPI {
    func currentUser(token: String) async throws -> GitHubAccount {
        throw URLError(.notConnectedToInternet)
    }

    func repositories(token: String) async throws -> [Repository] {
        throw URLError(.notConnectedToInternet)
    }

    func repositoryPage(
        token: String,
        page: Int,
        perPage: Int
    ) async throws -> GitHubRepositoryPage {
        throw URLError(.notConnectedToInternet)
    }
}

private final class InMemoryRepositorySyncPreferenceStore:
    RepositorySyncPreferenceStoring,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var values: [String: [RepositorySyncPreference]]

    init(values: [String: [RepositorySyncPreference]] = [:]) {
        self.values = values
    }

    func load(accountID: String) throws -> [RepositorySyncPreference] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return values[accountID] ?? []
    }

    func save(
        _ preferences: [RepositorySyncPreference],
        accountID: String
    ) throws {
        lock.lock()
        defer {
            lock.unlock()
        }
        values[accountID] = preferences
    }

    func clear(accountID: String) throws {
        lock.lock()
        defer {
            lock.unlock()
        }
        values[accountID] = nil
    }
}

private final class CancellableSyncService: RepositorySyncService, @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var cancelled = false

    var hasStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    var hasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func sync(
        repositories: [Repository],
        preferences: [RepositorySyncPreference],
        destination: URL,
        accessToken: String?
    ) -> AsyncThrowingStream<SyncEvent, Error> {
        AsyncThrowingStream { continuation in
            lock.lock()
            started = true
            lock.unlock()
            if let repository = repositories.first {
                continuation.yield(.repositoryStarted(repository))
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.lock()
                cancelled = true
                lock.unlock()
            }
        }
    }
}

private final class RecordingSyncService: RepositorySyncService,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var recordedRepositoryIDs: [Int64] = []

    var repositoryIDs: [Int64] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRepositoryIDs
    }

    func sync(
        repositories: [Repository],
        preferences _: [RepositorySyncPreference],
        destination _: URL,
        accessToken _: String?
    ) -> AsyncThrowingStream<SyncEvent, Error> {
        lock.lock()
        recordedRepositoryIDs = repositories.map(\.id)
        lock.unlock()
        return AsyncThrowingStream { continuation in
            continuation.yield(.finished)
            continuation.finish()
        }
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
    syncEvents: [SyncEvent] = [.finished],
    credentialStore: InMemoryCredentialStore = InMemoryCredentialStore(),
    sessionStore: InMemoryAccountSessionStore = InMemoryAccountSessionStore(),
    syncService: (any RepositorySyncService)? = nil,
    initialState: OnboardingState = OnboardingState(),
    syncDestination: URL = FileManager.default.temporaryDirectory
        .appending(
            path: "GitMate-Onboarding-\(UUID().uuidString)",
            directoryHint: .isDirectory
    ),
    workspaceCache: (any WorkspaceCaching)? = nil,
    api: (any GitHubAPI)? = nil,
    repositorySyncPreferenceStore:
        any RepositorySyncPreferenceStoring =
            InMemoryRepositorySyncPreferenceStore()
) throws -> (OnboardingViewModel, InMemoryCredentialStore) {
    let defaultAPI = FakeGitHubAPI(
        account: viewModelAccount,
        repositories: [viewModelRepository]
    )
    let dependencies = OnboardingDependencies(
        apiProvider: FakeAPIProvider(api: api ?? defaultAPI),
        enterpriseConnector: FakeEnterpriseConnector(account: viewModelAccount),
        credentialStore: credentialStore,
        accountSessionStore: sessionStore,
        syncService: syncService ?? FixedSyncService(events: syncEvents),
        networkMonitor: SilentNetworkMonitor(),
        syncDestination: syncDestination,
        workspaceCache: workspaceCache,
        repositorySyncPreferenceStore: repositorySyncPreferenceStore
    )
    return (
        OnboardingViewModel(
            dependencies: dependencies,
            initialState: initialState
        ),
        credentialStore
    )
}

let onboardingViewModelTests = [
    TestCase("工作区重新授权成功后返回工作区而非同步进度") { @MainActor in
        let initialState = OnboardingState(
            route: .complete,
            account: viewModelAccount,
            repositories: [viewModelRepository],
            preferences: [
                RepositorySyncPreference(
                    repositoryID: viewModelRepository.id,
                    mode: .manual
                )
            ]
        )
        let (viewModel, _) = try makeViewModel(
            initialState: initialState
        )

        viewModel.prepareReauthorization()
        await viewModel.reauthorizeGitHub(token: "renewed-secret")

        try expectEqual(
            viewModel.state.route,
            .complete,
            "工作区重新授权成功后应返回页面 10–15"
        )
        try expectEqual(
            viewModel.state.repositories,
            [viewModelRepository],
            "重新授权不得清空原工作区仓库"
        )
    },
    TestCase("恢复会话发现本地仓库时直接进入工作区") { @MainActor in
        let syncDestination = FileManager.default.temporaryDirectory
            .appending(
                path: "GitMate-Restore-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer {
            try? FileManager.default.removeItem(at: syncDestination)
        }
        try FileManager.default.createDirectory(
            at: syncDestination
                .appending(path: "mac-client", directoryHint: .isDirectory)
                .appending(path: ".git", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        let credentialStore = InMemoryCredentialStore()
        let sessionStore = InMemoryAccountSessionStore()
        try credentialStore.save(
            token: "secret",
            accountID: viewModelAccount.id
        )
        try sessionStore.save(account: viewModelAccount)
        let (viewModel, _) = try makeViewModel(
            credentialStore: credentialStore,
            sessionStore: sessionStore,
            syncDestination: syncDestination
        )

        await viewModel.restoreSession()

        try expectEqual(
            viewModel.state.route,
            .complete,
            "已有本地 Git 仓库时应直接进入页面 10–15"
        )
        try expectEqual(
            viewModel.state.account,
            viewModelAccount,
            "本地优先恢复仍应保留有效账户"
        )
    },
    TestCase("离线恢复会话优先使用工作区缓存并直接进入工作区") { @MainActor in
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "GitMate-Restore-Cache-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer {
            try? FileManager.default.removeItem(at: cacheDirectory)
        }
        let cache = JSONWorkspaceCache(rootDirectory: cacheDirectory)
        try cache.save(
            WorkspaceCacheSnapshot(
                accountID: viewModelAccount.id,
                repositoryRecords: [
                    LocalRepositoryRecord(
                        repository: viewModelRepository,
                        localURL: URL(
                            filePath: "/同步目录/mac-client",
                            directoryHint: .isDirectory
                        ),
                        availability: .available,
                        localSizeInBytes: 1_024,
                        lastInspectedAt: Date(
                            timeIntervalSince1970: 1_000
                        )
                    )
                ],
                onlineSummaries: [:],
                savedAt: Date(timeIntervalSince1970: 1_000)
            )
        )

        let credentialStore = InMemoryCredentialStore()
        let sessionStore = InMemoryAccountSessionStore()
        try credentialStore.save(
            token: "secret",
            accountID: viewModelAccount.id
        )
        try sessionStore.save(account: viewModelAccount)
        let (viewModel, _) = try makeViewModel(
            credentialStore: credentialStore,
            sessionStore: sessionStore,
            workspaceCache: cache,
            api: OfflineGitHubAPI()
        )

        await viewModel.restoreSession()

        try expectEqual(
            viewModel.state.route,
            .complete,
            "离线时存在缓存应直接进入页面 10–15"
        )
        try expectEqual(
            viewModel.state.repositories,
            [viewModelRepository],
            "恢复工作区时应从缓存还原仓库列表"
        )
        try expectEqual(
            viewModel.state.preferences,
            [
                RepositorySyncPreference(
                    repositoryID: viewModelRepository.id,
                    mode: .never
                )
            ],
            "没有保存偏好时缓存仓库应保持不同步"
        )
        try expectEqual(
            viewModel.state.errorMessage,
            nil,
            "本地优先恢复不得因离线产生启动错误"
        )
    },
    TestCase("恢复会话保留不同步云端仓库而不是全部改为手动") { @MainActor in
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "GitMate-Restore-Preferences-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer {
            try? FileManager.default.removeItem(at: cacheDirectory)
        }
        let cache = JSONWorkspaceCache(rootDirectory: cacheDirectory)
        try cache.save(
            WorkspaceCacheSnapshot(
                accountID: viewModelAccount.id,
                repositoryRecords: [
                    LocalRepositoryRecord(
                        repository: viewModelRepository,
                        localURL: URL(
                            filePath: "/同步目录/mac-client",
                            directoryHint: .isDirectory
                        ),
                        availability: .missing,
                        localSizeInBytes: 0,
                        lastInspectedAt: Date(
                            timeIntervalSince1970: 1_000
                        )
                    )
                ],
                onlineSummaries: [:],
                savedAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        let credentialStore = InMemoryCredentialStore()
        let sessionStore = InMemoryAccountSessionStore()
        try credentialStore.save(
            token: "secret",
            accountID: viewModelAccount.id
        )
        try sessionStore.save(account: viewModelAccount)
        let preferenceStore = InMemoryRepositorySyncPreferenceStore(
            values: [
                viewModelAccount.id: [
                    RepositorySyncPreference(
                        repositoryID: viewModelRepository.id,
                        mode: .never
                    )
                ]
            ]
        )
        let (viewModel, _) = try makeViewModel(
            credentialStore: credentialStore,
            sessionStore: sessionStore,
            workspaceCache: cache,
            api: OfflineGitHubAPI(),
            repositorySyncPreferenceStore: preferenceStore
        )

        await viewModel.restoreSession()

        try expectEqual(
            viewModel.state.preferences,
            [
                RepositorySyncPreference(
                    repositoryID: viewModelRepository.id,
                    mode: .never
                )
            ],
            "恢复工作区必须使用真实持久偏好"
        )
    },
    TestCase("工作区重新同步返回仓库选择并保留账户仓库") { @MainActor in
        let (viewModel, _) = try makeViewModel()
        await viewModel.startGitHubLogin()
        await viewModel.connectGitHub(token: "secret")
        await viewModel.confirmPermissions()
        await viewModel.startSync()

        viewModel.prepareRepositoryResync()

        try expectEqual(viewModel.state.route, .repositorySync, "应返回仓库同步选择页")
        try expectEqual(viewModel.state.account, viewModelAccount, "应保留当前账户")
        try expectEqual(
            viewModel.state.repositories,
            [viewModelRepository],
            "应保留已加载仓库"
        )
    },
    TestCase("工作区缺少令牌时返回重新授权并保留账户仓库") { @MainActor in
        let (viewModel, _) = try makeViewModel()
        await viewModel.startGitHubLogin()
        await viewModel.connectGitHub(token: "secret")
        await viewModel.confirmPermissions()

        viewModel.prepareReauthorization()

        try expectEqual(viewModel.state.route, .authorizationExpired, "应进入重新授权页")
        try expectEqual(viewModel.state.account, viewModelAccount, "应保留当前账户")
        try expectEqual(
            viewModel.state.repositories,
            [viewModelRepository],
            "应保留仓库选择"
        )
    },
    TestCase("工作区下载云端仓库只同步选中的一个仓库") { @MainActor in
        let cloudRepository = Repository(
            id: 202,
            name: "cloud-only",
            fullName: "GitMate/cloud-only",
            isPrivate: true,
            defaultBranch: "main",
            sizeInKilobytes: 2_048,
            cloneURL: URL(
                string: "https://github.com/GitMate/cloud-only.git"
            )!,
            ownerAvatarURL: nil
        )
        let credentialStore = InMemoryCredentialStore()
        try credentialStore.save(
            token: "secret",
            accountID: viewModelAccount.id
        )
        let syncService = RecordingSyncService()
        let (viewModel, _) = try makeViewModel(
            credentialStore: credentialStore,
            syncService: syncService,
            initialState: OnboardingState(
                route: .complete,
                account: viewModelAccount,
                repositories: [viewModelRepository],
                preferences: [
                    RepositorySyncPreference(
                        repositoryID: viewModelRepository.id,
                        mode: .automatic
                    )
                ]
            )
        )

        await viewModel.syncRepositoryFromWorkspace(
            cloudRepository,
            mode: .manual
        )

        try expectEqual(
            syncService.repositoryIDs,
            [cloudRepository.id],
            "单仓库下载不得触发其他仓库同步"
        )
        try expect(
            viewModel.state.repositories.contains(cloudRepository),
            "下载完成后仓库应进入本地工作区列表"
        )
        try expectEqual(
            viewModel.state.preferences.first {
                $0.repositoryID == cloudRepository.id
            }?.mode,
            .manual,
            "工作区选择的同步模式必须持久保留"
        )
        try expectEqual(
            viewModel.state.route,
            .complete,
            "单仓库下载完成后应返回工作区"
        )
    },
    TestCase("GitHub 登录保存令牌并进入权限确认页") { @MainActor in
        let sessionStore = InMemoryAccountSessionStore()
        let (viewModel, credentialStore) = try makeViewModel(
            sessionStore: sessionStore
        )

        await viewModel.startGitHubLogin()
        await viewModel.connectGitHub(token: "secret")

        try expectEqual(viewModel.state.route, .permissionReview, "登录成功后应进入第 4 页")
        try expectEqual(viewModel.state.account?.login, "lele", "应保存 GitHub 账户")
        let token = try credentialStore.token(accountID: viewModelAccount.id)
        try expectEqual(token, "secret", "访问令牌应保存到凭据存储")
        let savedAccount = try sessionStore.account()
        try expectEqual(
            savedAccount,
            viewModelAccount,
            "账户元数据应保存到会话存储"
        )
    },
    TestCase("确认权限后加载仓库并默认全部不同步") { @MainActor in
        let (viewModel, _) = try makeViewModel()
        await viewModel.startGitHubLogin()
        await viewModel.connectGitHub(token: "secret")

        await viewModel.confirmPermissions()

        try expectEqual(viewModel.state.route, .repositorySync, "应进入第 5 页")
        try expectEqual(viewModel.state.repositories, [viewModelRepository], "应加载账户仓库")
        try expectEqual(
            viewModel.state.preferences,
            [RepositorySyncPreference(repositoryID: 101, mode: .never)],
            "首次加载应默认全部不同步"
        )
    },
    TestCase("重新启动后恢复账户并直接进入仓库页") { @MainActor in
        let credentialStore = InMemoryCredentialStore()
        let sessionStore = InMemoryAccountSessionStore()
        try credentialStore.save(token: "secret", accountID: viewModelAccount.id)
        try sessionStore.save(account: viewModelAccount)
        let (viewModel, _) = try makeViewModel(
            credentialStore: credentialStore,
            sessionStore: sessionStore
        )

        await viewModel.restoreSession()

        try expectEqual(viewModel.state.account, viewModelAccount, "应恢复已登录账户")
        try expectEqual(viewModel.state.route, .repositorySync, "应跳过登录并进入仓库页")
        try expectEqual(
            viewModel.state.preferences,
            [RepositorySyncPreference(repositoryID: 101, mode: .never)],
            "恢复会话后仓库也应默认不同步"
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
        await viewModel.connectGitHub(token: "secret")
        await viewModel.confirmPermissions()

        await viewModel.startSync()

        try expectEqual(viewModel.state.route, .complete, "同步完成后应退出引导")
        try expectEqual(viewModel.state.progress.completed, 1, "应更新完成数量")
        try expectEqual(viewModel.state.progress.currentFile, "Sources/App.swift", "应保留最后同步文件")
    },
    TestCase("停止同步会取消后台任务并返回仓库选择页") { @MainActor in
        let syncService = CancellableSyncService()
        let (viewModel, _) = try makeViewModel(syncService: syncService)
        await viewModel.startGitHubLogin()
        await viewModel.connectGitHub(token: "secret")
        await viewModel.confirmPermissions()
        viewModel.updateSyncMode(repositoryID: 101, mode: .manual)

        let task = Task { await viewModel.startSync() }
        while !syncService.hasStarted {
            await Task.yield()
        }
        viewModel.stopSync()
        await task.value

        try expectEqual(viewModel.state.route, .repositorySync, "停止后应返回仓库选择页")
        try expect(syncService.hasCancelled, "停止后应取消同步流和后台 Git 任务")
    },
    TestCase("同步断网进入第 8 页并允许恢复") { @MainActor in
        let (viewModel, _) = try makeViewModel(syncEvents: [
            .repositoryFailed(
                repositoryID: 101,
                failure: .networkInterrupted("网络连接中断")
            )
        ])
        await viewModel.startGitHubLogin()
        await viewModel.connectGitHub(token: "secret")
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
        await viewModel.connectGitHub(token: "secret")
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
        await viewModel.connectGitHub(token: "secret")
        await viewModel.confirmPermissions()

        await viewModel.startSync()

        try expectEqual(viewModel.state.route, .syncError, "普通同步错误应进入第 7 页")
        try expectEqual(viewModel.state.failedRepositoryIDs, [101], "应记录失败仓库")
    }
]
