import Foundation
import GitMateCore
import SwiftUI

@main
@MainActor
struct GitMateApp: App {
    @State private var viewModel: OnboardingViewModel
    private let workspaceRuntime: WorkspaceRuntimeDependencies
    private let repositoryWorkspaceFactory:
        RepositoryWorkspaceRuntimeFactory?
    private let workspacePreview: WorkspaceRootView?

    init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
        let syncDestination = applicationSupport
            .appending(path: "GitMate", directoryHint: .isDirectory)
            .appending(path: "Repositories", directoryHint: .isDirectory)
        let cacheDirectory = caches.appending(
            path: "GitMate",
            directoryHint: .isDirectory
        )
        let syncDestinationStore = UserDefaultsSyncDestinationStore()

        if let page = Self.previewPage {
            _viewModel = State(
                initialValue: OnboardingPreviewFactory.make(
                    page: min(page, 9)
                )
            )
            workspaceRuntime = WorkspaceRuntimeDependencies(
                syncDestination: FileManager.default.temporaryDirectory,
                cacheDirectory: FileManager.default.temporaryDirectory,
                credentialStore: InMemoryCredentialStore()
            )
            repositoryWorkspaceFactory = nil
            workspacePreview = page >= 10
                ? WorkspacePreviewFactory.make(
                    page: page,
                    state: Self.previewState
                )
                : nil
            return
        }

        let api = URLSessionGitHubAPI()
        let credentialStore = KeychainCredentialStore()
        let workspaceCache = JSONWorkspaceCache(
            rootDirectory: cacheDirectory.appending(
                path: "Workspace",
                directoryHint: .isDirectory
            )
        )
        let repositoryCatalog = LocalRepositoryCatalog(
            rootDirectoryProvider: {
                syncDestinationStore.destination()
                    ?? syncDestination
            }
        )
        let dependencies = OnboardingDependencies(
            apiProvider: DefaultGitHubAPIProvider(githubDotComAPI: api),
            enterpriseConnector: EnterpriseConnectionService(),
            credentialStore: credentialStore,
            accountSessionStore: UserDefaultsAccountSessionStore(),
            syncService: GitRepositorySyncService(),
            networkMonitor: NWPathNetworkMonitor(),
            syncDestinationStore: syncDestinationStore,
            workspaceCache: workspaceCache,
            repositorySyncPreferenceStore:
                UserDefaultsRepositorySyncPreferenceStore()
        )
        _viewModel = State(
            initialValue: OnboardingViewModel(dependencies: dependencies)
        )
        workspaceRuntime = WorkspaceRuntimeDependencies(
            syncDestination: syncDestination,
            cacheDirectory: cacheDirectory,
            credentialStore: credentialStore,
            catalog: repositoryCatalog,
            cache: workspaceCache
        )
        repositoryWorkspaceFactory = RepositoryWorkspaceRuntimeFactory(
            credentialStore: credentialStore,
            catalog: repositoryCatalog
        )
        workspacePreview = nil
    }

    private static var previewPage: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--preview-page"),
              arguments.indices.contains(flagIndex + 1),
              let page = Int(arguments[flagIndex + 1]),
              (1...15).contains(page) else {
            return nil
        }
        return page
    }

    private static var previewState: WorkspacePreviewState {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--preview-state"),
              arguments.indices.contains(flagIndex + 1),
              let state = WorkspacePreviewState(
                  rawValue: arguments[flagIndex + 1].lowercased()
              ) else {
            return .normal
        }
        return state
    }

    var body: some Scene {
        WindowGroup {
            if let workspacePreview {
                workspacePreview
            } else {
                GitMateRootView(
                    onboarding: viewModel,
                    runtime: workspaceRuntime,
                    repositoryWorkspaceFactory:
                        repositoryWorkspaceFactory
                )
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_180, height: 760)
    }
}
