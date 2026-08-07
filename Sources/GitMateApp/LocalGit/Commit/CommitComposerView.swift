import GitMateCore
import SwiftUI

struct CommitComposerView: View {
    @Bindable var workingTreeViewModel: WorkingTreeViewModel
    @Bindable var diffViewModel: FileDiffViewModel
    @Bindable var commitViewModel: CommitComposerViewModel

    var body: some View {
        HSplitView {
            stagedFiles
                .frame(minWidth: 200, idealWidth: 230)
            FileDiffView(viewModel: diffViewModel)
                .frame(minWidth: 300)
            composer
                .frame(minWidth: 260, idealWidth: 290)
        }
        .background(.white)
        .accessibilityIdentifier("localGit.commit")
        .task {
            await commitViewModel.loadContext()
            await workingTreeViewModel.refresh()
        }
    }

    private var stagedFiles: some View {
        VStack(spacing: 0) {
            HStack {
                Text("已暂存文件")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(stagedFileValues.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 54)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(stagedFileValues) { file in
                        WorkingTreeFileRow(
                            file: file,
                            isSelected: workingTreeViewModel.selection
                                .contains(file.id),
                            onToggle: {
                                workingTreeViewModel.toggleSelection(file.id)
                            },
                            onOpenDiff: {
                                Task {
                                    await diffViewModel.select(
                                        path: file.path,
                                        source: .index
                                    )
                                }
                            }
                        )
                    }
                }
            }

            Divider()

            Button("取消暂存所选") {
                Task { await workingTreeViewModel.unstageSelection() }
            }
            .disabled(workingTreeViewModel.selection.isEmpty)
            .padding(12)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("创建提交")
                .font(.system(size: 18, weight: .bold))

            contextCard

            VStack(alignment: .leading, spacing: 7) {
                Text("标题")
                    .font(.system(size: 11, weight: .semibold))
                TextField("简要说明本次变更", text: $commitViewModel.title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("localGit.commit.title")
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("说明")
                    .font(.system(size: 11, weight: .semibold))
                TextEditor(text: $commitViewModel.body)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(GitMateTheme.panel)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: GitMateTheme.compactCornerRadius
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: GitMateTheme.compactCornerRadius
                        )
                        .stroke(GitMateTheme.border, lineWidth: 1)
                    }
                    .accessibilityIdentifier("localGit.commit.body")
            }
            .frame(maxHeight: .infinity)

            if let error = commitViewModel.error {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GitMateTheme.danger)
            }

            if let result = commitViewModel.result {
                Label(
                    "已创建 \(result.shortOID)",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GitMateTheme.success)
            }

            Button {
                Task {
                    await commitViewModel.commit()
                    if commitViewModel.result != nil {
                        await workingTreeViewModel.refresh()
                    }
                }
            } label: {
                HStack {
                    if commitViewModel.isCommitting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("创建提交")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(GitMateTheme.accent)
            .disabled(
                commitViewModel.isCommitting
                    || commitViewModel.title
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
            )
            .accessibilityIdentifier("localGit.commit.submit")
        }
        .padding(18)
        .background(.white)
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(
                identityText,
                systemImage: "person.crop.circle"
            )
            .accessibilityIdentifier("localGit.commit.identity")

            Label(
                signingText,
                systemImage: "signature"
            )
            .accessibilityIdentifier("localGit.commit.signing")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(GitMateTheme.textSecondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitMateTheme.panel)
        .clipShape(
            RoundedRectangle(
                cornerRadius: GitMateTheme.compactCornerRadius
            )
        )
    }

    private var stagedFileValues: [WorkingTreeFile] {
        workingTreeViewModel.visibleFiles.filter { $0.category == .staged }
    }

    private var identityText: String {
        guard let identity = commitViewModel.identity else {
            return "正在读取提交身份"
        }
        return "\(identity.name ?? "未配置姓名") · \(identity.email ?? "未配置邮箱")"
    }

    private var signingText: String {
        switch commitViewModel.signingState {
        case .disabled:
            return "提交签名未启用"
        case let .configured(format):
            return "沿用 Git 签名配置\(format.map { " · \($0)" } ?? "")"
        case let .misconfigured(reason):
            return reason
        }
    }
}
