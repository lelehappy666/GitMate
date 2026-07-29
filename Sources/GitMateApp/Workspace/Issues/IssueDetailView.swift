import GitMateCore
import SwiftUI

struct IssueDetailView: View {
    @Bindable var viewModel: RepositoryWorkspaceViewModel
    @Environment(\.openURL) private var openURL
    @State private var commentBody = ""
    @State private var showsEditSheet = false

    var body: some View {
        if let issue = viewModel.state.selectedIssue {
            VStack(spacing: 12) {
                detailToolbar(issue)
                HStack(alignment: .top, spacing: 12) {
                    conversation(issue)
                    metadata(issue)
                        .frame(width: 270)
                }
            }
            .sheet(isPresented: $showsEditSheet) {
                EditIssueSheet(
                    issue: issue,
                    onCancel: { showsEditSheet = false },
                    onSave: { input in
                        showsEditSheet = false
                        Task {
                            await viewModel.updateIssue(input)
                        }
                    }
                )
            }
        } else {
            WorkspaceEmptyView(
                icon: "circle.dotted",
                title: "正在读取议题",
                message: "GitMate 正在加载正文、时间线和评论。"
            )
            .workspacePanel()
        }
    }

    private func detailToolbar(_ issue: GitHubIssue) -> some View {
        HStack(spacing: 10) {
            Button {
                viewModel.navigate(to: .issues)
            } label: {
                Label("返回议题", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)

            IssueStateChip(state: issue.state)

            Text("#\(issue.number)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(GitMateTheme.textSecondary)

            Spacer()

            if let webURL = issue.webURL {
                Button {
                    openURL(webURL)
                } label: {
                    Label("在 GitHub 打开", systemImage: "arrow.up.right")
                }
                .buttonStyle(.bordered)
            }

            Button {
                showsEditSheet = true
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .buttonStyle(GitMateButtonStyle(role: .primary))
        }
    }

    private func conversation(_ issue: GitHubIssue) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    issueBody(issue)

                    if !viewModel.state.timeline.isEmpty {
                        timelineHeader
                        ForEach(viewModel.state.timeline) {
                            timelineEvent($0)
                        }
                    }

                    ForEach(viewModel.state.comments) {
                        commentCard($0)
                    }

                    commentEditor
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .workspacePanel()
    }

    private func issueBody(_ issue: GitHubIssue) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                IssueAvatarView(user: issue.author, size: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.title)
                        .font(.system(size: 19, weight: .bold))
                    Text(
                        "@\(issue.author.login) 创建于 \(workspaceDate(issue.createdAt))"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(GitMateTheme.textSecondary)
                }
                Spacer()
            }

            Divider()

            if let body = issue.body, !body.isEmpty {
                IssueMarkdownView(markdown: body)
            } else {
                Text("该议题没有正文。")
                    .font(.system(size: 12))
                    .foregroundStyle(GitMateTheme.textTertiary)
                    .italic()
            }
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(GitMateTheme.border)
        }
    }

    private var timelineHeader: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(GitMateTheme.border)
                .frame(height: 1)
            Text("活动时间线")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(GitMateTheme.textTertiary)
                .fixedSize()
            Rectangle()
                .fill(GitMateTheme.border)
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private func timelineEvent(_ event: IssueTimelineEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(timelineColor(event.kind).opacity(0.12))
                Image(systemName: timelineIcon(event.kind))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(timelineColor(event.kind))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(timelineText(event))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GitMateTheme.textPrimary)
                Text(workspaceDate(event.createdAt))
                    .font(.system(size: 9))
                    .foregroundStyle(GitMateTheme.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private func commentCard(_ comment: IssueComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            IssueAvatarView(user: comment.author, size: 32)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("@\(comment.author.login)")
                        .font(.system(size: 11, weight: .bold))
                    Text("评论于 \(workspaceDate(comment.createdAt))")
                        .font(.system(size: 9))
                        .foregroundStyle(GitMateTheme.textSecondary)
                    Spacer()
                }
                Divider()
                IssueMarkdownView(markdown: comment.body)
            }
            .padding(13)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(GitMateTheme.border)
            }
        }
    }

    private var commentEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("添加评论")
                .font(.system(size: 12, weight: .bold))
            TextEditor(text: $commentBody)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 96)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(GitMateTheme.border)
                }
            HStack {
                Text("支持 Markdown")
                    .font(.system(size: 9))
                    .foregroundStyle(GitMateTheme.textTertiary)
                Spacer()
                Button("发表评论") {
                    let body = commentBody
                    commentBody = ""
                    Task {
                        await viewModel.addComment(body: body)
                    }
                }
                .buttonStyle(GitMateButtonStyle(role: .primary))
                .disabled(
                    commentBody
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }
        }
        .padding(14)
        .background(GitMateTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func metadata(_ issue: GitHubIssue) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    metadataSection("负责人", icon: "person.2") {
                        if issue.assignees.isEmpty {
                            metadataPlaceholder("尚未分配")
                        } else {
                            ForEach(issue.assignees) { user in
                                HStack(spacing: 8) {
                                    IssueAvatarView(user: user, size: 24)
                                    Text("@\(user.login)")
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                        }
                    }

                    metadataSection("标签", icon: "tag") {
                        if issue.labels.isEmpty {
                            metadataPlaceholder("没有标签")
                        } else {
                            FlowLayout(spacing: 6) {
                                ForEach(issue.labels) {
                                    IssueLabelChip(label: $0)
                                }
                            }
                        }
                    }

                    metadataSection("里程碑", icon: "signpost.right") {
                        if let milestone = issue.milestone {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(milestone.title)
                                    .font(.system(size: 11, weight: .semibold))
                                ProgressView(value: milestone.progress)
                                    .tint(GitMateTheme.success)
                                Text(
                                    "\(milestone.closedIssues) / \(milestone.openIssues + milestone.closedIssues) 已完成"
                                )
                                .font(.system(size: 9))
                                .foregroundStyle(
                                    GitMateTheme.textSecondary
                                )
                            }
                        } else {
                            metadataPlaceholder("没有里程碑")
                        }
                    }

                    metadataSection("状态", icon: "lock") {
                        VStack(alignment: .leading, spacing: 10) {
                            IssueStateChip(state: issue.state)
                            if issue.isLocked {
                                Label("讨论已锁定", systemImage: "lock.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(GitMateTheme.warning)
                            }
                        }
                    }
                }
                .padding(15)
            }

            Divider()

            issueActions(issue)
                .padding(14)
        }
        .frame(maxHeight: .infinity)
        .workspacePanel()
    }

    private func metadataSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(GitMateTheme.textPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(GitMateTheme.textTertiary)
    }

    private func issueActions(_ issue: GitHubIssue) -> some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    await viewModel.updateIssue(
                        UpdateIssueInput(
                            title: issue.title,
                            body: issue.body ?? "",
                            state: issue.state == .open ? .closed : .open,
                            assigneeLogins: issue.assignees.map(\.login),
                            labelNames: issue.labels.map(\.name),
                            milestoneNumber: issue.milestone?.number
                        )
                    )
                }
            } label: {
                Label(
                    issue.state == .open ? "关闭议题" : "重新打开",
                    systemImage: issue.state == .open
                        ? "checkmark.circle"
                        : "arrow.uturn.backward.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if issue.isLocked {
                Button {
                    Task {
                        await viewModel.unlockSelectedIssue()
                    }
                } label: {
                    Label("解锁讨论", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Menu {
                    Button("已解决") {
                        lock(reason: .resolved)
                    }
                    Button("偏离主题") {
                        lock(reason: .offTopic)
                    }
                    Button("争论过热") {
                        lock(reason: .tooHeated)
                    }
                    Button("垃圾信息") {
                        lock(reason: .spam)
                    }
                } label: {
                    Label("锁定讨论", systemImage: "lock")
                        .frame(maxWidth: .infinity)
                }
                .menuStyle(.borderlessButton)
            }
        }
    }

    private func lock(reason: IssueLockReason) {
        Task {
            await viewModel.lockSelectedIssue(reason: reason)
        }
    }

    private func timelineIcon(_ kind: IssueTimelineEventKind) -> String {
        switch kind {
        case .closed:
            "checkmark.circle"
        case .reopened:
            "arrow.uturn.backward.circle"
        case .labeled, .unlabeled:
            "tag"
        case .assigned, .unassigned:
            "person"
        case .milestoned, .demilestoned:
            "signpost.right"
        case .locked, .unlocked:
            "lock"
        case .referenced, .committed:
            "link"
        case .commented:
            "bubble.left"
        }
    }

    private func timelineColor(_ kind: IssueTimelineEventKind) -> Color {
        switch kind {
        case .closed:
            .purple
        case .reopened:
            GitMateTheme.success
        case .locked:
            GitMateTheme.warning
        default:
            GitMateTheme.accent
        }
    }

    private func timelineText(_ event: IssueTimelineEvent) -> String {
        let actor = event.actor.map { "@\($0.login) " } ?? ""
        let detail = event.detail.map { "：\($0)" } ?? ""
        let action: String
        switch event.kind {
        case .commented:
            action = "发表了评论"
        case .closed:
            action = "关闭了议题"
        case .reopened:
            action = "重新打开了议题"
        case .labeled:
            action = "添加了标签"
        case .unlabeled:
            action = "移除了标签"
        case .assigned:
            action = "分配了负责人"
        case .unassigned:
            action = "移除了负责人"
        case .milestoned:
            action = "设置了里程碑"
        case .demilestoned:
            action = "移除了里程碑"
        case .locked:
            action = "锁定了讨论"
        case .unlocked:
            action = "解锁了讨论"
        case .referenced:
            action = "引用了该议题"
        case .committed:
            action = "在提交中关联了该议题"
        }
        return actor + action + detail
    }
}

