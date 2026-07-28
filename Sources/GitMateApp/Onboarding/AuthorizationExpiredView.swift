import GitMateCore
import SwiftUI

struct AuthorizationExpiredView: View {
    let viewModel: OnboardingViewModel
    @State private var enterpriseToken = ""

    private var isEnterprise: Bool {
        viewModel.state.account?.kind == .enterprise
    }

    var body: some View {
        HStack(spacing: 34) {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "key.slash.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(GitMateTheme.danger)
                Text("GitHub 授权已失效")
                    .font(.system(size: 30, weight: .bold))
                Text("重新授权后会从当前同步现场继续，不会重复下载已完成内容。")
                    .font(.system(size: 15))
                    .foregroundStyle(GitMateTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let account = viewModel.state.account {
                    HStack(spacing: 12) {
                        GitMateAvatar(url: account.avatarURL, size: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.login)
                                .font(.system(size: 14, weight: .bold))
                            Text(account.serverURL.host() ?? account.serverURL.absoluteString)
                                .font(.system(size: 11))
                                .foregroundStyle(GitMateTheme.textSecondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GitMateTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if isEnterprise {
                    SecureField("输入新的 Personal Access Token", text: $enterpriseToken)
                        .textFieldStyle(.plain)
                        .padding(13)
                        .background(GitMateTheme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if let error = viewModel.state.errorMessage {
                    Text(error)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(GitMateTheme.danger)
                }

                Button {
                    Task {
                        if isEnterprise {
                            await viewModel.reauthorizeEnterprise(token: enterpriseToken)
                        } else {
                            await viewModel.reauthorize()
                        }
                    }
                } label: {
                    HStack {
                        if viewModel.isWorking {
                            ProgressView().controlSize(.small)
                        }
                        Image(systemName: "checkmark.shield")
                        Text("重新授权并继续")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(GitMateButtonStyle(role: .primary, fillsWidth: true))
                .accessibilityIdentifier("onboarding.authorization.reauthorize")
                .disabled(viewModel.isWorking || (isEnterprise && enterpriseToken.isEmpty))

                Button("切换其他账户") {
                    viewModel.returnToWelcome()
                }
                .buttonStyle(
                    GitMateButtonStyle(role: .secondary, fillsWidth: true)
                )
            }
            .frame(width: 460)
            .gitMateCard(padding: 30)

            VStack(alignment: .leading, spacing: 22) {
                safetyItem(
                    number: "01",
                    title: "同步现场保留",
                    detail: "已完成仓库和当前文件不会被删除。"
                )
                safetyItem(
                    number: "02",
                    title: "安全替换令牌",
                    detail: "新令牌会覆盖钥匙串中的旧凭据。"
                )
                safetyItem(
                    number: "03",
                    title: "原位置继续",
                    detail: "授权完成后自动返回同步进度。"
                )
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private func safetyItem(
        number: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(GitMateTheme.accent)
                .frame(width: 38, height: 38)
                .background(GitMateTheme.accentSoft)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
        }
    }
}
