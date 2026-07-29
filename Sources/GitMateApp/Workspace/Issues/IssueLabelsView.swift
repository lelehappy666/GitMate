import GitMateCore
import SwiftUI

struct IssueLabelsView: View {
    @Bindable var viewModel: RepositoryWorkspaceViewModel
    @State private var searchText = ""
    @State private var editingLabel: IssueLabel?
    @State private var showsEditor = false
    @State private var showsMergeSheet = false

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            summary
            mergeProgress
            labelGrid
        }
        .sheet(isPresented: $showsEditor) {
            LabelEditorSheet(
                label: editingLabel,
                onCancel: {
                    editingLabel = nil
                    showsEditor = false
                },
                onSave: { input in
                    let original = editingLabel
                    editingLabel = nil
                    showsEditor = false
                    Task {
                        if let original {
                            await viewModel.updateLabel(
                                name: original.name,
                                input: input
                            )
                        } else {
                            await viewModel.createLabel(input)
                        }
                    }
                }
            )
        }
        .sheet(isPresented: $showsMergeSheet) {
            LabelMergeSheet(
                labels: viewModel.state.labels,
                onCancel: { showsMergeSheet = false },
                onMerge: { source, target in
                    showsMergeSheet = false
                    let affected = viewModel.state.labels.first {
                        $0.name == source
                    }?.issueCount ?? 0
                    viewModel.requestMergeLabels(
                        source: source,
                        target: target,
                        affectedIssues: affected
                    )
                }
            )
        }
    }

    private var filteredLabels: [IssueLabel] {
        guard !searchText.isEmpty else {
            return viewModel.state.labels
        }
        return viewModel.state.labels.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.description?
                    .localizedCaseInsensitiveContains(searchText) == true)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(GitMateTheme.textTertiary)
                TextField("搜索标签名称或说明", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(GitMateTheme.border)
            }

            Button {
                showsMergeSheet = true
            } label: {
                Label("合并标签", systemImage: "arrow.triangle.merge")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.state.labels.count < 2)

            Button {
                editingLabel = nil
                showsEditor = true
            } label: {
                Label("新建标签", systemImage: "plus")
            }
            .buttonStyle(GitMateButtonStyle(role: .primary))
            .accessibilityIdentifier("workspace.labels.create")
        }
    }

    private var summary: some View {
        HStack(spacing: 0) {
            summaryItem(
                value: viewModel.state.labels.count,
                title: "全部标签",
                color: GitMateTheme.textPrimary
            )
            summaryItem(
                value: viewModel.state.labels.filter(\.isDefault).count,
                title: "默认标签",
                color: GitMateTheme.accent
            )
            summaryItem(
                value: viewModel.state.labels.reduce(0) {
                    $0 + $1.openIssueCount
                },
                title: "进行中使用",
                color: GitMateTheme.success
            )
            summaryItem(
                value: viewModel.state.labels.filter {
                    $0.issueCount == 0
                }.count,
                title: "未使用",
                color: GitMateTheme.warning
            )
        }
        .frame(height: 62)
        .workspacePanel()
    }

    @ViewBuilder
    private var mergeProgress: some View {
        if let progress = viewModel.state.labelMergeProgress {
            HStack(spacing: 12) {
                Image(
                    systemName: progress.failedIssueNumbers.isEmpty
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(
                    progress.failedIssueNumbers.isEmpty
                        ? GitMateTheme.success
                        : GitMateTheme.warning
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        progress.failedIssueNumbers.isEmpty
                            ? "标签合并已完成"
                            : "标签合并部分完成，可重新执行以继续"
                    )
                    .font(.system(size: 11, weight: .bold))
                    Text(
                        "已更新 \(progress.completedIssueNumbers.count) 个议题"
                            + (
                                progress.failedIssueNumbers.isEmpty
                                    ? ""
                                    : "，失败 \(progress.failedIssueNumbers.count) 个"
                            )
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(GitMateTheme.textSecondary)
                }
                Spacer()
                if !progress.failedIssueNumbers.isEmpty {
                    Text(
                        progress.failedIssueNumbers
                            .map { "#\($0)" }
                            .joined(separator: "、")
                    )
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(GitMateTheme.danger)
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(
                (
                    progress.failedIssueNumbers.isEmpty
                        ? GitMateTheme.success
                        : GitMateTheme.warning
                )
                .opacity(0.08)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        (
                            progress.failedIssueNumbers.isEmpty
                                ? GitMateTheme.success
                                : GitMateTheme.warning
                        )
                        .opacity(0.25)
                    )
            }
        }
    }

    private var labelGrid: some View {
        ScrollView {
            if filteredLabels.isEmpty {
                WorkspaceEmptyView(
                    icon: "swatchpalette",
                    title: searchText.isEmpty ? "没有标签" : "没有匹配结果",
                    message: "创建标签后可用于议题分类与筛选。"
                )
                .frame(minHeight: 360)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 285), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(filteredLabels) { label in
                        labelCard(label)
                    }
                }
                .padding(1)
            }
        }
    }

    private func labelCard(_ label: IssueLabel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                IssueLabelChip(label: label)
                if label.isDefault {
                    Text("默认")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(GitMateTheme.accent)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(GitMateTheme.accentSoft)
                        .clipShape(Capsule())
                }
                Spacer()
                Menu {
                    Button("编辑") {
                        editingLabel = label
                        showsEditor = true
                    }
                    Divider()
                    Button("删除", role: .destructive) {
                        viewModel.requestDeleteLabel(
                            name: label.name,
                            affectedIssues: label.issueCount
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 24)
                }
                .menuStyle(.borderlessButton)
            }

            Text(label.description ?? "没有说明")
                .font(.system(size: 10))
                .foregroundStyle(GitMateTheme.textSecondary)
                .lineLimit(2)
                .frame(minHeight: 26, alignment: .topLeading)

            HStack(spacing: 16) {
                labelMetric(
                    "\(label.openIssueCount)",
                    title: "进行中",
                    color: GitMateTheme.success
                )
                labelMetric(
                    "\(label.closedIssueCount)",
                    title: "已关闭",
                    color: .purple
                )
                Spacer()
                Text("#\(label.normalizedColorHex)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(GitMateTheme.textTertiary)
            }

            GeometryReader { proxy in
                let total = max(1, label.issueCount)
                let openWidth = proxy.size.width
                    * CGFloat(label.openIssueCount) / CGFloat(total)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.purple.opacity(0.18))
                    Capsule()
                        .fill(GitMateTheme.success)
                        .frame(width: openWidth)
                }
            }
            .frame(height: 5)
        }
        .padding(15)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(GitMateTheme.border)
        }
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

    private func labelMetric(
        _ value: String,
        title: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 8))
                .foregroundStyle(GitMateTheme.textTertiary)
        }
    }
}

