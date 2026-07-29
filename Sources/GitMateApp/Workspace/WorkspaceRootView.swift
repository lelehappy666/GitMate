import GitMateCore
import SwiftUI

struct WorkspaceRootView: View {
    @State private var session: WorkspaceSession
    @State private var selection: WorkspaceSelection
    @State private var apiAuthorizationRequired = false

    let preferences: [RepositorySyncPreference]
    let runtime: WorkspaceRuntimeDependencies
    let authorization: WorkspaceAuthorization
    let onResync: () -> Void
    let onReauthorize: (WorkspaceRoute) -> Void

    init(
        session: WorkspaceSession,
        preferences: [RepositorySyncPreference],
        runtime: WorkspaceRuntimeDependencies,
        onResync: @escaping () -> Void,
        onReauthorize: @escaping (WorkspaceRoute) -> Void
    ) {
        _session = State(initialValue: session)
        _selection = State(initialValue: WorkspaceSelection(route: session.route))
        self.preferences = preferences
        self.runtime = runtime
        authorization = runtime.authorization(for: session.account)
        self.onResync = onResync
        self.onReauthorize = onReauthorize
    }

    var body: some View {
        NavigationSplitView {
            WorkspaceSidebar(
                selection: $selection,
                repositories: session.repositories,
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
        .background(GitMateTheme.background)
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
                repositories: session.repositories,
                token: token,
                loader: runtime.contentService(for: session.account),
                onAuthorizationRequired: requireReauthorization,
                showAllRepositories: {
                    selection.route = .repositories
                }
            )
        case .repositories:
            RepositoryWallContainer(
                account: session.account,
                repositories: session.repositories,
                preferences: preferences,
                token: token,
                content: runtime.contentService(for: session.account),
                coverCache: runtime.coverCache,
                coverLoader: runtime.coverLoader,
                onRoute: onRoute,
                onAuthorizationRequired: requireReauthorization
            )
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

private struct RepositoryWallContainer: View {
    let account: GitHubAccount
    let repositories: [Repository]
    let preferences: [RepositorySyncPreference]
    let token: String
    let content: WorkspaceContentService
    let coverCache: any RepositoryCoverCaching
    let coverLoader: any RepositoryCoverLoading
    let onRoute: (WorkspaceRoute) -> Void
    let onAuthorizationRequired: () -> Void

    @State private var viewModel: RepositoryWallViewModel
    @State private var errorMessage: String?

    init(
        account: GitHubAccount,
        repositories: [Repository],
        preferences: [RepositorySyncPreference],
        token: String,
        content: WorkspaceContentService,
        coverCache: any RepositoryCoverCaching,
        coverLoader: any RepositoryCoverLoading,
        onRoute: @escaping (WorkspaceRoute) -> Void,
        onAuthorizationRequired: @escaping () -> Void
    ) {
        self.account = account
        self.repositories = repositories
        self.preferences = preferences
        self.token = token
        self.content = content
        self.coverCache = coverCache
        self.coverLoader = coverLoader
        self.onRoute = onRoute
        self.onAuthorizationRequired = onAuthorizationRequired

        let modes = Dictionary(
            uniqueKeysWithValues: preferences.map {
                ($0.repositoryID, $0.mode)
            }
        )
        let initialItems = repositories.map { repository in
            let mode = modes[repository.id] ?? .manual
            return RepositoryPosterItem(
                repository: repository,
                language: nil,
                syncMode: mode,
                syncState: mode == .never
                    ? .notSynchronized
                    : .needsAttention,
                updatedAt: nil,
                cover: .fallback(
                    FallbackRepositoryCover.make(
                        repository: repository,
                        language: nil
                    )
                )
            )
        }
        _viewModel = State(
            initialValue: RepositoryWallViewModel(
                items: initialItems,
                coverLoader: coverLoader
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                Label(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(GitMateTheme.textPrimary)
                .padding(.horizontal, 18)
                .frame(
                    maxWidth: .infinity,
                    minHeight: 42,
                    alignment: .leading
                )
                .background(GitMateTheme.warning.opacity(0.13))
            }
            RepositoryWallView(
                viewModel: viewModel,
                onRoute: onRoute
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GitMateTheme.canvas)
        .task(id: account.id) {
            await load()
        }
    }

    private func load() async {
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
                viewModel.updateItems(items)
            }
            await viewModel.resolvePendingCovers()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "本地与缓存数据暂时无法读取，请稍后重试。"
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
