import AppKit
import GitMateCore
import SwiftUI

struct WorkspaceRootView: View {
    @State private var session: WorkspaceSession
    @State private var selection: WorkspaceSelection
    @State private var apiAuthorizationRequired = false
    @State private var repositoryGroups: WorkspaceRepositoryGroups
    @State private var repositoryRevision = 0

    let preferences: [RepositorySyncPreference]
    let runtime: WorkspaceRuntimeDependencies
    let authorization: WorkspaceAuthorization
    let onResync: () -> Void
    let onReauthorize: (WorkspaceRoute) -> Void
    let onDownloadRepository:
        (Repository, RepositorySyncMode) -> Void

    init(
        session: WorkspaceSession,
        preferences: [RepositorySyncPreference],
        runtime: WorkspaceRuntimeDependencies,
        onResync: @escaping () -> Void,
        onReauthorize: @escaping (WorkspaceRoute) -> Void,
        onDownloadRepository:
            @escaping (Repository, RepositorySyncMode) -> Void = { _, _ in }
    ) {
        var initialSession = session
        let importedRepositories = (
            try? runtime.importedRepositories(for: session.account)
        ) ?? []
        for imported in importedRepositories {
            if let matchingRepository = initialSession.repositories.first(
                where: {
                    $0.normalizedFullName
                        == imported.repository.normalizedFullName
                }
            ) {
                runtime.catalog.register(
                    localURL: imported.localURL,
                    repositoryID: matchingRepository.id
                )
            } else if !initialSession.repositories.contains(
                where: { $0.id == imported.repository.id }
            ) {
                initialSession.repositories.append(imported.repository)
            }
        }

        _session = State(initialValue: initialSession)
        _selection = State(
            initialValue: WorkspaceSelection(route: initialSession.route)
        )
        let cachedRecords = (
            try? runtime.cache.load(accountID: session.account.id)
        )?.repositoryRecords ?? []
        let cachedRecordsByID = Dictionary(
            cachedRecords.map { ($0.repository.id, $0) },
            uniquingKeysWith: { _, newest in newest }
        )
        let records = initialSession.repositories.map { repository in
            (try? runtime.catalog.record(for: repository))
                ?? cachedRecordsByID[repository.id]
                ?? LocalRepositoryRecord(
                    repository: repository,
                    localURL: runtime.catalog.localURL(for: repository),
                    availability: .missing,
                    localSizeInBytes: 0,
                    lastInspectedAt: .distantPast
                )
        }
        _repositoryGroups = State(
            initialValue: WorkspaceRepositoryClassifier.classify(
                repositories: initialSession.repositories,
                records: records,
                preferences: preferences
            )
        )
        self.preferences = preferences
        self.runtime = runtime
        authorization = runtime.authorization(for: session.account)
        self.onResync = onResync
        self.onReauthorize = onReauthorize
        self.onDownloadRepository = onDownloadRepository
    }

