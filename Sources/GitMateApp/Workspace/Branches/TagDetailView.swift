import GitMateCore
import SwiftUI

struct TagDetailView: View {
    let tag: GitTag
    @Bindable var viewModel: RepositoryWorkspaceViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    message
                    facts
                    releaseHint
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
                        .fill(Color.purple)
                    Image(systemName: "tag.fill")
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tag.name)
                        .font(.system(size: 16, weight: .bold))
                    Text(
                        tag.kind == .annotated
                            ? "附注标签"
                            : "轻量标签"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(GitMateTheme.textSecondary)
                }
                Spacer()
                statusChip
            }

            HStack(spacing: 10) {
                detailStat(
                    title: "目标提交",
                    value: shortSHA(tag.targetSHA ?? tag.objectSHA)
                )
                detailStat(
                    title: "创建者",
                    value: tag.taggerName ?? "未知"
                )
            }
        }
        .padding(18)
    }

    @ViewBuilder
    private var statusChip: some View {
        switch tag.remoteStatus {
        case .localOnly:
            WorkspaceStatusChip(text: "仅本地", color: GitMateTheme.warning)
        case .remoteOnly:
            WorkspaceStatusChip(text: "仅远端", color: GitMateTheme.textSecondary)
        case .synchronized:
            WorkspaceStatusChip(text: "已同步", color: GitMateTheme.success)
        }
    }

    private func detailStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .lineLimit(1)
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitMateTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("标签说明")
                .font(.system(size: 12, weight: .bold))
            Text(tag.message ?? "该标签没有附注说明。")
                .font(.system(size: 11))
                .foregroundStyle(
                    tag.message == nil
                        ? GitMateTheme.textTertiary
                        : GitMateTheme.textPrimary
                )
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(GitMateTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("标签信息")
                .font(.system(size: 12, weight: .bold))
            fact("对象", shortSHA(tag.objectSHA))
            fact("目标", shortSHA(tag.targetSHA ?? tag.objectSHA))
            fact("类型", tag.kind == .annotated ? "附注标签" : "轻量标签")
            fact(
                "创建时间",
                tag.createdAt?.formatted(date: .abbreviated, time: .shortened)
                    ?? "未知"
            )
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

    private var releaseHint: some View {
        HStack(spacing: 11) {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(GitMateTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("GitHub Release")
                    .font(.system(size: 11, weight: .semibold))
                Text("Release 内容在 GitHub 网页中打开，GitMate 不伪造发布状态。")
                    .font(.system(size: 10))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer()
        }
        .padding(13)
        .background(GitMateTheme.accentSoft.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                Button("推送到 origin") {
                    Task {
                        await viewModel.pushTag(
                            name: tag.name,
                            remote: "origin"
                        )
                    }
                }
                .buttonStyle(
                    GitMateButtonStyle(role: .secondary, fillsWidth: true)
                )
                .disabled(tag.existsRemotely)

                Button("删除标签") {
                    viewModel.requestDeleteTag(
                        name: tag.name,
                        remote: tag.existsRemotely ? "origin" : nil
                    )
                }
                .buttonStyle(
                    GitMateButtonStyle(role: .destructive, fillsWidth: true)
                )
            }

            Button("打开关联 Release") {
                openRelease()
            }
            .buttonStyle(
                GitMateButtonStyle(role: .primary, fillsWidth: true)
            )
        }
        .padding(14)
    }

    private func openRelease() {
        if let releaseURL = tag.releaseURL {
            openURL(releaseURL)
            return
        }
        let url = viewModel.context.account.serverURL
            .appending(path: viewModel.context.repository.fullName)
            .appending(path: "releases")
            .appending(path: "tag")
            .appending(path: tag.name)
        openURL(url)
    }
}
