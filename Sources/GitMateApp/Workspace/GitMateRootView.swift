import GitMateCore
import SwiftUI

struct GitMateRootView: View {
    @Bindable var onboarding: OnboardingViewModel
    let runtime: WorkspaceRuntimeDependencies

    var body: some View {
        if onboarding.state.route == .complete,
           let account = onboarding.state.account {
            WorkspaceRootView(
                session: WorkspaceSession(
                    account: account,
                    repositories: onboarding.state.repositories,
                    route: .dashboard
                ),
                preferences: onboarding.state.preferences,
                runtime: runtime,
                onResync: onboarding.prepareRepositoryResync,
                onReauthorize: onboarding.prepareReauthorization
            )
            .id(account.id)
        } else {
            OnboardingRootView(viewModel: onboarding)
        }
    }
}