private struct LabelEditorSheet: View {
    let label: IssueLabel?
    let onCancel: () -> Void
    let onSave: (IssueLabelInput) -> Void
    @State private var name: String
    @State private var color: String
    @State private var labelDescription: String

    init(
        label: IssueLabel?,
        onCancel: @escaping () -> Void,
        onSave: @escaping (IssueLabelInput) -> Void
    ) {
        self.label = label
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: label?.name ?? "")
        _color = State(initialValue: label?.normalizedColorHex ?? "2F81F7")
        _labelDescription = State(initialValue: label?.description ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(label == nil ? "新建议题标签" : "编辑议题标签")
                .font(.system(size: 19, weight: .bold))
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(issueHex: normalizedColor))
                    .frame(width: 38, height: 38)
                TextField("标签名称", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("颜色")
                    .font(.system(size: 10, weight: .semibold))
                HStack {
                    Text("#")
                        .foregroundStyle(GitMateTheme.textSecondary)
                    TextField("2F81F7", text: $color)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("说明")
                    .font(.system(size: 10, weight: .semibold))
                TextField("这个标签用于什么？", text: $labelDescription)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                Button("保存") {
                    onSave(
                        IssueLabelInput(
                            name: name.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ),
                            color: normalizedColor,
                            description:
                                labelDescription.isEmpty
                                    ? nil
                                    : labelDescription
                        )
                    )
                }
                .buttonStyle(GitMateButtonStyle(role: .primary))
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }
        }
        .padding(22)
        .frame(width: 470)
    }

    private var normalizedColor: String {
        IssueLabel(
            id: 0,
            name: name,
            color: color
        ).normalizedColorHex
    }
}

private struct LabelMergeSheet: View {
    let labels: [IssueLabel]
    let onCancel: () -> Void
    let onMerge: (String, String) -> Void
    @State private var source: String
    @State private var target: String

    init(
        labels: [IssueLabel],
        onCancel: @escaping () -> Void,
        onMerge: @escaping (String, String) -> Void
    ) {
        self.labels = labels
        self.onCancel = onCancel
        self.onMerge = onMerge
        _source = State(initialValue: labels.first?.name ?? "")
        _target = State(initialValue: labels.dropFirst().first?.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("合并标签")
                .font(.system(size: 19, weight: .bold))
            Text("GitMate 会逐个更新议题，全部成功后才删除来源标签。")
                .font(.system(size: 11))
                .foregroundStyle(GitMateTheme.textSecondary)
            LabeledContent("来源标签") {
                Picker("", selection: $source) {
                    ForEach(labels) {
                        Text($0.name).tag($0.name)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
            }
            HStack {
                Spacer()
                Image(systemName: "arrow.down")
                    .foregroundStyle(GitMateTheme.accent)
                Spacer()
            }
            LabeledContent("目标标签") {
                Picker("", selection: $target) {
                    ForEach(labels) {
                        Text($0.name).tag($0.name)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
            }
            if source == target {
                Label(
                    "来源和目标不能相同",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(GitMateTheme.danger)
            }
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                Button("下一步") {
                    onMerge(source, target)
                }
                .buttonStyle(GitMateButtonStyle(role: .primary))
                .disabled(source.isEmpty || target.isEmpty || source == target)
            }
        }
        .padding(22)
        .frame(width: 500)
    }
}
