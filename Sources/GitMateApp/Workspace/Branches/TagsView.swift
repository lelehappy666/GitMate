import GitMateCore
import SwiftUI

struct TagsView: View {
    @Bindable var viewModel: RepositoryWorkspaceViewModel
    @State private var searchText = ""
    @State private var selectedName: String?
    @State private var showsCreateSheet = false

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            summary

            HStack(spacing: 12) {
                tagList
                    .frame(
                        minWidth: 390,
                        idealWidth: GitMateTheme.workspaceListWidth
                    )

                if let selectedTag {
                    TagDetailView(tag: selectedTag, viewModel: viewModel)
                } else {
                    WorkspaceEmptyView(
                        icon: "tag",
                        title: "选择一个标签",
                        message: "查看目标提交、标签类型、远端状态和 Release 入口。"
                    )
                    .workspacePanel()
                }
            }
        }
        .sheet(isPresented: $showsCreateSheet) {
            NewTagSheet(
                defaultTarget: viewModel.context.repository.defaultBranch,
                onCancel: { showsCreateSheet = false },
                onCreate: { name, target, message in
                    showsCreateSheet = false
                    Task {
                        await viewModel.createTag(
                            name: name,
                            target: target,
                            message: message
                        )
                        await viewModel.loadCurrentRoute()
                    }
                }
            )
        }
        .onChange(
            of: viewModel.state.tags.map(\.id),
            initial: true
        ) { _, identifiers in
            if selectedName == nil || !identifiers.contains(selectedName ?? "") {
                selectedName = identifiers.first
            }
        }
    }

    private var filteredTags: [GitTag] {
        guard !searchText.isEmpty else {
            return viewModel.state.tags
        }
        return viewModel.state.tags.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.objectSHA.localizedCaseInsensitiveContains(searchText)
                || ($0.message?.localizedCaseInsensitiveContains(searchText) == true)
        }
    }

    private var selectedTag: GitTag? {
        viewModel.state.tags.first { $0.name == selectedName }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(GitMateTheme.textTertiary)
                TextField("搜索标签名称、提交或说明", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
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
                Label("新建标签", systemImage: "plus")
            }
            .buttonStyle(GitMateButtonStyle(role: .primary))
            .disabled(viewModel.context.localDirectory == nil)
            .accessibilityIdentifier("workspace.tags.create")
        }
    }

    private var summary: some View {
        HStack(spacing: 0) {
            summaryItem(
                value: viewModel.state.tags.count,
                title: "全部标签",
                color: GitMateTheme.textPrimary
            )
            summaryItem(
                value: viewModel.state.tags.filter {
                    $0.kind == .annotated
                }.count,
                title: "附注标签",
                color: GitMateTheme.accent
            )
            summaryItem(
                value: viewModel.state.tags.filter {
                    $0.remoteStatus == .synchronized
                }.count,
                title: "已同步",
                color: GitMateTheme.success
            )
            summaryItem(
                value: viewModel.state.tags.filter {
                    $0.remoteStatus == .localOnly
                }.count,
                title: "仅本地",
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

    private var tagList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("标签")
                Spacer()
                Text("目标提交")
                    .frame(width: 100, alignment: .leading)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(GitMateTheme.textTertiary)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(GitMateTheme.panel)

            Divider()

            if filteredTags.isEmpty {
                WorkspaceEmptyView(
                    icon: "tag",
                    title: searchText.isEmpty ? "没有标签" : "没有匹配结果",
                    message: "创建版本标签后会在这里显示。"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredTags) { tag in
                            tagRow(tag)
                            Divider()
                                .padding(.leading, 14)
                        }
                    }
                }
            }
        }
        .workspacePanel()
    }

    private func tagRow(_ tag: GitTag) -> some View {
        Button {
            selectedName = tag.name
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            selectedName == tag.name
                                ? GitMateTheme.accent
                                : Color.purple.opacity(0.10)
                        )
                    Image(systemName: "tag.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(
                            selectedName == tag.name ? .white : .purple
                        )
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(tag.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(
                        tag.kind == .annotated
                            ? "附注标签 · \(tag.taggerName ?? "未知创建者")"
                            : "轻量标签"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(GitMateTheme.textSecondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(shortSHA(tag.targetSHA ?? tag.objectSHA))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    tagStatus(tag)
                }
                .frame(width: 100, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(height: GitMateTheme.workspaceRowHeight)
            .background(
                selectedName == tag.name
                    ? GitMateTheme.selection.opacity(0.72)
                    : .white
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tagStatus(_ tag: GitTag) -> some View {
        switch tag.remoteStatus {
        case .localOnly:
            Text("仅本地")
                .foregroundStyle(GitMateTheme.warning)
        case .remoteOnly:
            Text("仅远端")
                .foregroundStyle(GitMateTheme.textSecondary)
        case .synchronized:
            Text("已同步")
                .foregroundStyle(GitMateTheme.success)
        }
    }
}

private struct NewTagSheet: View {
    let defaultTarget: String
    let onCancel: () -> Void
    let onCreate: (String, String, String?) -> Void

    @State private var name = ""
    @State private var target: String
    @State private var message = ""
    @State private var isAnnotated = true

    init(
        defaultTarget: String,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (String, String, String?) -> Void
    ) {
        self.defaultTarget = defaultTarget
        self.onCancel = onCancel
        self.onCreate = onCreate
        _target = State(initialValue: defaultTarget)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("新建标签")
                .font(.system(size: 20, weight: .bold))
            field("标签名称", placeholder: "v2.5.0", text: $name)
            field("目标提交或分支", placeholder: defaultTarget, text: $target)
            Toggle("创建附注标签", isOn: $isAnnotated)
            if isAnnotated {
                field("标签说明", placeholder: "版本说明", text: $message)
            }
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(GitMateButtonStyle(role: .secondary))
                Button("创建标签") {
                    onCreate(
                        name.trimmingCharacters(in: .whitespacesAndNewlines),
                        target.trimmingCharacters(in: .whitespacesAndNewlines),
                        isAnnotated
                            ? message.trimmingCharacters(in: .whitespacesAndNewlines)
                            : nil
                    )
                }
                .buttonStyle(GitMateButtonStyle(role: .primary))
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (isAnnotated
                            && message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                )
            }
        }
        .padding(26)
        .frame(width: 440)
    }

    private func field(
        _ title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
