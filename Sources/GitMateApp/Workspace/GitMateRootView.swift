import GitMateCore
import SwiftUI

struct GitMateRootView: View {
    @Bindable var onboarding: OnboardingViewModel
    @State private var workspaceRoute: WorkspaceRoute = .dashboard
    let runtime: WorkspaceRuntimeDependencies

    var body: some View {
        if onboarding.state.route == .complete,
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
                }
            )
            .id(account.id)
        } else {
            OnboardingRootView(viewModel: onboarding)
        }
    }
}
