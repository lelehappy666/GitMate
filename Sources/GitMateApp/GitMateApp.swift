import Foundation
import GitMateCore
import SwiftUI

@main
@MainActor
struct GitMateApp: App {
    @State private var onboardingViewModel: OnboardingViewModel?
    @State private var previewWorkspaceViewModel:
        RepositoryWorkspaceViewModel?
    private let workspaceFactory: RepositoryWorkspaceRuntimeFactory?

    init() {
        if let page = Self.previewPage {
            if (16...23).contains(page) {
                _onboardingViewModel = State(initialValue: nil)
                _previewWorkspaceViewModel = State(
                    initialValue: WorkspacePreviewFactory.make(page: page)
                )
            } else {
                _onboardingViewModel = State(
                    initialValue: OnboardingPreviewFactory.make(page: page)
                )
                _previewWorkspaceViewModel = State(initialValue: nil)
            }
            workspaceFactory = nil
            return
        }

        let api = URLSessionGitHubAPI()
        let credentialStore = KeychainCredentialStore()
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let syncDestination = applicationSupport
            .appending(path: "GitMate", directoryHint: .isDirectory)
            .appending(path: "Repositories", directoryHint: .isDirectory)
        let dependencies = OnboardingDependencies(
            apiProvider: DefaultGitHubAPIProvider(githubDotComAPI: api),
            enterpriseConnector: EnterpriseConnectionService(),
            credentialStore: credentialStore,
            accountSessionStore: UserDefaultsAccountSessionStore(),
            syncService: GitRepositorySyncService(),
            networkMonitor: NWPathNetworkMonitor(),
            syncDestination: syncDestination
        )
        _onboardingViewModel = State(
            initialValue: OnboardingViewModel(dependencies: dependencies)
        )
        _previewWorkspaceViewModel = State(initialValue: nil)
        workspaceFactory = RepositoryWorkspaceRuntimeFactory(
            credentialStore: credentialStore,
            syncDestination: syncDestination
        )
    }

    private static var previewPage: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--preview-page"),
              arguments.indices.contains(flagIndex + 1),
              let page = Int(arguments[flagIndex + 1]),
              (1...9).contains(page) || (16...23).contains(page) else {
            return nil
        }
        return page
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let previewWorkspaceViewModel {
                    RepositoryWorkspaceRootView(
                        viewModel: previewWorkspaceViewModel
                    )
                } else if let onboardingViewModel, let workspaceFactory {
                    GitMateApplicationRootView(
                        onboardingViewModel: onboardingViewModel,
                        workspaceFactory: workspaceFactory
                    )
                } else {
                    ProgressView("正在准备 GitMate…")
                }
            }
            .frame(width: 1_180, height: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1_180, height: 760)
    }
}
