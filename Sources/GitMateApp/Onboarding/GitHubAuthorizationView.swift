import GitMateCore
import SwiftUI

struct GitHubAuthorizationView: View {
    let viewModel: OnboardingViewModel
    @State private var token = ""

    var body: some View {
        HStack(spacing: 42) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("使用 GitHub 令牌登录")
                        .font(.system(size: 30, weight: .bold))
                    Text("粘贴 Personal Access Token，验证成功后即可继续。")
                        .font(.system(size: 15))
                        .foregroundStyle(GitMateTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 11) {
                    Text("Personal Access Token")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GitMateTheme.textSecondary)

                    SecureField("github_pat_… 或 ghp_…", text: $token)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, design: .monospaced))
                        .padding(14)
                        .background(GitMateTheme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .accessibilityLabel("GitHub Personal Access Token")
                        .onSubmit {
                            connect()
                        }

                    Text("令牌仅用于连接 GitHub，并保存在这台 Mac 的钥匙串中。")
                        .font(.system(size: 12))
                        .foregroundStyle(GitMateTheme.textSecondary)
                }

                if let error = viewModel.state.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GitMateTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    connect()
                } label: {
                    HStack {
                        if viewModel.isWorking {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "key.fill")
                        }
                        Text(viewModel.isWorking ? "正在验证账户…" : "验证令牌并登录")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(GitMateButtonStyle(role: .primary, fillsWidth: true))
                .disabled(
                    token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || viewModel.isWorking
                )
                .accessibilityIdentifier("onboarding.github.token.connect")

                HStack(spacing: 6) {
                    Text("还没有令牌？")
                        .foregroundStyle(GitMateTheme.textSecondary)
                    Link(
                        "前往 GitHub 创建",
                        destination: URL(string: "https://github.com/settings/tokens")!
                    )
                    .fontWeight(.semibold)
                }
                .font(.system(size: 12))

                Button("返回登录方式") {
                    viewModel.returnToWelcome()
                }
                .buttonStyle(GitMateButtonStyle(role: .secondary, fillsWidth: true))
            }
            .frame(width: 440)
            .gitMateCard(padding: 30)

            VStack(alignment: .leading, spacing: 22) {
                Text("建议权限")
                    .font(.system(size: 20, weight: .bold))

                permissionItem(
                    icon: "folder.fill",
                    title: "仓库访问",
                    detail: "Classic Token 勾选 repo；细粒度令牌请选择需要管理的仓库。"
                )
                permissionItem(
                    icon: "person.crop.circle.fill",
                    title: "账户资料",
                    detail: "Classic Token 勾选 read:user，用于读取用户名与头像。"
                )
                permissionItem(
                    icon: "play.square.stack.fill",
                    title: "Actions（可选）",
                    detail: "需要管理 GitHub Actions 时，再增加 workflow 权限。"
                )

                Label("GitMate 不会把令牌写入项目或明文配置文件", systemImage: "lock.shield.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GitMateTheme.success)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 34)
        }
        .frame(maxHeight: .infinity)
    }

    private func permissionItem(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(GitMateTheme.accent)
                .frame(width: 42, height: 42)
                .background(GitMateTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(GitMateTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func connect() {
        Task {
            await viewModel.connectGitHub(token: token)
        }
    }
}
