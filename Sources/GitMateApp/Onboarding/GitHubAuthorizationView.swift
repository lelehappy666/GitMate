import AppKit
import GitMateCore
import SwiftUI

struct GitHubAuthorizationView: View {
    let viewModel: OnboardingViewModel
    @Environment(\.openURL) private var openURL

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

                Button {
                    if let url = viewModel.deviceCode?.verificationURI {
                        openURL(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "safari")
                        Text("打开 GitHub 授权页面")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                }
                .buttonStyle(GitMateButtonStyle(role: .primary, fillsWidth: true))
                .disabled(viewModel.deviceCode == nil)

                if viewModel.isWorking {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("等待 GitHub 授权…")
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
}
