import GitMateCore
import SwiftUI

struct GitMateRootView: View {
    @Bindable var onboarding: OnboardingViewModel
    @Bindable var experimentalFeatures: ExperimentalFeaturePreferences
    @State private var workspaceRoute: WorkspaceRoute = .dashboard
    @State private var repositoryWorkspace:
        RepositoryWorkspaceRuntime?
    @State private var repositoryWorkspaceError: String?
    @State private var isSettingsPresented = false
    let runtime: WorkspaceRuntimeDependencies
    let repositoryWorkspaceFactory:
        RepositoryWorkspaceRuntimeFactory?

    private var repositoryManagementAccess: RepositoryManagementAccessPolicy {
        RepositoryManagementAccessPolicy(
            isEnabled: experimentalFeatures.repositoryManagementEnabled
        )
    }

    var body: some View {
        Group {
            if let repositoryWorkspace {
                RepositoryWorkspaceRootView(
                    runtime: repositoryWorkspace,
                    onReturnToWorkspace: {
                        self.repositoryWorkspace = nil
                    },
                    onOpenWorkspaceRoute: { route in
                        workspaceRoute = route
                        self.repositoryWorkspace = nil
                    },
                    onResync: {
                        self.repositoryWorkspace = nil
                        onboarding.prepareRepositoryResync()
                    },
                    onSettingsRequested: { isSettingsPresented = true }
                )
            } else if onboarding.state.route == .complete,
                      let account = onboarding.state.account {
                WorkspaceRootView(
                    session: WorkspaceSession(
                        account: account,
                        repositories: onboarding.state.repositories,
                        route: workspaceRoute
                    ),
                    preferences: onboarding.state.preferences,
                    runtime: runtime,
                    onResync: onboarding.prepareRepositoryResync,
                    onReauthorize: { route in
                        workspaceRoute = route
                        onboarding.prepareReauthorization()
                    },
                    onDownloadRepository: { repository, mode in
                        Task {
                            await onboarding.syncRepositoryFromWorkspace(
                                repository,
                                mode: mode
                            )
                        }
                    },
                    onOpenRepositoryTools: { repository in
                        openRepositoryTools(
                            account: account,
                            repository: repository
                        )
                    },
                    repositoryManagementEnabled:
                        experimentalFeatures.repositoryManagementEnabled,
                    onSettingsRequested: { isSettingsPresented = true }
                )
                .id(account.id)
            } else {
                OnboardingRootView(viewModel: onboarding)
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            GitMateSettingsView(
                preferences: experimentalFeatures,
                onClose: { isSettingsPresented = false }
            )
        }
        .onChange(of: experimentalFeatures.repositoryManagementEnabled) {
            _, _ in
            if repositoryManagementAccess.shouldDismissWorkspace(
                isPresented: repositoryWorkspace != nil
            ) {
                repositoryWorkspace = nil
            }
        }
        .alert(
            "无法打开分支与议题工作区",
            isPresented: Binding(
                get: { repositoryWorkspaceError != nil },
                set: { isPresented in
                    if !isPresented {
                        repositoryWorkspaceError = nil
                    }
                }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(repositoryWorkspaceError ?? "请稍后重试。")
        }
    }

    private func openRepositoryTools(
        account: GitHubAccount,
        repository: Repository
    ) {
        guard repositoryManagementAccess.canOpenWorkspace else { return }
        guard let repositoryWorkspaceFactory else {
            repositoryWorkspaceError = "仓库工具尚未准备完成。"
            return
        }
        do {
            repositoryWorkspace = try repositoryWorkspaceFactory.make(
                account: account,
                repository: repository
            )
        } catch {
            repositoryWorkspaceError = error.localizedDescription
        }
    }
}
