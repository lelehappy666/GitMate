import GitMateCore
import SwiftUI

struct SyncProgressView: View {
    let viewModel: OnboardingViewModel

    private var progress: SyncProgress { viewModel.state.progress }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("正在同步仓库")
                        .font(.system(size: 28, weight: .bold))
                    Text("文件会实时写入本机，窗口可以保持在后台。")
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
                Spacer()
                Label("连接正常", systemImage: "circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitMateTheme.success)
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(progress.completed) / \(progress.total)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("仓库")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GitMateTheme.textSecondary)
                    Spacer()
                    Text("\(Int(progress.fraction * 100))%")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(GitMateTheme.accent)
                }

                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .tint(GitMateTheme.accent)
                    .scaleEffect(x: 1, y: 2.4)
                    .accessibilityLabel("首次同步总进度")
                    .accessibilityValue("\(Int(progress.fraction * 100))%")

                HStack(spacing: 12) {
                    statusBox(
                        icon: "arrow.triangle.branch",
                        title: "当前仓库",
                        value: progress.currentRepository ?? "正在准备…"
                    )
                    statusBox(
                        icon: "doc.text",
                        title: "当前文件",
                        value: progress.currentFile ?? "等待文件…",
                        monospaced: true
                    )
                }
            }
            .gitMateCard(padding: 24)

            VStack(spacing: 0) {
                HStack {
                    Text("仓库队列")
                    Spacer()
                    Text("状态")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GitMateTheme.textSecondary)
                .padding(.horizontal, 18)
                .frame(height: 38)
                .background(GitMateTheme.panel)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.state.repositories) { repository in
                            repositoryStatusRow(repository)
                            Divider().padding(.leading, 58)
                        }
                    }
                }
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(GitMateTheme.border, lineWidth: 1)
            }

            HStack {
                Label(
                    "同步中断后会保留已完成文件，并从现场继续。",
                    systemImage: "externaldrive.badge.checkmark"
                )
                .font(.system(size: 12))
                .foregroundStyle(GitMateTheme.textSecondary)
                Spacer()
                Text("正在计算剩余时间")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GitMateTheme.textTertiary)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func statusBox(
        icon: String,
        title: String,
        value: String,
        monospaced: Bool = false
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(GitMateTheme.accent)
                .frame(width: 38, height: 38)
                .background(GitMateTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GitMateTheme.textSecondary)
                Text(value)
                    .font(
                        .system(
                            size: 13,
                            weight: .semibold,
                            design: monospaced ? .monospaced : .default
                        )
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(GitMateTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func repositoryStatusRow(_ repository: Repository) -> some View {
        let isCurrent = progress.currentRepository == repository.fullName
        let isFailed = viewModel.state.failedRepositoryIDs.contains(repository.id)

        return HStack(spacing: 12) {
            GitMateAvatar(url: repository.ownerAvatarURL, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(repository.fullName)
                    .font(.system(size: 13, weight: .semibold))
                Text(repository.defaultBranch)
                    .font(.system(size: 11))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer()
            if isFailed {
                Label("失败", systemImage: "xmark.circle.fill")
                    .foregroundStyle(GitMateTheme.danger)
            } else if isCurrent {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("同步中")
                }
                .foregroundStyle(GitMateTheme.accent)
            } else {
                Text("等待")
                    .foregroundStyle(GitMateTheme.textTertiary)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 18)
        .frame(height: 58)
    }
}
