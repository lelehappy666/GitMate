import GitMateCore
import SwiftUI

struct BranchDetailView: View {
    let branch: GitBranch
    @Bindable var viewModel: RepositoryWorkspaceViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let workingTree = viewModel.state.workingTreeStatus,
                       !workingTree.isClean {
                        localWarning(workingTree)
                    }
                    facts
                    protection
                }
                .padding(18)
            }

            Divider()
            actions
        }
        .workspacePanel()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(GitMateTheme.accent)
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(branch.name)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                    Text(branchLocationText)
                        .font(.system(size: 10))
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
                Spacer()
                if branch.isProtected {
                    WorkspaceStatusChip(
                        text: "受保护",
                        color: GitMateTheme.success
                    )
                }
            }

            HStack(spacing: 10) {
                statistic(
                    value: aheadCount,
                    title: "领先",
                    color: GitMateTheme.accent
                )
                statistic(
                    value: behindCount,
                    title: "落后",
                    color: GitMateTheme.warning
                )
                statistic(
                    value: viewModel.state.workingTreeStatus?.changedFiles.count ?? 0,
                    title: "变更文件",
                    color: GitMateTheme.textPrimary
                )
            }
        }
        .padding(18)
    }

    private func statistic(
        value: Int,
        title: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitMateTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func localWarning(_ status: WorkingTreeStatus) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(GitMateTheme.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("有 \(status.changedFiles.count) 个未提交文件")
                    .font(.system(size: 12, weight: .semibold))
                Text("签出或合并前，请先在编辑器中处理这些更改。")
                    .font(.system(size: 10))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitMateTheme.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分支信息")
                .font(.system(size: 12, weight: .bold))
            fact("本地提交", shortSHA(branch.localSHA))
            fact("远端提交", shortSHA(branch.remoteSHA))
            fact("上游分支", branch.upstreamName ?? "尚未设置")
            fact("最近作者", branch.authorName ?? "未知")
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(GitMateTheme.textSecondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .textSelection(.enabled)
        }
        .font(.system(size: 11))
        .padding(.vertical, 3)
    }

    private var protection: some View {
        HStack(spacing: 11) {
            Image(systemName: branch.isProtected ? "lock.shield.fill" : "lock.open")
                .foregroundStyle(
                    branch.isProtected
                        ? GitMateTheme.success
                        : GitMateTheme.textTertiary
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(branch.isProtected ? "已启用 GitHub 保护" : "没有分支保护")
                    .font(.system(size: 11, weight: .semibold))
                Text(
                    branch.isProtected
                        ? "切换到“分支规则”查看 Ruleset 和审查要求。"
                        : "可以为重要分支添加合并和状态检查限制。"
                )
                .font(.system(size: 10))
                .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer()
        }
        .padding(13)
        .background(GitMateTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                Button("签出分支") {
                    Task {
                        await viewModel.checkoutBranch(name: branch.name)
                    }
                }
                .buttonStyle(
                    GitMateButtonStyle(role: .secondary, fillsWidth: true)
                )
                .disabled(branch.localSHA == nil)
                .accessibilityIdentifier("workspace.branches.checkout")

                Button("推送") {
                    Task {
                        await viewModel.pushBranch(
                            name: branch.name,
                            remote: "origin"
                        )
                    }
                }
                .buttonStyle(
                    GitMateButtonStyle(role: .secondary, fillsWidth: true)
                )
                .disabled(branch.localSHA == nil)
                .accessibilityIdentifier("workspace.branches.push")
            }

            HStack(spacing: 9) {
                Button("删除分支") {
                    if branch.localSHA != nil {
                        viewModel.requestDeleteLocalBranch(
                            name: branch.name,
                            force: false
                        )
                    } else {
                        viewModel.requestDeleteRemoteBranch(
                            remote: "origin",
                            name: branch.name
                        )
                    }
                }
                .buttonStyle(
                    GitMateButtonStyle(role: .destructive, fillsWidth: true)
                )
                .accessibilityIdentifier("workspace.branches.delete")

                Button("创建拉取请求") {
                    openPullRequest()
                }
                .buttonStyle(
                    GitMateButtonStyle(role: .primary, fillsWidth: true)
                )
            }
        }
        .padding(14)
    }

    private var branchLocationText: String {
        switch branch.location {
        case .local:
            "本地分支 · 尚未发布"
        case .remote:
            "远端分支 · 尚未签出"
        case .localAndRemote:
            "本地与远端已关联"
        }
    }

    private var aheadCount: Int {
        switch branch.trackingStatus {
        case let .ahead(value), let .diverged(value, _):
            value
        default:
            0
        }
    }

    private var behindCount: Int {
        switch branch.trackingStatus {
        case let .behind(value), let .diverged(_, value):
            value
        default:
            0
        }
    }

    private func openPullRequest() {
        let repository = viewModel.context.repository.fullName
        let base = viewModel.context.account.serverURL
            .appending(path: repository)
            .appending(path: "compare")
        let comparison = "\(viewModel.context.repository.defaultBranch)...\(branch.name)"
        if let url = URL(
            string: base.appending(path: comparison).absoluteString + "?expand=1"
        ) {
            openURL(url)
        }
    }
}
