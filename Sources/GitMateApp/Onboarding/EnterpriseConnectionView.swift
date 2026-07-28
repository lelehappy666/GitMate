import GitMateCore
import SwiftUI

struct EnterpriseConnectionView: View {
    let viewModel: OnboardingViewModel
    @State private var server = ""
    @State private var token = ""

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(GitMateTheme.accent)
                Text("连接 GitHub Enterprise")
                    .font(.system(size: 28, weight: .bold))
                Text("使用企业服务器地址与 Personal Access Token")
                    .foregroundStyle(GitMateTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 17) {
                fieldTitle("服务器地址")
                TextField("github.company.com", text: $server)
                    .textFieldStyle(.plain)
                    .padding(13)
                    .background(GitMateTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("企业 GitHub 服务器地址")

                fieldTitle("Personal Access Token")
                SecureField("ghp_••••••••••••••••", text: $token)
                    .textFieldStyle(.plain)
                    .padding(13)
                    .background(GitMateTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("企业 GitHub 访问令牌")

                if let error = viewModel.state.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GitMateTheme.danger)
                }

                HStack(spacing: 12) {
                    Button("返回") {
                        viewModel.returnToWelcome()
                    }
                    .buttonStyle(GitMateButtonStyle(role: .secondary))

                    Button {
                        Task {
                            await viewModel.connectEnterprise(
                                serverURLText: server,
                                token: token
                            )
                        }
                    } label: {
                        HStack {
                            if viewModel.isWorking {
                                ProgressView().controlSize(.small)
                            }
                            Text("验证并连接")
                        }
                    }
                    .buttonStyle(
                        GitMateButtonStyle(role: .primary, fillsWidth: true)
                    )
                    .disabled(server.isEmpty || token.isEmpty || viewModel.isWorking)
                }
            }
            .frame(width: 500)
            .gitMateCard(padding: 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fieldTitle(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(GitMateTheme.textSecondary)
    }
}
