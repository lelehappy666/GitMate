import AppKit
import GitMateCore
import SwiftUI

struct SyncProgressView: View {
    let viewModel: OnboardingViewModel

    private var progress: SyncProgress { viewModel.state.progress }
    private var selectedRepositories: [Repository] {
        return viewModel.state.repositories.filter {
            viewModel.state.selectedRepositoryIDs.contains($0.id)
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(
                        viewModel.isDownloadPaused
                            ? "首次下载已暂停"
                            : "正在下载仓库"
                    )
                        .font(.system(size: 28, weight: .bold))
                    Text("文件会实时写入本机；本次只执行 Clone。")
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
                Spacer()
                Label("连接正常", systemImage: "circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitMateTheme.success)

                Button {
                    if viewModel.isDownloadPaused {
                        viewModel.resumeDownload()
                    } else {
                        viewModel.pauseDownload()
                    }
                } label: {
                    Label(
                        viewModel.isDownloadPaused ? "继续下载" : "暂停下载",
                        systemImage: viewModel.isDownloadPaused
                            ? "play.circle.fill"
                            : "pause.circle.fill"
                    )
                }
                .buttonStyle(GitMateButtonStyle(role: .secondary))
                .accessibilityIdentifier("onboarding.download.pause")

                Button {
                    viewModel.stopSync()
                } label: {
                    Label("停止下载", systemImage: "stop.circle.fill")
                }
                .buttonStyle(GitMateButtonStyle(role: .destructive))
                .accessibilityIdentifier("onboarding.sync.stop")
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("仓库下载进度")
                        .font(.system(size: 13, weight: .bold))
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
                    .accessibilityLabel("仓库下载总进度")
                    .accessibilityValue("\(Int(progress.fraction * 100))%")

                Divider()

                HStack(alignment: .firstTextBaseline) {
                    Text("当前仓库进度")
                        .font(.system(size: 13, weight: .bold))
                    Text(
                        progress.currentRepositoryPhase
                            ?? "正在读取 Git 进度"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
                    Spacer()
                    if let fraction = progress.currentRepositoryFraction {
                        Text("\(Int(fraction * 100))%")
                            .font(
                                .system(
                                    size: 19,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(GitMateTheme.accent)
                    } else {
                        Text("计算中")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(GitMateTheme.textSecondary)
                    }
                }

                currentRepositoryProgressView

                HStack(spacing: 12) {
                    statusBox(
                        icon: "arrow.triangle.branch",
                        title: "当前仓库",
                        value: progress.currentRepository ?? "正在准备…"
                    )
                    statusBox(
                        icon: "doc.text",
                        title: "Git 实时状态",
                        value: progress.currentFile ?? "等待文件…",
                        monospaced: true
                    )
                }
            }
            .gitMateCard(padding: 24)

            if let errorMessage = viewModel.state.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitMateTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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
                        ForEach(selectedRepositories) { repository in
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
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        "下载目录",
                        systemImage: "externaldrive.badge.checkmark"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    Text(viewModel.syncDestination?.path ?? "尚未选择")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(GitMateTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button("在 Finder 中显示") {
                    revealSyncDestination()
                }
                .buttonStyle(GitMateButtonStyle(role: .quiet))

                Spacer()
                Text(viewModel.isDownloadPaused ? "下载已暂停" : "正在下载")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GitMateTheme.textTertiary)
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var currentRepositoryProgressView: some View {
        if let fraction = progress.currentRepositoryFraction {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(GitMateTheme.accent)
                .scaleEffect(x: 1, y: 2.4)
                .accessibilityLabel("当前仓库下载进度")
                .accessibilityValue("\(Int(fraction * 100))%")
        } else {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(GitMateTheme.accent)
                .accessibilityLabel("正在读取当前仓库进度")
        }
    }

    private func revealSyncDestination() {
        guard let syncDestination = viewModel.syncDestination else {
            return
        }
        try? FileManager.default.createDirectory(
            at: syncDestination,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([
            syncDestination
        ])
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
        let repositoryIndex = selectedRepositories.firstIndex {
            $0.id == repository.id
        } ?? selectedRepositories.endIndex
        let isCompleted = repositoryIndex < progress.completed

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
            } else if isCompleted && !isCurrent {
                Label("已完成", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(GitMateTheme.success)
            } else if isCurrent {
                HStack(spacing: 7) {
                    if viewModel.isDownloadPaused {
                        Image(systemName: "pause.circle.fill")
                        Text("已暂停")
                    } else {
                        ProgressView().controlSize(.small)
                        Text("下载中")
                    }
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
