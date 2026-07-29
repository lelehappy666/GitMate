import GitMateCore
import SwiftUI

struct NetworkInterruptedView: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(GitMateTheme.warning.opacity(0.12))
                Image(systemName: "wifi.slash")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(GitMateTheme.warning)
            }
            .frame(width: 104, height: 104)

            VStack(spacing: 8) {
                Text("网络连接已中断")
                    .font(.system(size: 30, weight: .bold))
                Text("下载已安全暂停，已完成的文件和进度都不会丢失。")
                    .font(.system(size: 15))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }

            VStack(spacing: 0) {
                informationRow(
                    icon: "pause.fill",
                    title: "当前状态",
                    value: "已暂停，等待网络恢复"
                )
                Divider()
                informationRow(
                    icon: "externaldrive.badge.checkmark",
                    title: "本机数据",
                    value: "下载现场已保存"
                )
                Divider()
                informationRow(
                    icon: "arrow.clockwise",
                    title: "恢复方式",
                    value: "联网后自动继续"
                )
            }
            .frame(width: 560)
            .gitMateCard(padding: 0)

            if let error = viewModel.state.errorMessage {
                Text(error)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }

            Button {
                Task { await viewModel.resumeAfterNetwork() }
            } label: {
                HStack {
                    if viewModel.isWorking {
                        ProgressView().controlSize(.small)
                    }
                    Image(systemName: "arrow.clockwise")
                    Text("立即重试连接")
                }
            }
            .buttonStyle(GitMateButtonStyle(role: .primary))
            .accessibilityIdentifier("onboarding.network.resume")
            .disabled(viewModel.isWorking)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func informationRow(
        icon: String,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .foregroundStyle(GitMateTheme.accent)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }
}
