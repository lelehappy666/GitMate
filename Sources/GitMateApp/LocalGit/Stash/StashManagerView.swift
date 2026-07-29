import GitMateCore
import SwiftUI

struct StashManagerView: View {
    @Bindable var viewModel: StashViewModel
    let service: GitStashService
    let repositoryURL: URL
    var onShowConflicts: () -> Void = {}

    @State private var pendingConfirmation: PendingStashAction?

    var body: some View {
        HSplitView {
            listPanel
                .frame(minWidth: 330, idealWidth: 380)
            previewPanel
                .frame(minWidth: 480)
        }
        .background(.white)
        .accessibilityIdentifier("localGit.stash")
        .task { await viewModel.refresh() }
        .onChange(of: viewModel.shouldShowConflicts) {
            guard viewModel.shouldShowConflicts else {
                return
            }
            onShowConflicts()
            viewModel.consumeConflictRoute()
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: {
                    if !$0 {
                        pendingConfirmation = nil
                    }
                }
            )
        ) {
            Button(
                confirmationButtonTitle,
                role: pendingConfirmation == .drop ? .destructive : nil
            ) {
                runConfirmedAction()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var listPanel: some View {
        VStack(spacing: 0) {
            createPanel
            Divider()
            HStack {
                Text("已保存现场")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(viewModel.entries.count)")
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.entries) { entry in
                        stashRow(entry)
                    }
                }
                .padding(12)
            }

            if let error = viewModel.error {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GitMateTheme.danger)
                    .padding(12)
            }
        }
        .background(.white)
    }

    private var createPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("保存当前现场")
                .font(.system(size: 17, weight: .bold))
            TextField("说明（可选）", text: $viewModel.message)
                .textFieldStyle(.roundedBorder)
            Toggle("包含未跟踪文件", isOn: $viewModel.includeUntracked)
                .toggleStyle(.checkbox)
                .font(.system(size: 11, weight: .medium))
            Button {
                Task { await viewModel.create() }
            } label: {
                Text("创建 Stash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(GitMateTheme.accent)
            .disabled(viewModel.isMutating)
        }
        .padding(16)
        .background(GitMateTheme.panel.opacity(0.65))
    }

    private func stashRow(_ entry: GitStashEntry) -> some View {
        Button {
            Task { await viewModel.select(entry.id) }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label(
                        entry.baseBranch ?? "未知分支",
                        systemImage: "arrow.triangle.branch"
                    )
                    Text("\(entry.fileCount) 个文件")
                    if let createdAt = entry.createdAt {
                        Text(createdAt, style: .relative)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                entry.id == viewModel.selectedID
                    ? GitMateTheme.accentSoft
                    : .white
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: GitMateTheme.compactCornerRadius
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: GitMateTheme.compactCornerRadius
                )
                .stroke(
                    entry.id == viewModel.selectedID
                        ? GitMateTheme.accent
                        : GitMateTheme.border,
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var previewPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text(viewModel.selectedID?.rawValue ?? "Stash 预览")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button("Apply") {
                    Task { await viewModel.applySelected() }
                }
                Button("Pop") {
                    pendingConfirmation = .pop
                }
                Button("删除", role: .destructive) {
                    pendingConfirmation = .drop
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .disabled(viewModel.selectedID == nil || viewModel.isMutating)

            Divider()

            if let preview = viewModel.preview {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(spacing: 12) {
                        ForEach(preview.hunks) { hunk in
                            DiffHunkView(hunk: hunk)
                                .frame(minWidth: 620)
                        }
                    }
                    .padding(14)
                }
                .background(GitMateTheme.panel.opacity(0.4))
            } else {
                ContentUnavailableView(
                    "选择一个 Stash 查看差异",
                    systemImage: "tray.full"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.white)
    }

    private var confirmationTitle: String {
        pendingConfirmation == .drop
            ? "确定永久删除这个 Stash？"
            : "确定应用并移除这个 Stash？"
    }

    private var confirmationButtonTitle: String {
        pendingConfirmation == .drop ? "删除 Stash" : "应用并移除"
    }

    private func runConfirmedAction() {
        guard let selectedID = viewModel.selectedID else {
            return
        }
        let action = pendingConfirmation
        pendingConfirmation = nil
        Task {
            if action == .drop {
                await viewModel.dropSelected(
                    confirmation: service.dropConfirmation(
                        repositoryURL: repositoryURL,
                        id: selectedID
                    )
                )
            } else {
                await viewModel.popSelected(
                    confirmation: service.popConfirmation(
                        repositoryURL: repositoryURL,
                        id: selectedID
                    )
                )
            }
        }
    }
}

private enum PendingStashAction {
    case pop
    case drop
}
