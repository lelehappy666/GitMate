import Foundation
import GitMateCore
import SwiftUI

@MainActor
struct RepositoryWorkspaceRuntimeFactory {
    let credentialStore: any CredentialStore
    let catalog: LocalRepositoryCatalog

    func make(
        account: GitHubAccount,
        repository: Repository
    ) throws -> RepositoryWorkspaceViewModel {
        let apiBaseURL: URL
        switch account.kind {
        case .githubDotCom:
            apiBaseURL = URL(string: "https://api.github.com")!
        case .enterprise:
            apiBaseURL = try EnterpriseEndpoint(
                serverURL: account.serverURL
            ).apiBaseURL
        }

        let client = GitHubRESTClient(apiBaseURL: apiBaseURL)
        let issuesAPI = URLSessionGitHubIssuesAPI(
            client: client,
            repositoryFullName: repository.fullName
        )
        let localCandidate = catalog.localURL(for: repository)
        let gitDirectory = localCandidate.appending(
            path: ".git",
            directoryHint: .isDirectory
        )
        let localDirectory = FileManager.default.fileExists(
            atPath: gitDirectory.path
        ) ? localCandidate : nil

        return RepositoryWorkspaceViewModel(
            context: RepositoryWorkspaceContext(
                account: account,
                repository: repository,
                localDirectory: localDirectory,
                tokenAccountID: account.id
            ),
            dependencies: RepositoryWorkspaceDependencies(
                localGit: ProcessLocalRepositoryGitService(),
                branchesAPI: URLSessionGitHubBranchesAPI(
                    client: client,
                    repositoryFullName: repository.fullName
                ),
                issuesAPI: issuesAPI,
                credentialStore: credentialStore,
                persistenceStore: UserDefaultsWorkspacePersistenceStore(),
                labelMergeService: LabelMergeService(api: issuesAPI)
            )
        )
    }
}

@MainActor
struct GitMateApplicationRootView: View {
    @Bindable var onboardingViewModel: OnboardingViewModel
    let workspaceFactory: RepositoryWorkspaceRuntimeFactory
    @State private var workspaceViewModel: RepositoryWorkspaceViewModel? = nil
    @State private var workspaceError: String? = nil

    init(
        onboardingViewModel: OnboardingViewModel,
        workspaceFactory: RepositoryWorkspaceRuntimeFactory
    ) {
        self.onboardingViewModel = onboardingViewModel
        self.workspaceFactory = workspaceFactory
    }

    var body: some View {
        Group {
            if let workspaceViewModel {
                RepositoryWorkspaceRootView(viewModel: workspaceViewModel)
            } else if let workspaceError {
                workspaceLaunchError(workspaceError)
            } else {
                OnboardingRootView(viewModel: onboardingViewModel)
            }
        }
        .onChange(
            of: onboardingViewModel.state.route,
            initial: true
        ) { _, route in
            guard route == .complete else {
                return
            }
            openInitialRepository()
        }
    }

    private func openInitialRepository() {
        guard workspaceViewModel == nil else {
            return
        }
        guard let account = onboardingViewModel.state.account else {
            workspaceError = "同步已完成，但没有可用的 GitHub 账户。"
            return
        }

        let preferredIDs = Set(
            onboardingViewModel.state.preferences
                .filter { $0.mode != .never }
                .map(\.repositoryID)
        )
        let repository = onboardingViewModel.state.repositories.first {
            preferredIDs.contains($0.id)
        } ?? onboardingViewModel.state.repositories.first

        guard let repository else {
            workspaceError = "账户下没有可打开的仓库。"
            return
        }

        do {
            workspaceViewModel = try workspaceFactory.make(
                account: account,
                repository: repository
            )
        } catch {
            workspaceError = error.localizedDescription
        }
    }

    private func workspaceLaunchError(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(GitMateTheme.warning)
            Text("无法打开仓库工作区")
                .font(.system(size: 22, weight: .bold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(GitMateTheme.textSecondary)
            Button("重试") {
                workspaceError = nil
                openInitialRepository()
            }
            .buttonStyle(GitMateButtonStyle(role: .primary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GitMateTheme.canvas)
    }
}
