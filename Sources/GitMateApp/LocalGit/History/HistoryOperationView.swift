import GitMateCore
import SwiftUI

struct HistoryOperationView: View {
    @Bindable var viewModel: HistoryOperationViewModel
    var onShowConflicts: () -> Void = {}
    @State private var showAbortConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.operationState.kind != nil {
                activeOperation
            } else {
                operationComposer
            }
        }
        .background(.white)
        .accessibilityIdentifier("localGit.historyOperation")
        .task { await viewModel.refreshState() }
        .onChange(of: viewModel.shouldShowConflicts) {
            guard viewModel.shouldShowConflicts else {
                return
            }
            onShowConflicts()
            viewModel.consumeConflictRoute()
        }
        .confirmationDialog(
            "确定中止当前 Git 操作？",
            isPresented: $showAbortConfirmation
        ) {
            Button("中止并恢复", role: .destructive) {
                Task { await viewModel.abort() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("合并、变基与拣选")
                    .font(.system(size: 20, weight: .bold))
                Text("先预检影响，再执行历史操作")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 74)
    }

    private var operationComposer: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("操作", selection: $viewModel.mode) {
                    Text("合并").tag(HistoryOperationMode.merge)
                    Text("变基").tag(HistoryOperationMode.rebase)
                    Text("拣选").tag(HistoryOperationMode.cherryPick)
                }
                .pickerStyle(.segmented)

                TextField(sourcePlaceholder, text: $viewModel.source)
                    .textFieldStyle(.roundedBorder)

                Button("运行预检") {
                    Task { await viewModel.runPreflight() }
                }
                .buttonStyle(.borderedProminent)
                .tint(GitMateTheme.accent)

                if let error = viewModel.error {
                    Label(
                        error.message,
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GitMateTheme.danger)
                }
                Spacer()
            }
            .padding(20)
            .frame(minWidth: 300, idealWidth: 340)

            preflightPanel
                .frame(minWidth: 500)
        }
    }

    private var preflightPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("影响预检")
                .font(.system(size: 17, weight: .bold))

            if let preflight = viewModel.preflight {
                HStack(spacing: 12) {
                    metric(
                        value: "\(preflight.commitCount)",
                        label: "提交"
                    )
                    metric(
                        value: "\(preflight.affectedFiles.count)",
                        label: "受影响文件"
                    )
                    metric(
                        value: predictionText(preflight.conflictPrediction),
                        label: "冲突预测"
                    )
                }

                if let blocker = preflight.blocker {
                    Label(
                        blockerText(blocker),
                        systemImage: "exclamationmark.octagon"
                    )
                    .foregroundStyle(GitMateTheme.danger)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(preflight.affectedFiles, id: \.self) { path in
                            Label(path, systemImage: "doc")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("确认并执行") {
                    Task { await viewModel.start() }
                }
                .buttonStyle(.borderedProminent)
                .tint(GitMateTheme.accent)
                .disabled(!preflight.canStart)
            } else {
                ContentUnavailableView(
                    "等待预检",
                    systemImage: "checklist",
                    description: Text("选择操作并填写来源后运行预检。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .background(GitMateTheme.panel.opacity(0.45))
    }

    private var activeOperation: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 42))
                .foregroundStyle(GitMateTheme.accent)
            Text(activeOperationTitle)
                .font(.system(size: 21, weight: .bold))
            Text(
                viewModel.operationState.canContinue
                    ? "冲突已处理，可以继续。"
                    : "仍有冲突需要先解决。"
            )
            .foregroundStyle(GitMateTheme.textSecondary)
            HStack {
                Button("继续") {
                    Task { await viewModel.continueOperation() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.operationState.canContinue)
                Button("中止", role: .destructive) {
                    showAbortConfirmation = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sourcePlaceholder: String {
        viewModel.mode == .cherryPick
            ? "提交哈希，多个用空格或逗号分隔"
            : "分支或提交"
    }

    private var activeOperationTitle: String {
        switch viewModel.operationState.kind {
        case .merge:
            return "合并进行中"
        case .rebase:
            return "变基进行中"
        case .cherryPick:
            return "拣选进行中"
        case nil:
            return ""
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 17, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(
            RoundedRectangle(cornerRadius: GitMateTheme.compactCornerRadius)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: GitMateTheme.compactCornerRadius
            )
            .stroke(GitMateTheme.border, lineWidth: 1)
        }
    }

    private func predictionText(
        _ prediction: GitConflictPrediction
    ) -> String {
        switch prediction {
        case .none:
            return "未发现"
        case .likely:
            return "可能冲突"
        case .unknown:
            return "未知"
        }
    }

    private func blockerText(_ blocker: GitOperationBlocker) -> String {
        switch blocker {
        case .workingTreeNotClean:
            return "工作区有未保存变更，请先创建 Stash。"
        case .anotherOperationInProgress:
            return "已有历史操作正在进行。"
        case .invalidSource:
            return "来源分支或提交无效。"
        case .conflictPredictionUnknown:
            return "当前 Git 无法完成冲突预测。"
        }
    }
}