    var body: some View {
        NavigationSplitView {
            WorkspaceSidebar(
                selection: $selection,
                repositories: repositoryGroups.local,
                account: session.account
            )
        } detail: {
            if apiAuthorizationRequired {
                reauthorizationView
            } else {
                switch authorization {
                case let .ready(token):
                    workspaceDetail(token: token)
                case .reauthorizationRequired:
                    reauthorizationView
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(
            minWidth: 1_040,
            idealWidth: 1_180,
            minHeight: 680,
            idealHeight: 760
        )
        .background(GitMateTheme.canvas.ignoresSafeArea())
        .onChange(of: selection) { _, selection in
            session.route = selection.route
        }
    }

    @ViewBuilder
    private func workspaceDetail(token: String) -> some View {
        let onRoute: (WorkspaceRoute) -> Void = { route in
            selection.route = route
        }
        switch selection.route {
        case .dashboard:
            DashboardPageContainer(
                account: session.account,
                repositories: repositoryGroups.local,
                token: token,
                loader: runtime.contentService(for: session.account),
                onAuthorizationRequired: requireReauthorization,
                showAllRepositories: {
                    selection.route = .repositories
                }
            )
            .id("dashboard-\(repositoryRevision)")
        case .repositories:
            RepositoryWallContainer(
                account: session.account,
                repositories: repositoryGroups.local,
                preferences: preferences,
                token: token,
                content: runtime.contentService(for: session.account),
                coverCache: runtime.coverCache,
                coverScheduler: runtime.coverScheduler(for: session.account),
                cloudAPI: try? runtime.repositoryAPI(
                    for: session.account
                ),
                onRoute: onRoute,
                onDownloadRepository: onDownloadRepository,
                onImportLocalRepository: importLocalRepository,
                onReconcileLocalRepository:
                    reconcileLocalRepositoryMetadata,
                onAuthorizationRequired: requireReauthorization
            )
            .id("repositories-\(repositoryRevision)")
        case let .repositoryOverview(repositoryID):
            if let repository = repository(repositoryID) {
                RepositoryOverviewPageContainer(
                    repository: repository,
                    account: session.account,
                    token: token,
                    loader: authorizationObservingLoader,
                    onRoute: onRoute,
                    onResync: {
                        selection.route = .repositories
                        onResync()
                    }
                )
            } else {
                missingRepositoryView
            }
        case let .readme(repositoryID):
            if let repository = repository(repositoryID) {
                READMEPageContainer(
                    repository: repository,
                    account: session.account,
                    token: token,
                    loader: authorizationObservingLoader
                )
            } else {
                missingRepositoryView
            }
        case let .filesAndCommits(repositoryID):
            if let repository = repository(repositoryID) {
                FilesCommitsPageContainer(
                    reader: runtime.localGit,
                    repositoryURL: runtime.catalog.localURL(for: repository)
                )
            } else {
                missingRepositoryView
            }
        case let .commitGraph(repositoryID):
            if let repository = repository(repositoryID) {
                CommitGraphPageContainer(
                    reader: runtime.localGit,
                    repositoryURL: runtime.catalog.localURL(for: repository)
                )
            } else {
                missingRepositoryView
            }
        }
    }

    private var authorizationObservingLoader:
        AuthorizationObservingRepositoryLoader
    {
        AuthorizationObservingRepositoryLoader(
            loader: runtime.contentService(for: session.account),
            onAuthorizationRequired: requireReauthorization
        )
    }

    private func requireReauthorization() {
        apiAuthorizationRequired = true
    }

    private var reauthorizationView: some View {
        WorkspaceReauthorizationView {
            onReauthorize(selection.route)
        }
    }

    private func repository(_ id: Int64) -> Repository? {
        session.repositories.first { $0.id == id }
    }

    private func importLocalRepository(at selectedURL: URL) async throws {
        let imported = try await runtime.importLocalRepository(
            at: selectedURL,
            account: session.account
        )
        let localRepository: Repository
        if let matchingIndex = session.repositories.firstIndex(
            where: {
                $0.normalizedFullName
                    == imported.repository.normalizedFullName
            }
        ) {
            runtime.catalog.register(
                localURL: imported.localURL,
                repositoryID: session.repositories[matchingIndex].id
            )
            localRepository = session.repositories[matchingIndex]
        } else if !session.repositories.contains(
            where: { $0.id == imported.repository.id }
        ) {
            session.repositories.append(imported.repository)
            localRepository = imported.repository
        } else {
            localRepository = imported.repository
        }
        promoteToLocal(repository: localRepository)
        repositoryRevision += 1
    }

    private func reconcileLocalRepositoryMetadata(
        _ remoteRepository: Repository
    ) {
        guard let matchingIndex = session.repositories.firstIndex(
            where: {
                $0.normalizedFullName
                    == remoteRepository.normalizedFullName
            }
        ) else {
            return
        }
        let existingRepository = session.repositories[matchingIndex]
        guard existingRepository != remoteRepository else {
            return
        }
        let localURL = runtime.catalog.localURL(
            for: existingRepository
        )
        session.repositories[matchingIndex] = remoteRepository
        runtime.catalog.register(
            localURL: localURL,
            repositoryID: remoteRepository.id
        )
        try? runtime.updateImportedRepositoryMetadata(
            remoteRepository,
            localURL: localURL,
            account: session.account
        )
        promoteToLocal(repository: remoteRepository)
        repositoryRevision += 1
    }

    private func promoteToLocal(repository: Repository) {
        var localFullNames = Set(
            repositoryGroups.local.map {
                $0.normalizedFullName
            }
        )
        localFullNames.insert(repository.normalizedFullName)
        let local = session.repositories.filter {
            localFullNames.contains($0.normalizedFullName)
        }
        let localIDs = Set(local.map(\.id))
        repositoryGroups = WorkspaceRepositoryGroups(
            local: local,
            cloud: session.repositories.filter {
                !localIDs.contains($0.id)
            }
        )
    }

    private var missingRepositoryView: some View {
        ContentUnavailableView(
            "仓库不可用",
            systemImage: "externaldrive.badge.exclamationmark",
            description: Text("该仓库已不在当前账户列表中，请返回全部仓库重新选择。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GitMateTheme.canvas)
    }
}

private struct DashboardPageContainer: View {
    @State private var viewModel: DashboardViewModel
    let onAuthorizationRequired: () -> Void
    let showAllRepositories: () -> Void

    init(
        account: GitHubAccount,
        repositories: [Repository],
        token: String,
        loader: any WorkspaceDashboardLoading,
        onAuthorizationRequired: @escaping () -> Void,
        showAllRepositories: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: DashboardViewModel(
                account: account,
                repositories: repositories,
                token: token,
                loader: loader
            )
        )
        self.onAuthorizationRequired = onAuthorizationRequired
        self.showAllRepositories = showAllRepositories
    }

    var body: some View {
        DashboardView(
            viewModel: viewModel,
            showAllRepositories: showAllRepositories
        )
        .onChange(of: viewModel.state.connectivity) { _, connectivity in
            if connectivity == .authorizationRequired {
                onAuthorizationRequired()
            }
        }
    }
}

private enum RepositoryLibraryTab {
    case local
    case cloud
}

private struct RepositoryWallContainer: View {
    let account: GitHubAccount
    let repositories: [Repository]
    let preferences: [RepositorySyncPreference]
    let token: String
    let content: WorkspaceContentService
    let coverCache: any RepositoryCoverCaching
    let coverScheduler: RepositoryCoverViewportScheduler
    let cloudAPI: (any GitHubAPI)?
    let onRoute: (WorkspaceRoute) -> Void
    let onDownloadRepository:
        (Repository, RepositorySyncMode) -> Void
    let onImportLocalRepository: (URL) async throws -> Void
    let onReconcileLocalRepository: (Repository) -> Void
    let onAuthorizationRequired: () -> Void

    @State private var selectedTab: RepositoryLibraryTab = .local
    @State private var localViewModel: RepositoryWallViewModel
    @State private var cloudViewModel: CloudRepositoryViewModel?
    @State private var cloudWallViewModel: RepositoryWallViewModel
    @State private var errorMessage: String?
    @State private var isImportingLocalRepository = false

    init(
        account: GitHubAccount,
        repositories: [Repository],
        preferences: [RepositorySyncPreference],
        token: String,
        content: WorkspaceContentService,
        coverCache: any RepositoryCoverCaching,
        coverScheduler: RepositoryCoverViewportScheduler,
        cloudAPI: (any GitHubAPI)?,
        onRoute: @escaping (WorkspaceRoute) -> Void,
        onDownloadRepository:
            @escaping (Repository, RepositorySyncMode) -> Void,
        onImportLocalRepository:
            @escaping (URL) async throws -> Void,
        onReconcileLocalRepository:
            @escaping (Repository) -> Void,
        onAuthorizationRequired: @escaping () -> Void
    ) {
        self.account = account
        self.repositories = repositories
        self.preferences = preferences
        self.token = token
        self.content = content
        self.coverCache = coverCache
        self.coverScheduler = coverScheduler
        self.cloudAPI = cloudAPI
        self.onRoute = onRoute
        self.onDownloadRepository = onDownloadRepository
        self.onImportLocalRepository = onImportLocalRepository
        self.onReconcileLocalRepository = onReconcileLocalRepository
        self.onAuthorizationRequired = onAuthorizationRequired

        let modes = Dictionary(
            uniqueKeysWithValues: preferences.map {
                ($0.repositoryID, $0.mode)
            }
        )
        let initialItems = repositories.map { repository in
            let mode = modes[repository.id] ?? .manual
            let language = repository.primaryLanguage
            return RepositoryPosterItem(
                repository: repository,
                language: language,
                syncMode: mode,
                syncState: mode == .never
                    ? .notSynchronized
                    : .needsAttention,
                updatedAt: nil,
                cover: .fallback(
                    FallbackRepositoryCover.make(
                        repository: repository,
                        language: language
                    )
                )
            )
        }
        _localViewModel = State(
            initialValue: RepositoryWallViewModel(
                items: initialItems,
                coverScheduler: coverScheduler,
                token: token
            )
        )
        _cloudWallViewModel = State(
            initialValue: RepositoryWallViewModel(
                items: [],
                coverScheduler: coverScheduler,
                token: token
            )
        )
        _cloudViewModel = State(
            initialValue: cloudAPI.map {
                CloudRepositoryViewModel(
                    api: $0,
                    token: token,
                    excludedRepositoryIDs: Set(
                        repositories.map(\.id)
                    ),
                    excludedRepositoryFullNames: Set(
                        repositories.map(\.fullName)
                    )
                )
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            repositoryTabs

            if selectedTab == .local {
                if let errorMessage {
                    statusBanner(
                        errorMessage,
                        symbol: "exclamationmark.triangle.fill",
                        color: GitMateTheme.warning
                    )
                }
                RepositoryWallView(
                    viewModel: localViewModel,
                    scope: .local,
                    onRoute: onRoute,
                    onAddLocal: chooseLocalRepository,
                    isAddingLocalRepository: isImportingLocalRepository
                )
            } else if let cloudViewModel {
                cloudStatus(for: cloudViewModel.phase)
                RepositoryWallView(
                    viewModel: cloudWallViewModel,
                    scope: .cloud,
                    onRefresh: refreshCloud,
                    onLoadNextPage: {
                        guard cloudViewModel.hasNextPage else {
                            return
                        }
                        loadNextCloudPage()
                    },
                    onDownload: onDownloadRepository
                )
            } else {
                ContentUnavailableView(
                    "云端仓库暂不可用",
                    systemImage: "icloud.slash",
                    description: Text("请重新授权 GitHub 账户后再试。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(GitMateTheme.canvas)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GitMateTheme.canvas)
        .task(id: account.id) {
            await loadLocal()
        }
        .onChange(of: selectedTab) { _, tab in
            guard tab == .cloud,
                  cloudViewModel?.repositories.isEmpty == true
            else {
                return
            }
            loadNextCloudPage()
        }
    }

    private var repositoryTabs: some View {
        HStack(spacing: 6) {
            tabButton(
                title: "本地仓库",
                count: repositories.count,
                tab: .local
            )
            tabButton(
                title: "云端仓库",
                count: cloudViewModel?.repositories.count ?? 0,
                tab: .cloud
            )
            Spacer()
            Text("本地仓库优先，云端仓库按需下载")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .padding(.horizontal, 28)
        .frame(minHeight: 54)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func tabButton(
        title: String,
        count: Int,
        tab: RepositoryLibraryTab
    ) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 7) {
                Text(title)
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(
                        selectedTab == tab
                            ? Color.white.opacity(0.82)
                            : GitMateTheme.panel
                    )
                    .clipShape(Capsule())
            }
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(
                selectedTab == tab
                    ? GitMateTheme.accent
                    : GitMateTheme.textSecondary
            )
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                selectedTab == tab
                    ? GitMateTheme.accent.opacity(0.12)
                    : Color.clear
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cloudStatus(
        for phase: CloudRepositoryLoadPhase
    ) -> some View {
        switch phase {
        case .idle, .loaded:
            EmptyView()
        case .loading:
            statusBanner(
                "正在加载下一批云端仓库…",
                symbol: "arrow.triangle.2.circlepath",
                color: GitMateTheme.accent
            )
        case let .rateLimited(resetAt):
            statusBanner(
                "GitHub 在线信息暂停，预计 \(resetAt.formatted(date: .omitted, time: .shortened)) 后可刷新；本地仓库功能不受影响。",
                symbol: "clock.badge.exclamationmark",
                color: GitMateTheme.warning
            )
        case let .failed(message):
            statusBanner(
                "云端仓库加载失败：\(message)",
                symbol: "icloud.slash",
                color: GitMateTheme.danger
            )
        }
    }

    private func statusBanner(
        _ message: String,
        symbol: String,
        color: Color
    ) -> some View {
        Label(message, systemImage: symbol)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(GitMateTheme.textPrimary)
            .padding(.horizontal, 18)
            .frame(
                maxWidth: .infinity,
                minHeight: 42,
                alignment: .leading
            )
            .background(color.opacity(0.12))
    }

    private func loadLocal() async {
        do {
            let updates = content.dashboardUpdates(
                account: account,
                repositories: repositories,
                token: token
            )
            let modes = Dictionary(
                uniqueKeysWithValues: preferences.map {
                    ($0.repositoryID, $0.mode)
                }
            )
            for try await dashboard in updates {
                try Task.checkCancellation()
                if dashboard.connectivity == .authorizationRequired {
                    onAuthorizationRequired()
                    return
                }
                let cards = dashboard.repositories.map {
                    RepositoryCardContent(
                        content: $0,
                        syncMode: modes[$0.repository.id] ?? .manual
                    )
                }
                let items = RepositoryPosterBuilder.make(
                    contents: cards,
                    extractor: RepositoryCoverExtractor(),
                    cache: coverCache
                )
                try Task.checkCancellation()
                errorMessage = nil
                localViewModel.updateItems(items)
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "本地与缓存数据暂时无法读取，请稍后重试。"
        }
    }

    private func loadNextCloudPage() {
        guard let cloudViewModel else {
            return
        }
        Task {
            await cloudViewModel.loadNextPage()
            cloudViewModel.matchedExcludedRepositories.forEach(
                onReconcileLocalRepository
            )
            synchronizeCloudWall(cloudViewModel.repositories)
        }
    }

    private func refreshCloud() {
        guard let cloudViewModel else {
            return
        }
        let knownIDs = Set(cloudViewModel.repositories.map(\.id))
        try? coverCache.markNeedsRefresh(repositoryIDs: knownIDs)
        cloudWallViewModel.markCoversForRefresh(
            repositoryIDs: knownIDs
        )
        Task {
            await cloudViewModel.refresh()
            cloudViewModel.matchedExcludedRepositories.forEach(
                onReconcileLocalRepository
            )
            synchronizeCloudWall(cloudViewModel.repositories)
        }
    }

    private func synchronizeCloudWall(
        _ repositories: [Repository]
    ) {
        cloudWallViewModel.updateItems(
            RepositoryPosterBuilder.makeCloud(
                repositories: repositories
            )
        )
    }

    private func chooseLocalRepository() {
        let panel = NSOpenPanel()
        panel.title = "添加本地 GitHub 仓库"
        panel.message = "选择已有 Git 仓库，GitMate 会原地管理，不复制或移动文件。"
        panel.prompt = "添加仓库"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK,
              let selectedURL = panel.url
        else {
            return
        }

        errorMessage = nil
        isImportingLocalRepository = true
        Task {
            defer {
                isImportingLocalRepository = false
            }
            do {
                try await onImportLocalRepository(selectedURL)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct AuthorizationObservingRepositoryLoader:
    RepositoryContentLoading,
    @unchecked Sendable
{
    let loader: any RepositoryContentLoading
    let onAuthorizationRequired: @MainActor @Sendable () -> Void

    func repositoryContent(
        repository: Repository,
        account: GitHubAccount,
        token: String
    ) async throws -> RepositoryContent {
        let content = try await loader.repositoryContent(
            repository: repository,
            account: account,
            token: token
        )
        if content.connectivity == .authorizationRequired {
            await onAuthorizationRequired()
        }
        return content
    }
}

private struct RepositoryOverviewPageContainer: View {
    @State private var viewModel: RepositoryOverviewViewModel
    let onRoute: (WorkspaceRoute) -> Void
    let onResync: () -> Void

    init(
        repository: Repository,
        account: GitHubAccount,
        token: String,
        loader: any RepositoryContentLoading,
        onRoute: @escaping (WorkspaceRoute) -> Void,
        onResync: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: RepositoryOverviewViewModel(
                repository: repository,
                account: account,
                token: token,
                loader: loader
            )
        )
        self.onRoute = onRoute
        self.onResync = onResync
    }

    var body: some View {
        RepositoryOverviewView(
            viewModel: viewModel,
            onRoute: onRoute,
            onResync: onResync
        )
    }
}

private struct READMEPageContainer: View {
    @State private var viewModel: READMEViewModel

    init(
        repository: Repository,
        account: GitHubAccount,
        token: String,
        loader: any RepositoryContentLoading
    ) {
        _viewModel = State(
            initialValue: READMEViewModel(
                repository: repository,
                account: account,
                token: token,
                loader: loader
            )
        )
    }

    var body: some View {
        READMEView(viewModel: viewModel)
    }
}

private struct FilesCommitsPageContainer: View {
    @State private var viewModel: FilesCommitsViewModel

    init(reader: any LocalGitReading, repositoryURL: URL) {
        _viewModel = State(
            initialValue: FilesCommitsViewModel(
                reader: reader,
                repositoryURL: repositoryURL
            )
        )
    }

    var body: some View {
        FilesCommitsView(viewModel: viewModel)
    }
}

private struct CommitGraphPageContainer: View {
    @State private var viewModel: CommitGraphViewModel

    init(reader: any LocalGitReading, repositoryURL: URL) {
        _viewModel = State(
            initialValue: CommitGraphViewModel(
                reader: reader,
                repositoryURL: repositoryURL
            )
        )
    }

    var body: some View {
        CommitGraphView(viewModel: viewModel)
    }
}

private struct WorkspaceReauthorizationView: View {
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                "需要重新授权",
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
        } description: {
            Text("当前账户令牌不存在或 GitHub 已拒绝授权。重新授权后将返回刚才浏览的工作区页面。")
        } actions: {
            Button("重新授权", action: action)
                .buttonStyle(.borderedProminent)
                .tint(GitMateTheme.accent)
                .accessibilityIdentifier(
                    "workspace.authorization.reauthorize"
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GitMateTheme.canvas)
    }
}
