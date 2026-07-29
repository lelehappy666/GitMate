import AppKit
import GitMateCore
import SwiftUI

struct RepositorySyncSetupView: View {
    let viewModel: OnboardingViewModel

    private var syncModes: [Int64: RepositorySyncMode] {
        Dictionary(
            uniqueKeysWithValues: viewModel.state.preferences.map {
                ($0.repositoryID, $0.mode)
            }
        )
    }

    var body: some View {
        let modes = syncModes
        let summary = selectionSummary(modes: modes)

        VStack(spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("选择首次同步方式")
                        .font(.system(size: 28, weight: .bold))
                    Text("手动会立即同步一次；自动持续更新尚未开发，当前仅完成首次同步。")
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
                Spacer()
                Menu {
                    batchButton("全部不同步", mode: .never)
                    batchButton("全部手动同步", mode: .manual)
                    batchButton("全部自动（预留）", mode: .automatic)
                } label: {
                    Label("批量设置", systemImage: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: 12) {
                summaryMetric(
                    value: "\(viewModel.state.repositories.count)",
                    label: "仓库总数"
                )
                summaryMetric(value: "\(summary.count)", label: "本次同步")
                summaryMetric(value: formattedSize(summary.size), label: "预计占用")
            }

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
                            ?? "尚未选择；开始同步前必须选择一个本机文件夹"
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

            VStack(spacing: 0) {
                HStack {
                    Text("仓库")
                    Spacer()
                    Text("同步方式")
                        .frame(width: 300)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GitMateTheme.textSecondary)
                .padding(.horizontal, 18)
                .frame(height: 38)
                .background(GitMateTheme.panel)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.state.repositories) { repository in
                            RepositorySyncRow(
                                repository: repository,
                                mode: modes[repository.id] ?? .never,
                                onModeChanged: { mode in
                                    viewModel.updateSyncMode(
                                        repositoryID: repository.id,
                                        mode: mode
                                    )
                                }
                            )
                            Divider().padding(.leading, 64)
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

                Button {
                    Task { await viewModel.startSync() }
                } label: {
                    HStack {
                        Text(summary.count == 0 ? "跳过首次同步" : "开始首次同步")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(GitMateButtonStyle(role: .primary))
                .disabled(
                    summary.count > 0 && viewModel.syncDestination == nil
                )
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func selectionSummary(
        modes: [Int64: RepositorySyncMode]
    ) -> (count: Int, size: Int64) {
        viewModel.state.repositories.reduce(into: (count: 0, size: 0)) {
            result,
            repository in
            guard (modes[repository.id] ?? .never) != .never else { return }
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

    private func batchButton(
        _ title: String,
        mode: RepositorySyncMode
    ) -> some View {
        Button(title) {
            viewModel.setSyncModeForAllRepositories(mode)
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

private struct RepositorySyncRow: View {
    let repository: Repository
    let mode: RepositorySyncMode
    let onModeChanged: (RepositorySyncMode) -> Void

    var body: some View {
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
                            fromByteCount: Int64(repository.sizeInKilobytes) * 1_024,
                            countStyle: .file
                        )
                    )
                }
                .font(.system(size: 11))
                .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer()
            Picker(
                "同步方式",
                selection: Binding(
                    get: { mode },
                    set: { newMode in
                        onModeChanged(newMode)
                    }
                )
            ) {
                Text("不同步").tag(RepositorySyncMode.never)
                Text("手动").tag(RepositorySyncMode.manual)
                Text("自动（预留）").tag(RepositorySyncMode.automatic)
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            .accessibilityLabel("\(repository.fullName) 同步方式")
            .accessibilityIdentifier(
                "onboarding.repository.syncMode.\(repository.id)"
            )
        }
        .padding(.horizontal, 18)
        .frame(height: 68)
    }
}