private struct EditIssueSheet: View {
    let issue: GitHubIssue
    let onCancel: () -> Void
    let onSave: (UpdateIssueInput) -> Void
    @State private var title: String
    @State private var issueBodyText: String

    init(
        issue: GitHubIssue,
        onCancel: @escaping () -> Void,
        onSave: @escaping (UpdateIssueInput) -> Void
    ) {
        self.issue = issue
        self.onCancel = onCancel
        self.onSave = onSave
        _title = State(initialValue: issue.title)
        _issueBodyText = State(initialValue: issue.body ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑议题 #\(issue.number)")
                .font(.system(size: 18, weight: .bold))
            TextField("标题", text: $title)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $issueBodyText)
                .font(.system(size: 12))
                .padding(8)
                .frame(height: 300)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(GitMateTheme.border)
                }
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                Button("保存") {
                    onSave(
                        UpdateIssueInput(
                            title: title,
                            body: issueBodyText,
                            state: issue.state,
                            assigneeLogins: issue.assignees.map(\.login),
                            labelNames: issue.labels.map(\.name),
                            milestoneNumber: issue.milestone?.number
                        )
                    )
                }
                .buttonStyle(GitMateButtonStyle(role: .primary))
                .disabled(
                    title.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }
        }
        .padding(22)
        .frame(width: 640, height: 470)
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(
            proposal: proposal,
            subviews: subviews,
            place: false
        ).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        _ = layout(
            proposal: ProposedViewSize(
                width: bounds.width,
                height: proposal.height
            ),
            subviews: subviews,
            place: true,
            origin: bounds.origin
        )
    }

    private func layout(
        proposal: ProposedViewSize,
        subviews: Subviews,
        place: Bool,
        origin: CGPoint = .zero
    ) -> (size: CGSize, positions: [CGPoint]) {
        let width = proposal.width ?? 260
        var x = origin.x
        var y = origin.y
        var rowHeight: CGFloat = 0
        var positions: [CGPoint] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > origin.x, x + size.width > origin.x + width {
                x = origin.x
                y += rowHeight + spacing
                rowHeight = 0
            }
            let position = CGPoint(x: x, y: y)
            positions.append(position)
            if place {
                subview.place(
                    at: position,
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return (
            CGSize(
                width: width,
                height: max(0, y - origin.y + rowHeight)
            ),
            positions
        )
    }
}
