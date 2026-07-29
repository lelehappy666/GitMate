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
        let dependencies = OnboardingDependencies(
            apiProvider: DefaultGitHubAPIProvider(githubDotComAPI: api),
            enterpriseConnector: EnterpriseConnectionService(),
            credentialStore: KeychainCredentialStore(),
            accountSessionStore: UserDefaultsAccountSessionStore(),
            syncService: GitRepositorySyncService(),
            networkMonitor: NWPathNetworkMonitor(),
            syncDestinationStore: UserDefaultsSyncDestinationStore()
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
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_180, height: 760)
    }
}
