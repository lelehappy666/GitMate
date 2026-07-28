import AppKit
import GitMateCore
import SwiftUI

struct SyncErrorView: View {
    let viewModel: OnboardingViewModel

    private var failedRepositories: [Repository] {
        let failed = Set(viewModel.state.failedRepositoryIDs)
        return viewModel.state.repositories.filter { failed.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(GitMateTheme.warning)
                    .frame(width: 66, height: 66)
                    .background(GitMateTheme.warning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 17))
                VStack(alignment: .leading, spacing: 6) {
                    Text("部分仓库同步失败")
                        .font(.system(size: 28, weight: .bold))
                    Text("已完成的仓库不受影响，你可以只重试失败项。")
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("错误原因")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitMateTheme.textSecondary)
                Text(viewModel.state.errorMessage ?? "同步命令未能完成。")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    .background(Color(red: 1, green: 0.97, blue: 0.94))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
            }
            .gitMateCard(padding: 20)

            VStack(spacing: 0) {
                ForEach(failedRepositories) { repository in
                    HStack(spacing: 12) {
                        GitMateAvatar(url: repository.ownerAvatarURL, size: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(repository.fullName)
                                .font(.system(size: 14, weight: .semibold))
                            Text("本机现场已保留")
                                .font(.system(size: 11))
                                .foregroundStyle(GitMateTheme.textSecondary)
                        }
                        Spacer()
                        Button("重试此仓库") {
                            Task {
                                await viewModel.retry(repositoryID: repository.id)
                            }
                        }
                        .buttonStyle(GitMateButtonStyle(role: .secondary))
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 68)
                    Divider()
                }
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(GitMateTheme.border, lineWidth: 1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button {
                    copyDiagnostics()
                } label: {
                    Label("复制诊断信息", systemImage: "doc.on.doc")
                }
                .buttonStyle(GitMateButtonStyle(role: .quiet))

                Button("跳过失败仓库") {
                    viewModel.skipFailedRepositories()
                }
                .buttonStyle(GitMateButtonStyle(role: .secondary))

                Spacer()

                Button {
                    Task { await viewModel.retryFailed() }
                } label: {
                    Label("重试全部失败项", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GitMateButtonStyle(role: .primary))
                .accessibilityIdentifier("onboarding.sync.retry")
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func copyDiagnostics() {
        let repositories = failedRepositories.map(\.fullName).joined(separator: "\n")
        let message = """
        GitMate 首次同步诊断
        失败仓库：
        \(repositories)

        错误：
        \(viewModel.state.errorMessage ?? "未知错误")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message, forType: .string)
    }
}
