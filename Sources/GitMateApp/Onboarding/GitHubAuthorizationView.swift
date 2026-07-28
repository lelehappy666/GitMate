import AppKit
import GitMateCore
import SwiftUI

struct GitHubAuthorizationView: View {
    let viewModel: OnboardingViewModel
    @Environment(\.openURL) private var openURL
    @State private var clientID = ""

    var body: some View {
        HStack(spacing: 42) {
            VStack(alignment: .leading, spacing: 18) {
                Text("在浏览器中授权")
                    .font(.system(size: 30, weight: .bold))
                Text("复制验证码，然后在 GitHub 完成登录。")
                    .font(.system(size: 15))
                    .foregroundStyle(GitMateTheme.textSecondary)

                VStack(alignment: .leading, spacing: 12) {
                    Text("设备验证码")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GitMateTheme.textSecondary)
                    HStack(spacing: 14) {
                        Text(viewModel.deviceCode?.userCode ?? "正在生成…")
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .tracking(2)
                        Spacer()
                        Button {
                            if let code = viewModel.deviceCode?.userCode {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(code, forType: .string)
                            }
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(GitMateButtonStyle(role: .quiet))
                        .disabled(viewModel.deviceCode == nil)
                    }
                    .padding(18)
                    .background(GitMateTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                }

                if viewModel.needsGitHubClientID {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("首次使用需要配置 Client ID")
                            .font(.system(size: 13, weight: .bold))
                        Text("Client ID 只保存在这台 Mac，用于向 GitHub 获取设备验证码。")
                            .font(.system(size: 12))
                            .foregroundStyle(GitMateTheme.textSecondary)

                        HStack(spacing: 10) {
                            TextField("GitHub OAuth Client ID", text: $clientID)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    saveClientID()
                                }

                            Button("保存并重试") {
                                saveClientID()
                            }
                            .buttonStyle(GitMateButtonStyle(role: .secondary))
                            .disabled(
                                clientID
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty || viewModel.isWorking
                            )
                        }

                        Link(
                            "没有 Client ID？前往创建 GitHub OAuth App",
                            destination: URL(
                                string: "https://github.com/settings/applications/new"
                            )!
                        )
                        .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(14)
                    .background(GitMateTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    let url = viewModel.deviceCode?.verificationURI
                        ?? URL(string: "https://github.com/login/device")!
                    openURL(url)
                } label: {
                    HStack {
                        Image(systemName: "safari")
                        Text("打开 GitHub 授权页面")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                }
                .buttonStyle(GitMateButtonStyle(role: .primary, fillsWidth: true))

                if viewModel.isWorking {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(
                            viewModel.deviceCode == nil
                                ? "正在获取设备验证码…"
                                : "等待 GitHub 授权…"
                        )
                            .foregroundStyle(GitMateTheme.textSecondary)
                    }
                }

                if let error = viewModel.state.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GitMateTheme.danger)
                }
            }
            .frame(width: 430)
            .gitMateCard(padding: 30)

            VStack(spacing: 18) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(GitMateTheme.accent)
                Text("GitMate 不会看到你的密码")
                    .font(.system(size: 18, weight: .bold))
                Text("授权由 GitHub 官方页面完成，访问令牌只保存在这台 Mac 的钥匙串中。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(GitMateTheme.textSecondary)
                    .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private func saveClientID() {
        Task {
            await viewModel.configureGitHubClientIDAndRetry(clientID)
        }
    }
}
