import GitMateCore
import SwiftUI

struct GitMateRootView: View {
    @Bindable var onboarding: OnboardingViewModel

    var body: some View {
        if onboarding.state.route == .complete,
           let account = onboarding.state.account {
            WorkspaceRootView(
                session: WorkspaceSession(
                    account: account,
                    repositories: onboarding.state.repositories,
                    route: .dashboard
                )
            )
        } else {
            OnboardingRootView(viewModel: onboarding)
        }
    }
}
