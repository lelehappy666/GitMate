import Foundation
import GitMateCore
import SwiftUI

@main
@MainActor
struct GitMateApp: App {
    @State private var viewModel: OnboardingViewModel
    private let localRootView: LocalGitRootView?
    private let launchError: String?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let configuration: LocalGitLaunchConfiguration?
        do {
            configuration = try LocalGitLaunchConfiguration(
                arguments: arguments
            )
            launchError = nil
        } catch {
            configuration = nil
            launchError = GitOutputRedactor.redact(
                error.localizedDescription
            )
        }

        if let route = configuration?.previewRoute {
            localRootView = LocalGitPreviewFactory.make(
                page: route.pageNumber
            )
        } else if let repositoryURL = configuration?.repositoryURL {
            let accountID = (
                try? UserDefaultsAccountSessionStore().account()?.id
            ) ?? "未登录账户"
            localRootView = LocalGitRootView(
                repositoryURL: repositoryURL,
                credentialContext: GitCredentialContext(
                    accountID: accountID
                ),
                initialRoute: .workingTree
            )
        } else {
            localRootView = nil
        }

        if let page = Self.onboardingPreviewPage(arguments: arguments) {
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

    private static func onboardingPreviewPage(
        arguments: [String]
    ) -> Int? {
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
            if let launchError {
                ContentUnavailableView(
                    "无法打开本地仓库",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(launchError)
                )
                .frame(
                    minWidth: 1_040,
                    idealWidth: 1_180,
                    minHeight: 680,
                    idealHeight: 760
                )
            } else if let localRootView {
                localRootView
            } else {
                OnboardingRootView(viewModel: viewModel)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_180, height: 760)
    }
}
