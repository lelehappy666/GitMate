import GitMateCore
import SwiftUI

struct RepositoryOverviewView: View {
    @Bindable var viewModel: RepositoryOverviewViewModel
    let onRoute: (WorkspaceRoute) -> Void
    let onResync: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            repositoryHeader
            Divider()
            bodyContent
        }
        .background(GitMateTheme.canvas)
        .accessibilityIdentifier("workspace.repository.overview")
        .task {
            await viewModel.load()
        }
    }

    private var repositoryHeader: some View {
        HStack(spacing: 14) {
            GitMateAvatar(
                url: viewModel.state.repository.ownerAvatarURL,
                size: 46
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(viewModel.state.repository.fullName)
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(GitMateTheme.textPrimary)
                        .lineLimit(1)

                    visibilityBadge
                }

                Text(headerDescription)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 20)

            if showsResyncAction {
                Button(action: onResync) {
                    Label("重新同步", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(GitMateTheme.accent)
                .accessibilityIdentifier("workspace.repository.resync")
            } else {
                Label(
                    "本地可用",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(GitMateTheme.success)
            }
        }
        .padding(.horizontal, 26)
        .frame(height: 86)
        .background(.white)
    }

    private var visibilityBadge: some View {
        Text(viewModel.state.repository.isPrivate ? "私有" : "公开")
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(GitMateTheme.textPrimary)
            .padding(.horizontal, 8)
            .frame(height: 23)
            .background(GitMateTheme.panel)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(GitMateTheme.border, lineWidth: 1)
            }
    }

    private var headerDescription: String {
        [
            viewModel.state.onlineSummary?.primaryLanguage ?? "未知语言",
            viewModel.state.repository.defaultBranch,
            repositorySize(viewModel.state.repository.sizeInKilobytes)
        ].joined(separator: " · ")
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch viewModel.state.loadPhase {
        case .idle, .loading:
            loadingState
        case let .failed(message):
            errorState(message: message)
        case .loaded:
            loadedContent
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("正在读取仓库总览")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GitMateTheme.textPrimary)
            Text("本地信息与 GitHub 摘要会合并显示。")
                .font(.system(size: 13))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(GitMateTheme.danger)
            Text("仓库总览无法加载")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(GitMateTheme.textPrimary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(GitMateTheme.textSecondary)

            if let action = viewModel.state.retryAction {
                Button {
                    Task {
                        await viewModel.load()
                    }
                } label: {
                    Label(action.title, systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(GitMateTheme.accent)
                .accessibilityLabel(action.accessibilityLabel)
                .accessibilityIdentifier(
                    action.accessibilityIdentifier
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if viewModel.state.needsResync {
                    resyncBanner
                }
                if viewModel.state.connectivity == .offline {
                    offlineBanner
                }

                statusGrid

                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 18) {
                        recentCommitsCard
                        readmeCard
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 18) {
                        onlineCard
                        quickRoutesCard
                        remoteCard
                    }
                    .frame(width: 290)
                }

                if !viewModel.state.panelErrors.isEmpty {
                    panelErrorsCard
                }
            }
            .frame(maxWidth: GitMateTheme.contentMaxWidth, alignment: .topLeading)
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
        }
        .scrollIndicators(.visible)
    }

    private var resyncBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(GitMateTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(resyncTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                Text("远程元数据和 README 仍然可用，重新同步后可恢复本地文件与提交浏览。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer(minLength: 12)
            Button("重新同步", action: onResync)
                .buttonStyle(.bordered)
                .accessibilityIdentifier(
                    "workspace.repository.resync.banner"
                )
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 66)
        .background(GitMateTheme.warning.opacity(0.10))
        .clipShape(
            RoundedRectangle(
                cornerRadius: GitMateTheme.compactCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: GitMateTheme.compactCornerRadius,
                style: .continuous
            )
            .stroke(GitMateTheme.warning.opacity(0.42), lineWidth: 1)
        }
    }

    private var offlineBanner: some View {
        Label(
            "当前离线：本地内容继续可用，在线摘要可能不是最新状态。",
            systemImage: "wifi.slash"
        )
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(GitMateTheme.textPrimary)
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(GitMateTheme.panel)
        .clipShape(
            RoundedRectangle(
                cornerRadius: GitMateTheme.compactCornerRadius,
                style: .continuous
            )
        )
    }

    private var statusGrid: some View {
        HStack(spacing: 12) {
            overviewMetric(
                title: "本地状态",
                value: localStatusTitle,
                detail: branchDetail,
                symbol: "externaldrive",
                color: viewModel.state.needsResync
                    ? GitMateTheme.warning
                    : GitMateTheme.success
            )
            overviewMetric(
                title: "未提交改动",
                value: "\(viewModel.state.uncommittedChangeCount)",
                detail: changeDetail,
                symbol: "pencil.and.list.clipboard",
                color: viewModel.state.uncommittedChangeCount == 0
                    ? GitMateTheme.success
                    : GitMateTheme.warning
            )
            overviewMetric(
                title: "最后同步",
                value: lastSynchronizationTitle,
                detail: "\(byteSize(viewModel.state.localSizeInBytes)) · \(lastInspectionDetail)",
                symbol: "clock.arrow.circlepath",
                color: GitMateTheme.accent
            )
        }
    }

    private func overviewMetric(
        title: String,
        value: String,
        detail: String,
        symbol: String,
        color: Color
    ) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
                .fill(color.opacity(0.12))
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(GitMateTheme.textSecondary)
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(GitMateTheme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 82)
        .background(.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: GitMateTheme.compactCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: GitMateTheme.compactCornerRadius,
                style: .continuous
            )
            .stroke(GitMateTheme.border, lineWidth: 1)
        }
    }

    private var recentCommitsCard: some View {
        overviewCard(title: "最近提交", symbol: "clock.arrow.circlepath") {
            if viewModel.state.recentCommits.isEmpty {
                emptyRow(
                    symbol: "clock",
                    title: viewModel.state.needsResync
                        ? "重新同步后可读取本地提交"
                        : "暂无提交记录"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.state.recentCommits) { commit in
                        HStack(spacing: 11) {
                            GitMateAvatar(
                                url: nil,
                                size: 30
                            )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(commit.subject)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(GitMateTheme.textPrimary)
                                    .lineLimit(1)
                                Text(
                                    "\(commit.authorName) · \(commit.shortHash) · \(commit.authoredAt.formatted(.relative(presentation: .named)))"
                                )
                                .font(.system(size: 10.5))
                                .foregroundStyle(GitMateTheme.textTertiary)
                                .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)

                        if commit.id != viewModel.state.recentCommits.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var readmeCard: some View {
        overviewCard(title: "README 简介", symbol: "text.document") {
            if let document = viewModel.state.readmePreview {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(
                        Array(document.blocks.prefix(5).enumerated()),
                        id: \.offset
                    ) { _, block in
                        READMEBlockView(block: block)
                    }

                    Button {
                        onRoute(
                            .readme(
                                repositoryID: viewModel.state.repository.id
                            )
                        )
                    } label: {
                        Label("查看完整 README", systemImage: "arrow.right")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(GitMateTheme.accent)
                }
            } else {
                emptyRow(
                    symbol: "doc",
                    title: "暂无可显示的 README 内容"
                )
            }
        }
    }

    private var onlineCard: some View {
        overviewCard(title: "GitHub 摘要", symbol: "network") {
            if let summary = viewModel.state.onlineSummary {
                VStack(spacing: 10) {
                    onlineMetric(
                        title: "Issue",
                        value: summary.openIssueCount,
                        symbol: "record.circle"
                    )
                    onlineMetric(
                        title: "Pull Request",
                        value: summary.openPullRequestCount,
                        symbol: "arrow.triangle.pull"
                    )
                    onlineMetric(
                        title: "Actions 失败",
                        value: summary.failedWorkflowCount,
                        symbol: "bolt.trianglebadge.exclamationmark"
                    )
                }
            } else {
                emptyRow(
                    symbol: "wifi.slash",
                    title: "在线摘要暂不可用"
                )
            }
        }
    }

    private func onlineMetric(
        title: String,
        value: Int,
        symbol: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(GitMateTheme.accent)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
            Spacer(minLength: 8)
            Text(value, format: .number)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(GitMateTheme.textPrimary)
        }
    }

    private var quickRoutesCard: some View {
        overviewCard(title: "仓库浏览", symbol: "rectangle.3.group") {
            VStack(spacing: 7) {
                routeButton(
                    title: "README",
                    symbol: "text.document",
                    route: .readme(repositoryID: viewModel.state.repository.id)
                )
                routeButton(
                    title: "文件与提交",
                    symbol: "folder",
                    route: .filesAndCommits(
                        repositoryID: viewModel.state.repository.id
                    )
                )
                routeButton(
                    title: "提交图",
                    symbol: "point.3.connected.trianglepath.dotted",
                    route: .commitGraph(
                        repositoryID: viewModel.state.repository.id
                    )
                )
            }
        }
    }

    private func routeButton(
        title: String,
        symbol: String,
        route: WorkspaceRoute
    ) -> some View {
        Button {
            onRoute(route)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .frame(width: 18)
                Text(title)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(GitMateTheme.textPrimary)
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(GitMateTheme.panel)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 8,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var remoteCard: some View {
        overviewCard(title: "远程地址", symbol: "link") {
            Link(destination: viewModel.state.repository.cloneURL) {
                HStack(spacing: 6) {
                    Text(viewModel.state.repository.cloneURL.absoluteString)
                        .lineLimit(2)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(GitMateTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityHint("在浏览器中打开仓库远程地址")
        }
    }

    private var panelErrorsCard: some View {
        overviewCard(
            title: "部分信息暂不可用",
            symbol: "exclamationmark.triangle"
        ) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(
                    Array(viewModel.state.panelErrors.enumerated()),
                    id: \.offset
                ) { _, error in
                    Label(error.message, systemImage: "circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
            }
        }
    }

    private func overviewCard<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(GitMateTheme.textPrimary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: GitMateTheme.cornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: GitMateTheme.cornerRadius,
                style: .continuous
            )
            .stroke(GitMateTheme.border, lineWidth: 1)
        }
    }

    private func emptyRow(
        symbol: String,
        title: String
    ) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(GitMateTheme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
    }

    private var resyncTitle: String {
        switch viewModel.state.localAvailability {
        case .available:
            "本地仓库可用"
        case .missing:
            "本地仓库尚未同步或已被移动"
        case .damaged:
            "本地 Git 数据不可用"
        }
    }

    private var showsResyncAction: Bool {
        viewModel.state.loadPhase == .loaded
            && viewModel.state.needsResync
    }

    private var localStatusTitle: String {
        switch viewModel.state.localAvailability {
        case .available:
            "已同步"
        case .missing:
            "尚未同步"
        case .damaged:
            "需要修复"
        }
    }

    private var branchDetail: String {
        viewModel.state.localStatus?.branch.map { "分支 \($0)" }
            ?? viewModel.state.repository.defaultBranch
    }

    private var changeDetail: String {
        guard let status = viewModel.state.localStatus else {
            return "等待本地仓库"
        }
        return "暂存 \(status.stagedCount) · 未暂存 \(status.unstagedCount)"
    }

    private var lastInspectionDetail: String {
        viewModel.state.lastInspectedAt.map {
            "最近检查于 \($0.formatted(.relative(presentation: .named)))"
        } ?? "暂无检查记录"
    }

    private var lastSynchronizationTitle: String {
        viewModel.state.lastSynchronizedAt.map {
            "同步于 \($0.formatted(.relative(presentation: .named)))"
        } ?? "暂无同步记录"
    }

    private func repositorySize(_ kilobytes: Int) -> String {
        byteSize(Int64(kilobytes) * 1_024)
    }

    private func byteSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file
        )
    }
}
