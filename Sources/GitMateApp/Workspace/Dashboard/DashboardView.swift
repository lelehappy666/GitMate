import GitMateCore
import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: DashboardViewModel
    let showAllRepositories: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                accountHeader

                if viewModel.state.connectivity == .offline {
                    offlineBanner
                } else if case let .rateLimited(resetAt) = viewModel.state.connectivity {
                    rateLimitBanner(resetAt: resetAt)
                }

                focusCard
                    .accessibilityIdentifier("workspace.dashboard.focus")

                metricGrid

                if !viewModel.state.panelErrors.isEmpty {
                    panelErrorCard
                }

                activityCard
                    .accessibilityIdentifier("workspace.dashboard.activity")
            }
            .frame(maxWidth: GitMateTheme.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .background(GitMateTheme.canvas)
        .task {
            await viewModel.load()
        }
    }

    private var accountHeader: some View {
        HStack(spacing: 14) {
            GitMateAvatar(url: viewModel.state.account.avatarURL, size: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text("全局工作台")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                Text(accountDescription)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 20)

            loadStatus
        }
    }

    private var accountDescription: String {
        let accountName = viewModel.state.account.displayName
            ?? viewModel.state.account.login
        return "\(accountName) · \(viewModel.state.account.serverDisplayName)"
    }

    @ViewBuilder
    private var loadStatus: some View {
        switch viewModel.state.loadPhase {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在汇总工作区")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(GitMateTheme.textSecondary)
        case .loaded:
            Label("状态已更新", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GitMateTheme.success)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GitMateTheme.danger)
                .lineLimit(2)
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GitMateTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("当前处于离线状态")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                Text("本地仓库数据仍可使用，在线摘要可能不是最新状态。")
                    .font(.system(size: 13))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
        .background(GitMateTheme.warning.opacity(0.11))
        .clipShape(RoundedRectangle(cornerRadius: GitMateTheme.compactCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: GitMateTheme.compactCornerRadius)
                .stroke(GitMateTheme.warning.opacity(0.45), lineWidth: 1)
        }
        .accessibilityIdentifier("workspace.dashboard.offline")
    }

    private func rateLimitBanner(resetAt: Date) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GitMateTheme.warning)
            Text("GitHub 请求暂时受限，预计 \(resetAt.formatted(date: .omitted, time: .shortened)) 后恢复。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GitMateTheme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(GitMateTheme.warning.opacity(0.11))
        .clipShape(RoundedRectangle(cornerRadius: GitMateTheme.compactCornerRadius))
    }

    private var focusCard: some View {
        HStack(alignment: .center, spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(focusForeground.opacity(0.13))
                Image(systemName: focusSymbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(focusForeground)
            }
            .frame(width: 66, height: 66)

            VStack(alignment: .leading, spacing: 7) {
                Text("今日焦点")
                    .font(.system(size: 12, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(focusSecondaryForeground)
                Text(viewModel.state.focus.title)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(focusForeground)
                Text(viewModel.state.focus.message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(focusSecondaryForeground)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            if let itemCount = viewModel.state.focus.itemCount {
                VStack(spacing: 1) {
                    Text(itemCount, format: .number)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("待关注")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(focusForeground)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 24)
        .frame(minHeight: 142)
        .background(
            LinearGradient(
                colors: [
                    focusColor,
                    focusColor.opacity(0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: GitMateTheme.cornerRadius))
        .shadow(color: focusColor.opacity(0.22), radius: 18, y: 9)
    }

    private var metricGrid: some View {
        HStack(alignment: .top, spacing: 14) {
            repositoryHealthCard
            onlineSummaryCard
            localStatusCard
        }
    }

    private var repositoryHealthCard: some View {
        dashboardMetricCard(
            title: "仓库健康",
            symbol: "checkmark.shield",
            value: "\(viewModel.state.healthyRepositoryCount) / \(viewModel.state.repositoryCount)",
            detail: viewModel.state.syncFailureCount == 0
                ? "本地仓库状态正常"
                : "\(viewModel.state.syncFailureCount) 个仓库需要重新同步"
        ) {
            Button(action: showAllRepositories) {
                HStack(spacing: 5) {
                    Text("全部仓库")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GitMateTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开全部仓库")
        }
        .accessibilityIdentifier("workspace.dashboard.repositories")
    }

    private var onlineSummaryCard: some View {
        dashboardMetricCard(
            title: "在线摘要",
            symbol: "network",
            value: "\(viewModel.state.openIssueCount) Issue",
            detail: "\(viewModel.state.openPullRequestCount) PR · \(viewModel.state.failedWorkflowCount) Actions 失败"
        ) {
            Text("详情将在后续阶段开放")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
    }

    private var localStatusCard: some View {
        dashboardMetricCard(
            title: "本地状态",
            symbol: "externaldrive",
            value: "\(viewModel.state.localChangeCount) 项改动",
            detail: localStatusDetail
        ) {
            Text("已汇总暂存、未暂存、未跟踪与冲突")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
                .lineLimit(2)
        }
    }

    private var localStatusDetail: String {
        if viewModel.state.localChangeCount == 0 {
            return "工作区没有未提交改动"
        }
        return "分布在 \(repositoriesWithLocalChanges) 个仓库"
    }

    private var repositoriesWithLocalChanges: Int {
        viewModel.state.repositorySummaries.filter {
            $0.localChangeCount > 0
        }.count
    }

    private func dashboardMetricCard<Footer: View>(
        title: String,
        symbol: String,
        value: String,
        detail: String,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(GitMateTheme.textSecondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(GitMateTheme.textPrimary)
            Text(detail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
                .lineLimit(2)
                .frame(minHeight: 32, alignment: .topLeading)
            Divider()
            footer()
                .frame(minHeight: 30, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gitMateCard(padding: 17)
    }

    private var panelErrorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("部分数据暂不可用", systemImage: "exclamationmark.circle")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(GitMateTheme.textPrimary)

            ForEach(Array(viewModel.state.panelErrors.enumerated()), id: \.offset) { _, error in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(GitMateTheme.warning)
                        .frame(width: 6, height: 6)
                    Text(error.message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gitMateCard(padding: 17)
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("跨仓库最近活动")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                Spacer()
                Text("最近 \(viewModel.state.activities.count) 条")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }

            if viewModel.state.activities.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 20))
                        .foregroundStyle(GitMateTheme.accent)
                    Text("还没有可展示的本地提交活动。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.state.activities) { activity in
                        activityRow(activity)
                        if activity.id != viewModel.state.activities.last?.id {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
            }
        }
        .gitMateCard(padding: 18)
    }

    private func activityRow(_ activity: WorkspaceActivity) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GitMateTheme.accent)
                .frame(width: 30, height: 30)
                .background(GitMateTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(activity.commit.subject)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                    .lineLimit(1)
                Text("\(activity.repositoryFullName) · \(activity.commit.authorName)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(activity.commit.shortHash)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(GitMateTheme.textPrimary)
                Text(activity.commit.authoredAt, style: .relative)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
        }
        .padding(.vertical, 9)
    }

    private var focusSymbol: String {
        switch viewModel.state.focus.kind {
        case .authorizationRequired:
            "key.horizontal"
        case .syncFailure:
            "arrow.triangle.2.circlepath.circle"
        case .failedWorkflow:
            "bolt.trianglebadge.exclamationmark"
        case .localChanges:
            "pencil.and.list.clipboard"
        case .pendingPullRequest:
            "arrow.triangle.pull"
        case .recentActivity:
            "clock.arrow.circlepath"
        case .neutral:
            "checkmark.circle"
        }
    }

    private var focusColor: Color {
        switch viewModel.state.focus.kind {
        case .authorizationRequired, .syncFailure:
            GitMateTheme.danger
        case .failedWorkflow:
            GitMateTheme.warning
        case .localChanges, .pendingPullRequest, .recentActivity:
            GitMateTheme.accent
        case .neutral:
            GitMateTheme.success
        }
    }

    private var focusForeground: Color {
        switch viewModel.state.focus.kind {
        case .failedWorkflow, .neutral:
            GitMateTheme.textPrimary
        case .authorizationRequired,
             .syncFailure,
             .localChanges,
             .pendingPullRequest,
             .recentActivity:
            .white
        }
    }

    private var focusSecondaryForeground: Color {
        switch viewModel.state.focus.kind {
        case .failedWorkflow, .neutral:
            GitMateTheme.textPrimary
        case .authorizationRequired,
             .syncFailure,
             .localChanges,
             .pendingPullRequest,
             .recentActivity:
            Color.white.opacity(0.94)
        }
    }
}
