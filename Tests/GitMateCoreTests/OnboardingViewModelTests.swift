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
        selectedRepositoryIDs: Set<Int64>,
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

private final class CancellableSyncService: RepositorySyncService, @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var cancelled = false
    private var paused = false

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

    var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return paused
    }

    func pause() throws {
        lock.lock()
        paused = true
        lock.unlock()
    }

    func resume() throws {
        lock.lock()
        paused = false
        lock.unlock()
    }

    func sync(
        repositories: [Repository],
        selectedRepositoryIDs: Set<Int64>,
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
    destinationStore: InMemorySyncDestinationStore = InMemorySyncDestinationStore(
        destination: FileManager.default.temporaryDirectory
    )
) throws -> (OnboardingViewModel, InMemoryCredentialStore) {
    let api = FakeGitHubAPI(
        account: viewModelAccount,
        repositories: [viewModelRepository]
    )
    let dependencies = OnboardingDependencies(
        apiProvider: FakeAPIProvider(api: api),
        enterpriseConnector: FakeEnterpriseConnector(account: viewModelAccount),
        credentialStore: credentialStore,
        accountSessionStore: sessionStore,
        syncService: syncService ?? FixedSyncService(events: syncEvents),
        networkMonitor: SilentNetworkMonitor(),
        syncDestinationStore: destinationStore
    )
    return (OnboardingViewModel(dependencies: dependencies), credentialStore)
}

let onboardingViewModelTests = [
    TestCase("仓库默认全部未选择并可切换首次下载选择") { @MainActor in
        let (viewModel, _) = try makeViewModel()
        await viewModel.startGitHubLogin()
        await viewModel.connectGitHub(token: "secret")
        await viewModel.confirmPermissions()

        try expectEqual(
            viewModel.state.selectedRepositoryIDs,
            [],
            "仓库默认应全部未选择"
        )
        viewModel.setRepositorySelected(
            repositoryID: viewModelRepository.id,
            isSelected: true
        )
        try expectEqual(
            viewModel.state.selectedRepositoryIDs,
            [viewModelRepository.id],
            "勾选后应进入首次下载集合"
        )
        viewModel.setRepositorySelected(
            repositoryID: viewModelRepository.id,
            isSelected: false
        )
        try expectEqual(
            viewModel.state.selectedRepositoryIDs,
            [],
            "取消勾选后应移出首次下载集合"
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
    TestCase("确认权限后加载仓库并默认全部未选择") { @MainActor in
        let (viewModel, _) = try makeViewModel()
        await viewModel.startGitHubLogin()
        await viewModel.connectGitHub(token: "secret")

        await viewModel.confirmPermissions()

        try expectEqual(viewModel.state.route, .repositorySync, "应进入第 5 页")
        try expectEqual(viewModel.state.repositories, [viewModelRepository], "应加载账户仓库")
        try expectEqual(
            viewModel.state.selectedRepositoryIDs,
            [],
            "首次加载应默认全部未选择"
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
            viewModel.state.selectedRepositoryIDs,
            [],
            "恢复会话后仓库也应默认未选择"
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
        viewModel.setRepositorySelected(repositoryID: 101, isSelected: true)

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
        viewModel.setRepositorySelected(repositoryID: 101, isSelected: true)

        let task = Task { await viewModel.startSync() }
        while !syncService.hasStarted {
            await Task.yield()
        }
        viewModel.stopSync()
        await task.value

        try expectEqual(viewModel.state.route, .repositorySync, "停止后应返回仓库选择页")
        try expect(syncService.hasCancelled, "停止后应取消同步流和后台 Git 任务")
    },
    TestCase("暂停与继续会更新下载状态并控制当前任务") { @MainActor in
        let syncService = CancellableSyncService()
        let (viewModel, _) = try makeViewModel(syncService: syncService)

        viewModel.pauseDownload()
        try expect(viewModel.isDownloadPaused, "暂停后界面应切换为继续下载")
        try expect(syncService.isPaused, "暂停后应挂起当前 Git 任务")

        viewModel.resumeDownload()
        try expect(!viewModel.isDownloadPaused, "继续后界面应恢复暂停按钮")
        try expect(!syncService.isPaused, "继续后应恢复同一个 Git 任务")
    },
    TestCase("未选择存储目录时不能开始同步") { @MainActor in
        let destinationStore = InMemorySyncDestinationStore()
        let syncService = CancellableSyncService()
        let (viewModel, _) = try makeViewModel(
            syncService: syncService,
            destinationStore: destinationStore
        )
        await viewModel.startGitHubLogin()
        await viewModel.connectGitHub(token: "secret")
        await viewModel.confirmPermissions()
        viewModel.setRepositorySelected(repositoryID: 101, isSelected: true)

        await viewModel.startSync()

        try expectEqual(viewModel.state.route, .repositorySync, "缺少目录时应停留在仓库页")
        try expect(
            viewModel.state.errorMessage?.contains("存储目录") == true,
            "应提示用户先选择存储目录"
        )
        try expect(!syncService.hasStarted, "缺少目录时不得启动后台同步")
    },
    TestCase("选择存储目录后会保存用户选择") { @MainActor in
        let destinationStore = InMemorySyncDestinationStore()
        let (viewModel, _) = try makeViewModel(destinationStore: destinationStore)
        let destination = FileManager.default.temporaryDirectory
            .appending(
                path: "GitMateSelected-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )

        viewModel.selectSyncDestination(destination)

        try expectEqual(viewModel.syncDestination, destination, "界面应显示新目录")
        try expectEqual(
            destinationStore.destination(),
            destination,
            "目录选择应持久化"
        )
    },
    TestCase("目标目录存在同名文件时阻止同步") { @MainActor in
        let destination = FileManager.default.temporaryDirectory
            .appending(
                path: "GitMateConflict-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer { try? FileManager.default.removeItem(at: destination) }
        let repositoryDirectory = destination.appending(
            path: viewModelRepository.name,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: repositoryDirectory,
            withIntermediateDirectories: true
        )
        try Data("已有内容".utf8).write(
            to: repositoryDirectory.appending(path: "README.md")
        )
        let syncService = CancellableSyncService()
        let (viewModel, _) = try makeViewModel(
            syncService: syncService,
            destinationStore: InMemorySyncDestinationStore(
                destination: destination
            )
        )
        await viewModel.startGitHubLogin()
        await viewModel.connectGitHub(token: "secret")
        await viewModel.confirmPermissions()
        viewModel.setRepositorySelected(repositoryID: 101, isSelected: true)

        await viewModel.startSync()

        try expectEqual(viewModel.state.route, .repositorySync, "冲突时应停留在仓库页")
        try expect(
            viewModel.state.errorMessage?.contains("mac-client") == true,
            "冲突提示应指出同名文件夹"
        )
        try expect(!syncService.hasStarted, "冲突时不得启动后台同步")
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
        viewModel.setRepositorySelected(repositoryID: 101, isSelected: true)

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
        viewModel.setRepositorySelected(repositoryID: 101, isSelected: true)

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
        viewModel.setRepositorySelected(repositoryID: 101, isSelected: true)

        await viewModel.startSync()

        try expectEqual(viewModel.state.route, .syncError, "普通同步错误应进入第 7 页")
        try expectEqual(viewModel.state.failedRepositoryIDs, [101], "应记录失败仓库")
    }
]
