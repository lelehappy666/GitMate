import AppKit
import GitMateCore
import SwiftUI

struct RepositorySyncSetupView: View {
    let viewModel: OnboardingViewModel

    private var selectedRepositoryIDs: Set<Int64> {
        viewModel.state.selectedRepositoryIDs
    }

    var body: some View {
        let summary = selectionSummary()

        VStack(spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("选择首次下载仓库")
                        .font(.system(size: 28, weight: .bold))
                    Text("勾选需要保存到本机的仓库；本次只执行 Clone，不会自动上传或下载更新。")
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                summaryMetric(
                    value: "\(viewModel.state.repositories.count)",
                    label: "云端仓库"
                )
                summaryMetric(value: "\(summary.count)", label: "已选择")
                summaryMetric(value: formattedSize(summary.size), label: "预计占用")
            }

            destinationCard

            VStack(spacing: 0) {
                HStack {
                    Text("仓库")
                    Text("已选择 \(summary.count) 个")
                        .foregroundStyle(GitMateTheme.textTertiary)
                    Spacer()
                    Button {
                        Task { await viewModel.refreshRepositories() }
                    } label: {
                        if viewModel.isRefreshingRepositories {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 32, height: 32)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(GitMateTheme.border, lineWidth: 1)
                    }
                    .disabled(viewModel.isRefreshingRepositories)
                    .help("刷新云端仓库")
                    .accessibilityLabel("刷新云端仓库")
                    .accessibilityIdentifier(
                        "onboarding.repository.refresh"
                    )
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GitMateTheme.textSecondary)
                .padding(.horizontal, 18)
                .frame(height: 42)
                .background(GitMateTheme.panel)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.state.repositories) { repository in
                            RepositoryDownloadRow(
                                repository: repository,
                                isSelected: selectedRepositoryIDs.contains(
                                    repository.id
                                ),
                                onSelectionChanged: { isSelected in
                                    viewModel.setRepositorySelected(
                                        repositoryID: repository.id,
                                        isSelected: isSelected
                                    )
                                }
                            )
                            Divider().padding(.leading, 78)
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

            if let errorMessage = viewModel.state.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitMateTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("返回权限说明") {
                    viewModel.returnToPermissionReview()
                }
                .buttonStyle(GitMateButtonStyle(role: .secondary))

                Spacer()

                Text("\(summary.count) 个仓库 · \(formattedSize(summary.size))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)

                Button("跳过首次下载") {
                    viewModel.skipInitialDownload()
                }
                .buttonStyle(GitMateButtonStyle(role: .secondary))
                .accessibilityIdentifier("onboarding.repository.skipClone")

                Button {
                    Task { await viewModel.startSync() }
                } label: {
                    HStack {
                        Text("开始首次下载（Clone）")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(GitMateButtonStyle(role: .primary))
                .disabled(
                    summary.count == 0 || viewModel.syncDestination == nil
                )
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var destinationCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(GitMateTheme.accent)
                .frame(width: 42, height: 42)
                .background(GitMateTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text("仓库存储目录")
                    .font(.system(size: 13, weight: .semibold))
                Text(
                    viewModel.syncDestination?.path
                        ?? "尚未选择；首次下载前必须选择一个本机文件夹"
                )
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(GitMateTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }

            Spacer()

            Button(viewModel.syncDestination == nil ? "选择目录" : "更改目录") {
                chooseSyncDestination()
            }
            .buttonStyle(GitMateButtonStyle(role: .secondary))
            .accessibilityIdentifier("onboarding.repository.destination")
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(GitMateTheme.border, lineWidth: 1)
        }
    }

    private func selectionSummary() -> (count: Int, size: Int64) {
        viewModel.state.repositories.reduce(into: (count: 0, size: 0)) {
            result,
            repository in
            guard selectedRepositoryIDs.contains(repository.id) else {
                return
            }
            result.count += 1
            result.size += Int64(repository.sizeInKilobytes) * 1_024
        }
    }

    private func summaryMetric(value: String, label: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(GitMateTheme.border, lineWidth: 1)
        }
    }

    private func chooseSyncDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择 GitMate 保存仓库的父文件夹"
        panel.directoryURL = viewModel.syncDestination
        if panel.runModal() == .OK, let destination = panel.url {
            viewModel.selectSyncDestination(destination)
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file
        )
    }
}

private struct RepositoryDownloadRow: View {
    let repository: Repository
    let isSelected: Bool
    let onSelectionChanged: (Bool) -> Void

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { isSelected },
                set: { isSelected in
                    onSelectionChanged(isSelected)
                }
            )
        ) {
            HStack(spacing: 13) {
                GitMateAvatar(url: repository.ownerAvatarURL, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(repository.fullName)
                            .font(.system(size: 14, weight: .semibold))
                        Text(repository.isPrivate ? "私有" : "公开")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(GitMateTheme.panel)
                            .clipShape(Capsule())
                    }
                    HStack(spacing: 12) {
                        Label(
                            repository.defaultBranch,
                            systemImage: "arrow.triangle.branch"
                        )
                        Text(
                            ByteCountFormatter.string(
                                fromByteCount: Int64(
                                    repository.sizeInKilobytes
                                ) * 1_024,
                                countStyle: .file
                            )
                        )
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(GitMateTheme.textSecondary)
                }
                Spacer()
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 18)
        .frame(height: 68)
        .accessibilityLabel("\(repository.fullName) 首次下载")
        .accessibilityIdentifier(
            "onboarding.repository.selected.\(repository.id)"
        )
    }
}
