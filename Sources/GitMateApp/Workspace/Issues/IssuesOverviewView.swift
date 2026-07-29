import GitMateCore
import SwiftUI

struct IssuesOverviewView: View {
    @Bindable var viewModel: RepositoryWorkspaceViewModel
    @State private var searchText = ""
    @State private var stateFilter = "all"
    @State private var sort = IssueSort.updated
    @State private var direction = IssueDirection.descending
    @State private var labelFilter = ""
    @State private var savedViewName = ""
    @State private var showsSaveView = false

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            summary

            HStack(alignment: .top, spacing: 12) {
                filterPanel
                    .frame(width: 224)
                issueList
            }
        }
        .sheet(isPresented: $showsSaveView) {
            saveViewSheet
        }
        .onAppear {
            synchronizeFromQuery()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(GitMateTheme.textTertiary)
                TextField(
                    "搜索标题、正文，或输入 GitHub 高级搜索条件",
                    text: $searchText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit(applyFilters)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(GitMateTheme.border, lineWidth: 1)
            }

            Button("搜索", action: applyFilters)
                .buttonStyle(.bordered)

            Button {
                viewModel.navigate(to: .newIssue)
            } label: {
                Label("新建议题", systemImage: "plus")
            }
            .buttonStyle(GitMateButtonStyle(role: .primary))
            .accessibilityIdentifier("workspace.issues.create")
        }
    }

    private var summary: some View {
        let open = viewModel.state.issues.filter(\.isOpen).count
        let closed = viewModel.state.issues.count - open
        let assignedToMe = viewModel.state.issues.filter {
            $0.assignees.contains {
                $0.login == viewModel.context.account.login
            }
        }.count
        let locked = viewModel.state.issues.filter(\.isLocked).count

        return HStack(spacing: 0) {
            summaryItem(
                value: open,
                title: "进行中",
                color: GitMateTheme.success
            )
            summaryItem(
                value: closed,
                title: "已关闭",
                color: .purple
            )
            summaryItem(
                value: assignedToMe,
                title: "分配给我",
                color: GitMateTheme.accent
            )
            summaryItem(
                value: locked,
                title: "已锁定",
                color: GitMateTheme.warning
            )
        }
        .frame(height: 62)
        .workspacePanel()
    }

    private func summaryItem(
        value: Int,
        title: String,
        color: Color
    ) -> some View {
        HStack(spacing: 10) {
            Text("\(value)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(GitMateTheme.border)
                .frame(width: 1, height: 32)
        }
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("筛选条件")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button("重置") {
                    searchText = ""
                    stateFilter = "all"
                    sort = .updated
                    direction = .descending
                    labelFilter = ""
                    applyFilters()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .semibold))
            }

            filterField("状态") {
                Picker("", selection: $stateFilter) {
                    Text("全部").tag("all")
                    Text("进行中").tag("open")
                    Text("已关闭").tag("closed")
                }
                .labelsHidden()
            }

            filterField("标签") {
                TextField("多个标签用逗号分隔", text: $labelFilter)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            filterField("排序") {
                Picker("", selection: $sort) {
                    Text("最近更新").tag(IssueSort.updated)
                    Text("创建时间").tag(IssueSort.created)
                    Text("评论数量").tag(IssueSort.comments)
                }
                .labelsHidden()
            }

            filterField("方向") {
                Picker("", selection: $direction) {
                    Text("降序").tag(IssueDirection.descending)
                    Text("升序").tag(IssueDirection.ascending)
                }
                .labelsHidden()
            }

            Button("应用筛选", action: applyFilters)
                .buttonStyle(GitMateButtonStyle(role: .primary))
                .frame(maxWidth: .infinity)

            Divider()

            HStack {
                Text("保存的视图")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Button {
                    savedViewName = ""
                    showsSaveView = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .help("保存当前搜索")
            }

            if viewModel.state.savedIssueViews.isEmpty {
                Text("保存常用搜索后，可以一键恢复。")
                    .font(.system(size: 10))
                    .foregroundStyle(GitMateTheme.textTertiary)
            } else {
                ForEach(viewModel.state.savedIssueViews) { savedView in
                    Button {
                        searchText = savedView.query
                        applyFilters()
                    } label: {
                        HStack {
                            Image(systemName: "bookmark")
                            Text(savedView.name)
                                .lineLimit(1)
                            Spacer()
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(GitMateTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(14)
        .frame(maxHeight: .infinity)
        .workspacePanel()
    }

    private func filterField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(GitMateTheme.textSecondary)
            content()
                .frame(maxWidth: .infinity)
        }
    }

    private var issueList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("议题")
                Text("\(viewModel.state.issues.count)")
                    .foregroundStyle(GitMateTheme.textTertiary)
                Spacer()
                Text("最近更新")
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(GitMateTheme.textSecondary)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(GitMateTheme.panel)

            Divider()

            if viewModel.state.issues.isEmpty {
                WorkspaceEmptyView(
                    icon: "circle.circle",
                    title: "没有找到议题",
                    message: "调整筛选条件，或创建仓库的第一个议题。"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.state.issues) { issue in
                            issueRow(issue)
                            Divider()
                                .padding(.leading, 58)
                        }

                        if viewModel.state.nextIssuesPageURL != nil {
                            Button {
                                Task {
                                    await viewModel.loadMoreIssues()
                                }
                            } label: {
                                Label("加载更多议题", systemImage: "arrow.down")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(GitMateTheme.accent)
                        }
                    }
                }
            }
        }
        .workspacePanel()
    }

    private func issueRow(_ issue: GitHubIssue) -> some View {
        Button {
            viewModel.navigate(to: .issueDetail(number: issue.number))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                IssueAvatarView(user: issue.author, size: 32)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        IssueStateChip(state: issue.state)
                        Text("#\(issue.number)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(GitMateTheme.textTertiary)
                        if issue.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(GitMateTheme.warning)
                        }
                    }

                    Text(issue.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GitMateTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        ForEach(issue.labels.prefix(4)) { label in
                            IssueLabelChip(label: label)
                        }
                        if issue.labels.count > 4 {
                            Text("+\(issue.labels.count - 4)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(GitMateTheme.textSecondary)
                        }
                    }

                    HStack(spacing: 10) {
                        Text("@\(issue.author.login)")
                        if let milestone = issue.milestone {
                            Label(milestone.title, systemImage: "signpost.right")
                        }
                        Label(
                            "\(issue.commentsCount)",
                            systemImage: "bubble.left"
                        )
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(GitMateTheme.textSecondary)
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(workspaceDate(issue.updatedAt))
                        .font(.system(size: 9))
                        .foregroundStyle(GitMateTheme.textSecondary)
                    if !issue.assignees.isEmpty {
                        HStack(spacing: -6) {
                            ForEach(issue.assignees.prefix(3)) {
                                IssueAvatarView(user: $0, size: 22)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var saveViewSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("保存当前视图")
                .font(.system(size: 18, weight: .bold))
            Text("保存搜索内容，稍后可从议题左侧快速恢复。")
                .font(.system(size: 11))
                .foregroundStyle(GitMateTheme.textSecondary)
            TextField("视图名称", text: $savedViewName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") {
                    showsSaveView = false
                }
                .buttonStyle(.bordered)
                Button("保存") {
                    let view = SavedIssueView(
                        name: savedViewName,
                        query: searchText
                    )
                    viewModel.saveIssueViews(
                        viewModel.state.savedIssueViews + [view]
                    )
                    showsSaveView = false
                }
                .buttonStyle(GitMateButtonStyle(role: .primary))
                .disabled(
                    savedViewName
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }
        }
        .padding(22)
        .frame(width: 420)
    }

    private func applyFilters() {
        let state: IssueState?
        switch stateFilter {
        case "open":
            state = .open
        case "closed":
            state = .closed
        default:
            state = nil
        }
        let labels = labelFilter
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let query = IssueQuery(
            state: state,
            labels: labels,
            sort: sort,
            direction: direction,
            search: searchText
        )
        Task {
            await viewModel.updateIssueQuery(query)
        }
    }

    private func synchronizeFromQuery() {
        let query = viewModel.state.issueQuery
        stateFilter = query.state?.rawValue ?? "all"
        searchText = query.search ?? ""
        labelFilter = query.labels.joined(separator: ", ")
        sort = query.sort
        direction = query.direction
    }
}
