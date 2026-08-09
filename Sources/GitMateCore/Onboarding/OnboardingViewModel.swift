import Foundation
import Observation

@MainActor
@Observable
public final class OnboardingViewModel {
    public private(set) var state: OnboardingState
    public private(set) var isWorking = false
    public private(set) var isRefreshingRepositories = false
    public private(set) var isDownloadPaused = false
    public private(set) var syncDestination: URL?

    @ObservationIgnored
    private let dependencies: OnboardingDependencies

    @ObservationIgnored
    private var networkTask: Task<Void, Never>?

    @ObservationIgnored
    private var activeSyncTask: Task<Void, Never>?

    @ObservationIgnored
    private var activeSyncID: UUID?

    @ObservationIgnored
    private var hasAttemptedSessionRestore = false

    @ObservationIgnored
    private var shouldReturnToWorkspaceAfterReauthorization = false

    public init(
        dependencies: OnboardingDependencies,
        initialState: OnboardingState = OnboardingState()
    ) {
        self.dependencies = dependencies
        state = initialState
        syncDestination = dependencies.syncDestinationStore.destination()
    }

    deinit {
        networkTask?.cancel()
        activeSyncTask?.cancel()
    }

    public func startGitHubLogin() async {
        state.transition(.loginRequested)
    }

    public func showEnterpriseConnection() {
        state.transition(.enterpriseRequested)
    }

    public func returnToWelcome() {
        activeSyncTask?.cancel()
        activeSyncTask = nil
        activeSyncID = nil
        shouldReturnToWorkspaceAfterReauthorization = false
        if let account = state.account {
            try? dependencies.credentialStore.deleteToken(accountID: account.id)
            try? dependencies.repositorySyncPreferenceStore.clear(
                accountID: account.id
            )
        }
        try? dependencies.accountSessionStore.clear()
        state = OnboardingState()
    }

