import GitMateCore
import SwiftUI

struct BranchesView: View {
    @Bindable var viewModel: RepositoryWorkspaceViewModel
    @State private var searchText = ""
    @State private var selectedName: String?
    @State private var showsCreateSheet = false

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            summary

            HStack(spacing: 12) {
                branchList
                    .frame(
                        minWidth: 390,
                        idealWidth: GitMateTheme.workspaceListWidth
                    )

                if let selectedBranch {
                    BranchDetailView(
                        branch: selectedBranch,
                        viewModel: viewModel
                    )
                } else {
                    WorkspaceEmptyView(
                        icon: "arrow.triangle.branch",
                        title: "选择一个分支",
                        message: "查看本地状态、远端关系、保护规则和可用操作。"
                    )
                    .workspacePanel()
                }
            }
        }
        .sheet(isPresented: $showsCreateSheet) {
            NewBranchSheet(
                defaultStartPoint: viewModel.context.repository.defaultBranch,
                onCancel: { showsCreateSheet = false },
                onCreate: { name, startPoint in
                    showsCreateSheet = false
                    Task {
                        await viewModel.createBranch(
                            name: name,
                            startPoint: startPoint
                        )
                        await viewModel.loadCurrentRoute()
                    }
                }
            )
        }
        .onChange(
            of: viewModel.state.branches.map(\.id),
            initial: true
        ) { _, identifiers in
            if selectedName == nil || !identifiers.contains(selectedName ?? "") {
                selectedName = identifiers.first
            }
        }
    }

    private var filteredBranches: [GitBranch] {
        guard !searchText.isEmpty else {
            return viewModel.state.branches
        }
        return viewModel.state.branches.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.authorName?.localizedCaseInsensitiveContains(searchText) == true)
        }
    }

    private var selectedBranch: GitBranch? {
        viewModel.state.branches.first { $0.name == selectedName }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(GitMateTheme.textTertiary)
                TextField("搜索分支名称或提交作者", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .accessibilityIdentifier("workspace.branches.search")
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(GitMateTheme.border, lineWidth: 1)
            }

            Button {
                showsCreateSheet = true
            } label: {
                Label("新建分支", systemImage: "plus")
            }
            .buttonStyle(GitMateButtonStyle(role: .primary))
            .disabled(viewModel.context.localDirectory == nil)
            .accessibilityIdentifier("workspace.branches.create")
        }
    }

    private var summary: some View {
        HStack(spacing: 0) {
            summaryItem(
                value: viewModel.state.branches.filter {
                    $0.location != .remote
                }.count,
                title: "本地分支",
                color: GitMateTheme.accent
            )
            summaryItem(
                value: viewModel.state.branches.filter {
                    $0.location != .local
                }.count,
                title: "远端分支",
                color: GitMateTheme.textPrimary
            )
            summaryItem(
                value: viewModel.state.branches.filter {
                    switch $0.trackingStatus {
                    case .ahead, .behind, .diverged, .localOnly:
                        true
                    default:
                        false
                    }
                }.count,
                title: "需要同步",
                color: GitMateTheme.warning
            )
            summaryItem(
                value: viewModel.state.branches.filter(\.isProtected).count,
                title: "受保护",
                color: GitMateTheme.success
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

    private var branchList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("分支")
                Spacer()
                Text("与远端关系")
                    .frame(width: 110, alignment: .leading)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(GitMateTheme.textTertiary)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(GitMateTheme.panel)

            Divider()

            if filteredBranches.isEmpty {
                WorkspaceEmptyView(
                    icon: "arrow.triangle.branch",
                    title: searchText.isEmpty ? "没有分支" : "没有匹配结果",
                    message: searchText.isEmpty
                        ? "同步仓库后会在这里显示本地与远端分支。"
                        : "尝试缩短搜索关键词。"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredBranches) { branch in
                            branchRow(branch)
                            Divider()
                                .padding(.leading, 14)
                        }
                    }
                }
            }
        }
        .workspacePanel()
    }

    private func branchRow(_ branch: GitBranch) -> some View {
        Button {
            selectedName = branch.name
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            selectedName == branch.name
                                ? GitMateTheme.accent
                                : GitMateTheme.accentSoft
                        )
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            selectedName == branch.name
                                ? .white
                                : GitMateTheme.accent
                        )
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(branch.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        if branch.isProtected {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(GitMateTheme.success)
                        }
                    }
                    Text(branchSubtitle(branch))
                        .font(.system(size: 10))
                        .foregroundStyle(GitMateTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                trackingChip(branch.trackingStatus)
                    .frame(width: 110, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(height: GitMateTheme.workspaceRowHeight)
            .background(
                selectedName == branch.name
                    ? GitMateTheme.selection.opacity(0.72)
                    : .white
            )
        }
        .buttonStyle(.plain)
    }

    private func branchSubtitle(_ branch: GitBranch) -> String {
        switch branch.location {
        case .local:
            "仅本地 · \(shortSHA(branch.localSHA))"
        case .remote:
            "\(branch.remoteName ?? "远端") · \(shortSHA(branch.remoteSHA))"
        case .localAndRemote:
            "\(branch.upstreamName ?? branch.remoteName ?? "已跟踪") · \(shortSHA(branch.localSHA))"
        }
    }

    @ViewBuilder
    private func trackingChip(_ status: BranchTrackingStatus) -> some View {
        switch status {
        case .localOnly:
            WorkspaceStatusChip(text: "未发布", color: GitMateTheme.warning)
        case .remoteOnly:
            WorkspaceStatusChip(text: "仅远端", color: GitMateTheme.textSecondary)
        case .synchronized:
            WorkspaceStatusChip(text: "已同步", color: GitMateTheme.success)
        case let .ahead(count):
            WorkspaceStatusChip(text: "领先 \(count)", color: GitMateTheme.accent)
        case let .behind(count):
            WorkspaceStatusChip(text: "落后 \(count)", color: GitMateTheme.warning)
        case let .diverged(ahead, behind):
            WorkspaceStatusChip(
                text: "\(ahead)↑ \(behind)↓",
                color: GitMateTheme.danger
            )
        }
    }
}

private struct NewBranchSheet: View {
    let defaultStartPoint: String
    let onCancel: () -> Void
    let onCreate: (String, String) -> Void

    @State private var name = ""
    @State private var startPoint: String

    init(
        defaultStartPoint: String,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (String, String) -> Void
    ) {
        self.defaultStartPoint = defaultStartPoint
        self.onCancel = onCancel
        self.onCreate = onCreate
        _startPoint = State(initialValue: defaultStartPoint)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建分支")
                .font(.system(size: 20, weight: .bold))
            VStack(alignment: .leading, spacing: 7) {
                Text("分支名称")
                    .font(.system(size: 11, weight: .semibold))
                TextField("feature/新功能", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("起点")
                    .font(.system(size: 11, weight: .semibold))
                TextField(defaultStartPoint, text: $startPoint)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(GitMateButtonStyle(role: .secondary))
                Button("创建并签出") {
                    onCreate(
                        name.trimmingCharacters(in: .whitespacesAndNewlines),
                        startPoint.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .buttonStyle(GitMateButtonStyle(role: .primary))
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || startPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(26)
        .frame(width: 440)
    }
}
