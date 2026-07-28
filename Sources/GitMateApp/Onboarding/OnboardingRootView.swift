import GitMateCore
import SwiftUI

struct OnboardingRootView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            applicationHeader

            ZStack {
                GitMateTheme.canvas
                    .ignoresSafeArea()

                Group {
                    switch viewModel.state.route {
                    case .welcome:
                        WelcomeView(viewModel: viewModel)
                    case .githubAuthorization:
                        GitHubAuthorizationView(viewModel: viewModel)
                    case .enterpriseConnection:
                        EnterpriseConnectionView(viewModel: viewModel)
                    case .permissionReview:
                        PermissionReviewView(viewModel: viewModel)
                    case .repositorySync:
                        RepositorySyncSetupView(viewModel: viewModel)
                    case .syncProgress:
                        OnboardingPendingView(title: "正在准备同步")
                    case .syncError:
                        OnboardingPendingView(title: "同步遇到问题")
                    case .networkInterrupted:
                        OnboardingPendingView(title: "网络连接已中断")
                    case .authorizationExpired:
                        OnboardingPendingView(title: "GitHub 授权已失效")
                    case .complete:
                        completionView
                    }
                }
                .frame(maxWidth: GitMateTheme.contentMaxWidth, maxHeight: .infinity)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
        }
        .frame(minWidth: 1_040, idealWidth: 1_180, minHeight: 680, idealHeight: 760)
        .background(GitMateTheme.background)
        .foregroundStyle(GitMateTheme.textPrimary)
    }

    private var applicationHeader: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(GitMateTheme.accent)
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("GitMate")
                    .font(.system(size: 15, weight: .bold))
                Text("GitHub for Mac")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }

            Spacer()

            if let page = viewModel.state.route.pageNumber {
                Text(String(format: "%02d", page))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(GitMateTheme.accent)
                Text("/ 09")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(GitMateTheme.textTertiary)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 58)
        .background(.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GitMateTheme.border)
                .frame(height: 1)
        }
    }

    private var completionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(GitMateTheme.success)
            Text("首次同步已完成")
                .font(.system(size: 28, weight: .bold))
            Text("账户与仓库已准备好。")
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .frame(maxWidth: 520)
        .gitMateCard(padding: 40)
    }
}

private struct OnboardingPendingView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 24, weight: .bold))
            .gitMateCard(padding: 32)
    }
}
