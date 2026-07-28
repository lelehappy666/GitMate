import Foundation
import Observation

@MainActor
@Observable
public final class OnboardingViewModel {
    public private(set) var state: OnboardingState
    public private(set) var deviceCode: DeviceCode?
    public private(set) var isWorking = false

    @ObservationIgnored
    private let dependencies: OnboardingDependencies

    @ObservationIgnored
    private var networkTask: Task<Void, Never>?

    public init(
        dependencies: OnboardingDependencies,
        initialState: OnboardingState = OnboardingState()
    ) {
        self.dependencies = dependencies
        state = initialState
    }

    deinit {
        networkTask?.cancel()
    }

    public func startGitHubLogin() async {
        state.transition(.loginRequested)
        await authenticateGitHub(isReauthorization: false)
    }

    public func showEnterpriseConnection() {
        state.transition(.enterpriseRequested)
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
            state.preferences = repositories.map {
                RepositorySyncPreference(
                    repositoryID: $0.id,
                    mode: .automatic
                )
            }
        } catch GitHubAPIError.httpStatus(401, _) {
            state.transition(.authorizationExpired(message: "账户授权已失效，请重新登录。"))
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    public func updateSyncMode(
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

    public func startSync() async {
        state.transition(.syncConfigured(state.preferences))
        await runSync(
            repositories: state.repositories,
            preferences: state.preferences
        )
    }

    public func retryFailed() async {
        let failedIDs = Set(state.failedRepositoryIDs)
        let repositories = state.repositories.filter { failedIDs.contains($0.id) }
        let preferences = repositories.map {
            RepositorySyncPreference(repositoryID: $0.id, mode: .manual)
        }
        state.failedRepositoryIDs.removeAll()
        state.errorMessage = nil
        state.route = .syncProgress
        await runSync(repositories: repositories, preferences: preferences)
    }

    public func resumeAfterNetwork() async {
        state.transition(.networkRestored)
        await runSync(
            repositories: state.repositories,
            preferences: state.preferences
        )
    }

    public func reauthorize() async {
        await authenticateGitHub(isReauthorization: true)
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
            state.transition(.reauthorized(renewedAccount))
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
                }
            }
        }
    }

    public func stopNetworkMonitoring() {
        networkTask?.cancel()
        networkTask = nil
    }

    private func authenticateGitHub(isReauthorization: Bool) async {
        isWorking = true
        state.errorMessage = nil
        defer { isWorking = false }

        do {
            let code = try await dependencies.deviceAuthorizer.start()
            deviceCode = code
            let accessToken = try await dependencies.deviceAuthorizer.poll(
                deviceCode: code.deviceCode,
                interval: code.interval
            )

            let temporaryAccount = GitHubAccount(
                id: "github.com:pending",
                login: "",
                name: nil,
                avatarURL: nil,
                serverURL: URL(string: "https://github.com")!,
                kind: .githubDotCom,
                scopes: accessToken.scopes
            )
            let api = try dependencies.apiProvider.api(for: temporaryAccount)
            var account = try await api.currentUser(token: accessToken.accessToken)
            if account.scopes.isEmpty {
                account = GitHubAccount(
                    id: account.id,
                    login: account.login,
                    name: account.name,
                    avatarURL: account.avatarURL,
                    serverURL: account.serverURL,
                    kind: account.kind,
                    scopes: accessToken.scopes
                )
            }
            try dependencies.credentialStore.save(
                token: accessToken.accessToken,
                accountID: account.id
            )

            if isReauthorization {
                state.transition(.reauthorized(account))
            } else {
                state.transition(.accountVerified(account))
            }
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func runSync(
        repositories: [Repository],
        preferences: [RepositorySyncPreference]
    ) async {
        isWorking = true
        state.errorMessage = nil
        defer { isWorking = false }

        do {
            let stream = dependencies.syncService.sync(
                repositories: repositories,
                preferences: preferences,
                destination: dependencies.syncDestination
            )
            for try await event in stream {
                guard handle(syncEvent: event) else {
                    return
                }
            }
        } catch let failure as SyncFailure {
            handle(syncFailure: failure, repositoryID: nil)
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
            return true

        case let .fileChanged(_, path):
            state.progress.currentFile = path
            return true

        case let .progress(progress):
            let currentRepository = state.progress.currentRepository
            let currentFile = state.progress.currentFile
            state.progress = progress
            state.progress.currentRepository = progress.currentRepository
                ?? currentRepository
            state.progress.currentFile = progress.currentFile ?? currentFile
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
            state.errorMessage = syncFailure.message
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
}
