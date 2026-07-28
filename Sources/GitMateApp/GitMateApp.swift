import Foundation
import GitMateCore
import SwiftUI

@main
@MainActor
struct GitMateApp: App {
    @State private var viewModel: OnboardingViewModel

    init() {
        if let page = Self.previewPage {
            _viewModel = State(
                initialValue: OnboardingPreviewFactory.make(page: page)
            )
            return
        }

        let api = URLSessionGitHubAPI()
        let clientID = ProcessInfo.processInfo.environment[
            "GITMATE_GITHUB_CLIENT_ID"
        ] ?? ""
        let deviceFlow = GitHubDeviceFlow(
            clientID: clientID,
            scopes: ["repo", "read:user", "workflow"]
        )
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let syncDestination = applicationSupport
            .appending(path: "GitMate", directoryHint: .isDirectory)
            .appending(path: "Repositories", directoryHint: .isDirectory)
        let dependencies = OnboardingDependencies(
            deviceAuthorizer: deviceFlow,
            apiProvider: DefaultGitHubAPIProvider(githubDotComAPI: api),
            enterpriseConnector: EnterpriseConnectionService(),
            credentialStore: KeychainCredentialStore(),
            syncService: GitRepositorySyncService(),
            networkMonitor: NWPathNetworkMonitor(),
            syncDestination: syncDestination
        )
        _viewModel = State(
            initialValue: OnboardingViewModel(dependencies: dependencies)
        )
    }

    private static var previewPage: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--preview-page"),
              arguments.indices.contains(flagIndex + 1),
              let page = Int(arguments[flagIndex + 1]),
              (1...9).contains(page) else {
            return nil
        }
        return page
    }

    var body: some Scene {
        WindowGroup {
            OnboardingRootView(viewModel: viewModel)
                .onAppear {
                    viewModel.startNetworkMonitoring()
                }
                .onDisappear {
                    viewModel.stopNetworkMonitoring()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_180, height: 760)
    }
}
