import AppKit
import GitMateCore
import SwiftUI

@MainActor
struct LocalGitViewDependencies {
    let reader: any WorkingTreeReading
    let watcher: (any RepositoryFileSystemWatching)?
    let diff: any GitDiffServicing
    let commit: any GitCommitServicing
    let stash: any GitStashServicing
    let history: any GitHistoryOperationServicing
    let conflict: any GitConflictServicing
    let remote: any GitRemoteServicing
    let transfer: any GitTransferServicing

    static func production(
        credentialStore: any CredentialStore
    ) -> LocalGitViewDependencies {
        let executor = ProcessGitCommandExecutor()
        let coordinator = RepositoryOperationCoordinator()
        let credentialEnvironment = GitCredentialEnvironment(
            credentialStore: credentialStore
        )
        return LocalGitViewDependencies(
            reader: WorkingTreeReader(executor: executor),
            watcher: RepositoryFileSystemWatcher(),
            diff: GitDiffService(
                executor: executor,
                coordinator: coordinator
            ),
            commit: GitCommitService(
                executor: executor,
                coordinator: coordinator
            ),
            stash: GitStashService(
                executor: executor,
                coordinator: coordinator
            ),
            history: GitHistoryOperationService(
                executor: executor,
                coordinator: coordinator
            ),
            conflict: GitConflictService(
                executor: executor,
                coordinator: coordinator
            ),
            remote: GitRemoteService(
                executor: executor,
                coordinator: coordinator,
                credentialEnvironment: credentialEnvironment
            ),
            transfer: GitTransferService(
                executor: executor,
                coordinator: coordinator,
                credentialEnvironment: credentialEnvironment
            )
        )
    }
}

struct LocalGitRootView: View {
    let repositoryURL: URL
    let credentialContext: GitCredentialContext
    let isPreview: Bool

    @State private var route: LocalGitRoute
    @State private var workingTreeViewModel: WorkingTreeViewModel
    @State private var diffViewModel: FileDiffViewModel
    @State private var commitViewModel: CommitComposerViewModel
    @State private var stashViewModel: StashViewModel
    @State private var historyViewModel: HistoryOperationViewModel
    @State private var conflictViewModel: ConflictResolutionViewModel
    @State private var remoteViewModel: RemoteManagementViewModel
    @State private var transferViewModel: RemoteTransferViewModel
    @State private var conflictCount = 0
    @State private var hasActiveOperation = false

    private let stashService: any GitStashServicing
    private let historyService: any GitHistoryOperationServicing
    private let conflictService: any GitConflictServicing
    private let remoteService: any GitRemoteServicing

    init(
        repositoryURL: URL,
        credentialContext: GitCredentialContext,
        initialRoute: LocalGitRoute = .workingTree,
        isPreview: Bool = false,
        dependencies: LocalGitViewDependencies? = nil
    ) {
        let dependencies = dependencies
            ?? LocalGitViewDependencies.production(
                credentialStore: KeychainCredentialStore()
            )
        self.repositoryURL = repositoryURL
        self.credentialContext = credentialContext
        self.isPreview = isPreview
        self.stashService = dependencies.stash
        self.historyService = dependencies.history
        self.conflictService = dependencies.conflict
        self.remoteService = dependencies.remote
        _route = State(initialValue: initialRoute)
        _workingTreeViewModel = State(
            initialValue: WorkingTreeViewModel(
                repositoryURL: repositoryURL,
                reader: dependencies.reader,
                watcher: dependencies.watcher,
                mutationService: dependencies.diff
            )
        )
        _diffViewModel = State(
            initialValue: FileDiffViewModel(
                repositoryURL: repositoryURL,
                service: dependencies.diff
            )
        )
        _commitViewModel = State(
            initialValue: CommitComposerViewModel(
                repositoryURL: repositoryURL,
                service: dependencies.commit
            )
        )
        _stashViewModel = State(
            initialValue: StashViewModel(
                repositoryURL: repositoryURL,
                service: dependencies.stash
            )
        )
        _historyViewModel = State(
            initialValue: HistoryOperationViewModel(
                repositoryURL: repositoryURL,
                service: dependencies.history
            )
        )
        _conflictViewModel = State(
            initialValue: ConflictResolutionViewModel(
                repositoryURL: repositoryURL,
                service: dependencies.conflict
            )
        )
        _remoteViewModel = State(
            initialValue: RemoteManagementViewModel(
                repositoryURL: repositoryURL,
                service: dependencies.remote
            )
        )
        _transferViewModel = State(
            initialValue: RemoteTransferViewModel(
                repositoryURL: repositoryURL,
                context: credentialContext,
                service: dependencies.transfer
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            applicationHeader
            HStack(spacing: 0) {
                LocalGitSidebar(
                    route: $route,
                    repositoryName: repositoryURL.lastPathComponent,
                    isPreview: isPreview,
                    conflictCount: conflictCount,
                    hasActiveOperation: hasActiveOperation
                )
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(
            minWidth: 1_040,
            idealWidth: 1_180,
            minHeight: 680,
            idealHeight: 760
        )
        .background(.white)
        .foregroundStyle(GitMateTheme.textPrimary)
        .task { await refreshIndicators() }
        .onChange(of: route) {
            Task { await refreshIndicators() }
        }
    }

    private var applicationHeader: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(GitMateTheme.accent)
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("GitMate")
                    .font(.system(size: 15, weight: .bold))
                Text("本地 Git")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer()
            Text(String(format: "%02d", route.pageNumber))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(GitMateTheme.accent)
            Text("/ 37")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(GitMateTheme.textTertiary)
        }
        .padding(.horizontal, 24)
        .frame(height: 58)
        .background(.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GitMateTheme.border)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .workingTree:
            WorkingTreeView(
                workingTreeViewModel: workingTreeViewModel,
                diffViewModel: diffViewModel
            )
        case .commit:
            CommitComposerView(
                workingTreeViewModel: workingTreeViewModel,
                diffViewModel: diffViewModel,
                commitViewModel: commitViewModel
            )
        case .diff:
            WorkingTreeView(
                workingTreeViewModel: workingTreeViewModel,
                diffViewModel: diffViewModel
            )
        case .stash:
            StashManagerView(
                viewModel: stashViewModel,
                service: stashService,
                repositoryURL: repositoryURL,
                onShowConflicts: { route = .conflicts }
            )
        case .historyOperation:
            HistoryOperationView(
                viewModel: historyViewModel,
                onShowConflicts: { route = .conflicts }
            )
        case .conflicts:
            ConflictResolverView(
                viewModel: conflictViewModel,
                service: conflictService,
                repositoryURL: repositoryURL,
                onOpenExternalEditor: {
                    guard !isPreview else {
                        return
                    }
                    NSWorkspace.shared.open($0)
                }
            )
        case .remotes:
            RemoteManagementView(
                viewModel: remoteViewModel,
                service: remoteService,
                repositoryURL: repositoryURL,
                credentialContext: credentialContext
            )
        case .transfer:
            RemoteTransferView(
                viewModel: transferViewModel,
                onShowConflicts: { route = .conflicts }
            )
        }
    }

    private func refreshIndicators() async {
        conflictCount = (
            try? await conflictService.files(
                repositoryURL: repositoryURL
            ).count
        ) ?? 0
        hasActiveOperation = (
            try? await historyService.state(
                repositoryURL: repositoryURL
            ).kind
        ) != nil
    }
}
