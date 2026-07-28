import GitMateCore
import SwiftUI

struct PermissionReviewView: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 20) {
            if let account = viewModel.state.account {
                HStack(spacing: 16) {
                    GitMateAvatar(url: account.avatarURL, size: 62)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.name ?? account.login)
                            .font(.system(size: 23, weight: .bold))
                        Text("@\(account.login)")
                            .foregroundStyle(GitMateTheme.textSecondary)
                        Text(account.serverURL.host() ?? account.serverURL.absoluteString)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(GitMateTheme.textTertiary)
                    }
                    Spacer()
                    Label("账户已验证", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GitMateTheme.success)
                }
                .gitMateCard(padding: 24)
            }

            HStack(alignment: .top, spacing: 16) {
                permissionCard(
                    icon: "folder.badge.gearshape",
                    title: "仓库访问",
                    detail: "读取你的公开与私有仓库，用于克隆、同步和管理。"
                )
                permissionCard(
                    icon: "person.crop.circle",
                    title: "账户资料",
                    detail: "读取用户名与真实头像，在软件中识别当前账户。"
                )
                permissionCard(
                    icon: "key.fill",
                    title: "本机安全",
                    detail: "令牌保存在 macOS 钥匙串，不写入项目文件。"
                )
            }

            if let error = viewModel.state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(GitMateTheme.danger)
            }

            HStack {
                Text("继续后将读取仓库列表，不会立即下载。")
                    .font(.system(size: 13))
                    .foregroundStyle(GitMateTheme.textSecondary)
                Spacer()
                Button {
                    Task { await viewModel.confirmPermissions() }
                } label: {
                    HStack {
                        if viewModel.isWorking {
                            ProgressView().controlSize(.small)
                        }
                        Text("确认并读取仓库")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(GitMateButtonStyle(role: .primary))
                .accessibilityIdentifier("onboarding.permission.confirm")
                .disabled(viewModel.isWorking)
            }
            .padding(.top, 4)
        }
        .frame(maxHeight: .infinity)
    }

    private func permissionCard(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(GitMateTheme.accent)
                .frame(width: 46, height: 46)
                .background(GitMateTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(title)
                .font(.system(size: 17, weight: .bold))
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(GitMateTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gitMateCard(padding: 20)
    }
}