    public func restoreSession() async {
        guard !hasAttemptedSessionRestore, state.route == .welcome else {
            return
        }
        hasAttemptedSessionRestore = true

        do {
            guard let account = try dependencies.accountSessionStore.account()
            else {
                return
            }
            guard let token = try dependencies.credentialStore.token(
                accountID: account.id
            ), !token.isEmpty else {
                try dependencies.accountSessionStore.clear()
                return
            }

            state.account = account
            if let cachedRepositories = cachedRepositories(
                accountID: account.id
            ) {
                state.repositories = cachedRepositories
                state.preferences = try restoredPreferences(
                    repositories: cachedRepositories,
                    accountID: account.id
                )
                state.selectedRepositoryIDs = Set(
                    state.preferences
                        .filter(\.shouldSyncInitially)
                        .map(\.repositoryID)
                )
                state.route = .complete
                return
            }
            if hasLocalRepositoryData() {
                state.route = .complete
                return
            }
            state.route = .repositorySync
            await loadRepositories()
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func cachedRepositories(accountID: String) -> [Repository]? {
        guard let workspaceCache = dependencies.workspaceCache,
              let snapshot = try? workspaceCache.load(
                  accountID: accountID
              )
        else {
            return nil
        }

        var seenRepositoryIDs = Set<Int64>()
        var seenRepositoryFullNames = Set<String>()
        let repositories = snapshot.repositoryRecords.reversed().compactMap {
            record -> Repository? in
            guard seenRepositoryIDs.insert(record.repository.id).inserted,
                  seenRepositoryFullNames.insert(
                      record.repository.normalizedFullName
                  ).inserted else {
                return nil
            }
            return record.repository
        }
        return repositories.reversed()
    }

    private func hasLocalRepositoryData() -> Bool {
        guard let syncDestination,
              let repositoryDirectories = try? FileManager.default
            .contentsOfDirectory(
                at: syncDestination,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return false
        }

        return repositoryDirectories.contains { directory in
            let values = try? directory.resourceValues(
                forKeys: [.isDirectoryKey]
            )
            guard values?.isDirectory == true else {
                return false
            }
            return FileManager.default.fileExists(
                atPath: directory
                    .appending(
                        path: ".git",
                        directoryHint: .isDirectory
                    )
                    .path
            )
        }
    }

    public func connectGitHub(token: String) async {
        await authenticateGitHub(
            token: token,
            isReauthorization: false
        )
    }

    public func reauthorizeGitHub(token: String) async {
        await authenticateGitHub(
            token: token,
            isReauthorization: true
        )
    }

    private func normalizedToken(_ token: String) -> String? {
        let normalizedToken = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedToken.isEmpty ? nil : normalizedToken
    }

    public func returnToPermissionReview() {
        state.route = .permissionReview
        state.errorMessage = nil
    }

    public func connectEnterprise(serverURLText: String, token: String) async {
        guard let serverURL = normalizedURL(from: serverURLText) else {
            state.errorMessage = EnterpriseConnectionError.invalidServerURL.localizedDescription
            return
        }

        isWorking = true
        state.errorMessage = nil
        defer { isWorking = false }

        do {
            let account = try await dependencies.enterpriseConnector.verify(
                serverURL: serverURL,
                token: token
            )
            try dependencies.credentialStore.save(
                token: token,
                accountID: account.id
            )
            try dependencies.accountSessionStore.save(account: account)
            state.transition(.accountVerified(account))
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    public func confirmPermissions() async {
        state.transition(.permissionsConfirmed)
        await loadRepositories()
    }

    public func loadRepositories() async {
        guard let account = state.account else {
            state.errorMessage = "尚未连接 GitHub 账户。"
            return
        }

        isWorking = true
        state.errorMessage = nil
        defer { isWorking = false }

        do {
            guard let token = try dependencies.credentialStore.token(
                accountID: account.id
            ) else {
                state.transition(.authorizationExpired(message: "账户令牌不存在，请重新授权。"))
                return
            }
            let api = try dependencies.apiProvider.api(for: account)
            let repositories = try await api.repositories(token: token)
            state.transition(.repositoriesLoaded(repositories))
            state.preferences = try restoredPreferences(
                repositories: repositories,
                accountID: account.id
            )
            state.selectedRepositoryIDs = Set(
                state.preferences
                    .filter(\.shouldSyncInitially)
                    .map(\.repositoryID)
            )
        } catch GitHubAPIError.httpStatus(401, _) {
            state.transition(.authorizationExpired(message: "账户授权已失效，请重新登录。"))
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    public func refreshRepositories() async {
        guard let account = state.account else {
            state.errorMessage = "尚未连接 GitHub 账户。"
            return
        }
        guard !isRefreshingRepositories else { return }

        isRefreshingRepositories = true
        state.errorMessage = nil
        defer { isRefreshingRepositories = false }

        do {
            guard let token = try dependencies.credentialStore.token(
                accountID: account.id
            ) else {
                state.transition(
                    .authorizationExpired(
                        message: "账户令牌不存在，请重新授权。"
                    )
                )
                return
            }
            let api = try dependencies.apiProvider.api(for: account)
            let repositories = try await api.repositories(token: token)
            let availableIDs = Set(repositories.map(\.id))
            state.selectedRepositoryIDs.formIntersection(availableIDs)
            let existingModes = Dictionary(
                state.preferences.map { ($0.repositoryID, $0.mode) },
                uniquingKeysWith: { _, newest in newest }
            )
            state.transition(.repositoriesLoaded(repositories))
            state.preferences = repositories.map { repository in
                RepositorySyncPreference(
                    repositoryID: repository.id,
                    mode: existingModes[repository.id] ?? .never
                )
            }
        } catch GitHubAPIError.httpStatus(401, _) {
            state.transition(
                .authorizationExpired(
                    message: "账户授权已失效，请重新登录。"
                )
            )
        } catch {
            state.errorMessage = error.localizedDescription
        }
        persistPreferences()
    }

    public func setRepositorySelected(
        repositoryID: Int64,
        isSelected: Bool
    ) {
        if isSelected {
            state.selectedRepositoryIDs.insert(repositoryID)
        } else {
            state.selectedRepositoryIDs.remove(repositoryID)
        }
        setPreferenceMode(
            repositoryID: repositoryID,
            mode: isSelected ? .manual : .never
        )
        persistPreferences()
    }

    public func updateSyncMode(
        repositoryID: Int64,
        mode: RepositorySyncMode
    ) {
        setPreferenceMode(repositoryID: repositoryID, mode: mode)
        if mode.shouldSyncInitially {
            state.selectedRepositoryIDs.insert(repositoryID)
        } else {
            state.selectedRepositoryIDs.remove(repositoryID)
        }
        persistPreferences()
    }

    public func setSyncModeForAllRepositories(_ mode: RepositorySyncMode) {
        state.preferences = state.repositories.map {
            RepositorySyncPreference(repositoryID: $0.id, mode: mode)
        }
        state.selectedRepositoryIDs = mode.shouldSyncInitially
            ? Set(state.repositories.map(\.id))
            : []
        persistPreferences()
    }

    public func selectSyncDestination(_ destination: URL) {
        do {
            try dependencies.syncDestinationStore.save(
                destination: destination
            )
            syncDestination = destination
            state.errorMessage = nil
        } catch {
            state.errorMessage = error.localizedDescription
        }
        persistPreferences()
    }

    public func startSync() async {
        activeSyncTask?.cancel()
        isDownloadPaused = false
        let selectedRepositoryIDs = state.selectedRepositoryIDs
        guard !selectedRepositoryIDs.isEmpty else {
            state.transition(.downloadConfigured([]))
            state.transition(.syncFinished)
            return
        }
        guard let syncDestination else {
            state.errorMessage = "请先选择仓库存储目录。"
            state.route = .repositorySync
            return
        }
        let conflicts = SyncDestinationInspector.conflicts(
            repositories: state.repositories,
            selectedRepositoryIDs: selectedRepositoryIDs,
            destination: syncDestination
        )
        guard conflicts.isEmpty else {
            let names = conflicts.prefix(3).map(\.lastPathComponent)
                .joined(separator: "、")
            let remaining = conflicts.count - min(conflicts.count, 3)
            let suffix = remaining > 0 ? "等 \(conflicts.count) 个仓库" : ""
            state.errorMessage = "存储目录中存在同名内容：\(names)\(suffix)。请选择其他目录，或确认它们是同一远程仓库。"
            state.route = .repositorySync
            return
        }

        state.transition(.downloadConfigured(selectedRepositoryIDs))
        persistPreferences()
        let operationID = UUID()
        activeSyncID = operationID
        let repositories = state.repositories
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runSync(
                repositories: repositories,
                selectedRepositoryIDs: selectedRepositoryIDs
            )
        }
        activeSyncTask = task
        await task.value
        if activeSyncID == operationID {
            activeSyncTask = nil
            activeSyncID = nil
            isDownloadPaused = false
        }
    }

    public func skipInitialDownload() {
        activeSyncTask?.cancel()
        activeSyncTask = nil
        activeSyncID = nil
        isWorking = false
        isDownloadPaused = false
        state.errorMessage = nil
        state.selectedRepositoryIDs = []
        state.preferences = state.repositories.map {
            RepositorySyncPreference(repositoryID: $0.id, mode: .never)
        }
        persistPreferences()
        state.transition(.downloadConfigured([]))
        state.transition(.syncFinished)
    }

    public func pauseDownload() {
        do {
            try dependencies.syncService.pause()
            isDownloadPaused = true
            state.errorMessage = nil
            state.progress.currentFile = "下载已暂停"
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    public func resumeDownload() {
        do {
            try dependencies.syncService.resume()
            isDownloadPaused = false
            state.errorMessage = nil
            state.progress.currentFile = "正在继续下载…"
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    public func syncRepositoryFromWorkspace(
        _ repository: Repository,
        mode: RepositorySyncMode
    ) async {
        guard mode != .never else {
            return
        }
        if !state.repositories.contains(where: { $0.id == repository.id }) {
            state.repositories.append(repository)
        }
        updateSyncMode(repositoryID: repository.id, mode: mode)
        state.failedRepositoryIDs.removeAll { $0 == repository.id }
        state.errorMessage = nil
        state.progress = SyncProgress(completed: 0, total: 1)
        state.route = .syncProgress
        await runSync(
            repositories: [repository],
            selectedRepositoryIDs: [repository.id]
        )
    }

    public func stopSync() {
        activeSyncTask?.cancel()
        activeSyncTask = nil
        activeSyncID = nil
        isWorking = false
        isDownloadPaused = false
        state.errorMessage = nil
        state.progress.currentFile = "下载已停止"
        state.route = .repositorySync
    }

    public func prepareRepositoryResync() {
        activeSyncTask?.cancel()
        activeSyncTask = nil
        activeSyncID = nil
        isWorking = false
        state.errorMessage = nil
        state.route = .repositorySync
        if state.preferences.isEmpty {
            state.preferences = state.repositories.map {
                RepositorySyncPreference(
                    repositoryID: $0.id,
                    mode: .manual
                )
            }
        }
        state.selectedRepositoryIDs = Set(
            state.preferences
                .filter(\.shouldSyncInitially)
                .map(\.repositoryID)
        )
    }

    public func prepareReauthorization() {
        activeSyncTask?.cancel()
        activeSyncTask = nil
        activeSyncID = nil
        shouldReturnToWorkspaceAfterReauthorization = state.route == .complete
        isWorking = false
        state.canResumeSync = true
        state.errorMessage = "账户令牌不可用，请重新授权。"
        state.route = .authorizationExpired
    }

    public func retryFailed() async {
        let failedIDs = Set(state.failedRepositoryIDs)
        let repositories = state.repositories.filter { failedIDs.contains($0.id) }
        state.failedRepositoryIDs.removeAll()
        state.errorMessage = nil
        state.route = .syncProgress
        await runSync(
            repositories: repositories,
            selectedRepositoryIDs: failedIDs
        )
    }

    public func retry(repositoryID: Int64) async {
        guard let repository = state.repositories.first(
            where: { $0.id == repositoryID }
        ) else {
            return
        }
        state.failedRepositoryIDs.removeAll { $0 == repositoryID }
        state.errorMessage = nil
        state.route = .syncProgress
        await runSync(
            repositories: [repository],
            selectedRepositoryIDs: [repositoryID]
        )
    }

    public func skipFailedRepositories() {
        state.failedRepositoryIDs.removeAll()
        state.errorMessage = nil
        state.transition(.syncFinished)
    }

    public func resumeAfterNetwork() async {
        state.transition(.networkRestored)
        await runSync(
            repositories: state.repositories,
            selectedRepositoryIDs: state.selectedRepositoryIDs
        )
    }

    public func reauthorizeEnterprise(token: String) async {
        guard let account = state.account else {
            state.errorMessage = "尚未连接企业 GitHub 账户。"
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            let renewedAccount = try await dependencies.enterpriseConnector.verify(
                serverURL: account.serverURL,
                token: token
            )
            try dependencies.credentialStore.save(
                token: token,
                accountID: renewedAccount.id
            )
            try dependencies.accountSessionStore.save(account: renewedAccount)
            state.transition(.reauthorized(renewedAccount))
            finishWorkspaceReauthorizationIfNeeded()
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    public func startNetworkMonitoring() {
        networkTask?.cancel()
        let updates = dependencies.networkMonitor.statusUpdates()
        networkTask = Task { @MainActor [weak self] in
            for await status in updates {
                guard let self else { return }
                if status == .disconnected, state.route == .syncProgress {
                    state.transition(.networkLost)
                } else if status == .connected,
                          state.route == .networkInterrupted {
                    await resumeAfterNetwork()
                }
            }
        }
    }

    public func stopNetworkMonitoring() {
        networkTask?.cancel()
        networkTask = nil
    }

    private func authenticateGitHub(
        token: String,
        isReauthorization: Bool
    ) async {
        guard let token = normalizedToken(token) else {
            state.errorMessage = "请输入 GitHub Personal Access Token。"
            return
        }

        isWorking = true
        state.errorMessage = nil
        defer { isWorking = false }

        do {
            let temporaryAccount = GitHubAccount(
                id: "github.com:pending",
                login: "",
                name: nil,
                avatarURL: nil,
                serverURL: URL(string: "https://github.com")!,
                kind: .githubDotCom,
                scopes: []
            )
            let api = try dependencies.apiProvider.api(for: temporaryAccount)
            let account = try await api.currentUser(token: token)
            try dependencies.credentialStore.save(
                token: token,
                accountID: account.id
            )
            try dependencies.accountSessionStore.save(account: account)

            if isReauthorization {
                state.transition(.reauthorized(account))
                finishWorkspaceReauthorizationIfNeeded()
            } else {
                state.transition(.accountVerified(account))
            }
        } catch GitHubAPIError.httpStatus(401, _) {
            state.errorMessage = "令牌无效或已过期，请检查后重新输入。"
        } catch GitHubAPIError.httpStatus(403, let message) {
            state.errorMessage = message ?? "令牌权限不足，请检查仓库访问权限。"
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func finishWorkspaceReauthorizationIfNeeded() {
        guard shouldReturnToWorkspaceAfterReauthorization else {
            return
        }
        shouldReturnToWorkspaceAfterReauthorization = false
        state.route = .complete
    }

    private func runSync(
        repositories: [Repository],
        selectedRepositoryIDs: Set<Int64>
    ) async {
        guard let syncDestination else {
            state.errorMessage = "尚未选择仓库存储目录。"
            state.route = .repositorySync
            return
        }
        isWorking = true
        state.errorMessage = nil
        defer { isWorking = false }

        do {
            let accessToken: String?
            if let account = state.account {
                accessToken = try dependencies.credentialStore.token(
                    accountID: account.id
                )
            } else {
                accessToken = nil
            }
            let stream = dependencies.syncService.sync(
                repositories: repositories,
                selectedRepositoryIDs: selectedRepositoryIDs,
                destination: syncDestination,
                accessToken: accessToken
            )
            for try await event in stream {
                guard handle(syncEvent: event) else {
                    return
                }
            }
        } catch let failure as SyncFailure {
            if failure != .cancelled {
                handle(syncFailure: failure, repositoryID: nil)
            }
        } catch is CancellationError {
            return
        } catch {
            state.errorMessage = error.localizedDescription
            state.route = .syncError
        }
    }

    private func handle(syncEvent: SyncEvent) -> Bool {
        switch syncEvent {
        case let .repositoryStarted(repository):
            state.progress.currentRepository = repository.fullName
            state.progress.currentFile = nil
            state.progress.currentRepositoryFraction = 0
            state.progress.currentRepositoryPhase = "正在准备"
            return true

        case let .fileChanged(_, path):
            state.progress.currentFile = path
            return true

        case let .repositoryProgress(_, progress):
            state.progress.currentRepositoryFraction = progress.fraction
            state.progress.currentRepositoryPhase = progress.phase
            state.progress.currentFile = progress.activity
            return true

        case let .progress(progress):
            let currentRepository = state.progress.currentRepository
            let currentFile = state.progress.currentFile
            let currentRepositoryFraction =
                state.progress.currentRepositoryFraction
            let currentRepositoryPhase =
                state.progress.currentRepositoryPhase
            state.progress = progress
            state.progress.currentRepository = progress.currentRepository
                ?? currentRepository
            state.progress.currentFile = progress.currentFile ?? currentFile
            state.progress.currentRepositoryFraction =
                progress.currentRepositoryFraction
                ?? currentRepositoryFraction
            state.progress.currentRepositoryPhase =
                progress.currentRepositoryPhase
                ?? currentRepositoryPhase
            return true

        case let .repositoryFailed(repositoryID, failure):
            handle(syncFailure: failure, repositoryID: repositoryID)
            return false

        case .finished:
            if state.route == .syncProgress {
                state.transition(.syncFinished)
            }
            return true
        }
    }

    private func handle(
        syncFailure: SyncFailure,
        repositoryID: Int64?
    ) {
        switch syncFailure {
        case let .networkInterrupted(message):
            state.transition(.networkLost)
            state.errorMessage = message

        case let .authorizationExpired(message):
            state.transition(.authorizationExpired(message: message))

        case let .commandFailed(message):
            state.transition(
                .repositoryFailed(
                    id: repositoryID ?? -1,
                    message: message
                )
            )

        case .cancelled:
            return
        }
    }

    private func normalizedURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }

    private func setPreferenceMode(
        repositoryID: Int64,
        mode: RepositorySyncMode
    ) {
        if let index = state.preferences.firstIndex(
            where: { $0.repositoryID == repositoryID }
        ) {
            state.preferences[index].mode = mode
        } else {
            state.preferences.append(
                RepositorySyncPreference(
                    repositoryID: repositoryID,
                    mode: mode
                )
            )
        }
    }

    private func restoredPreferences(
        repositories: [Repository],
        accountID: String
    ) throws -> [RepositorySyncPreference] {
        let stored = try dependencies.repositorySyncPreferenceStore.load(
            accountID: accountID
        )
        let storedModes = Dictionary(
            stored.map { ($0.repositoryID, $0.mode) },
            uniquingKeysWith: { _, newest in newest }
        )
        return repositories.map {
            RepositorySyncPreference(
                repositoryID: $0.id,
                mode: storedModes[$0.id] ?? .never
            )
        }
    }

    private func persistPreferences() {
        guard let account = state.account else {
            return
        }
        do {
            try dependencies.repositorySyncPreferenceStore.save(
                state.preferences,
                accountID: account.id
            )
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }
}
