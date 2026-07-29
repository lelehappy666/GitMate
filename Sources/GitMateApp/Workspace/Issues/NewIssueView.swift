import GitMateCore
import SwiftUI

struct NewIssueView: View {
    @Bindable var viewModel: RepositoryWorkspaceViewModel
    @State private var draft = IssueDraft(title: "", body: "")
    @State private var selectedTab = "write"
    @State private var assigneesText = ""
    @State private var loadedDraft = false
    @State private var draftSaveTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 12) {
            toolbar

            HStack(alignment: .top, spacing: 12) {
                editor
                publishingPanel
                    .frame(width: 274)
            }
        }
        .onChange(
            of: viewModel.state.issueDraft,
            initial: true
        ) { _, storedDraft in
            guard !loadedDraft, let storedDraft else {
                return
            }
            draft = storedDraft
            assigneesText = storedDraft.assigneeLogins.joined(separator: ", ")
            loadedDraft = true
        }
        .onChange(of: draft) { _, value in
            draftSaveTask?.cancel()
            draftSaveTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(500))
                    try Task.checkCancellation()
                    viewModel.saveDraft(value)
                } catch {}
            }
        }
        .onDisappear {
            draftSaveTask?.cancel()
        }
    }

    private var toolbar: some View {
        HStack {
            Button {
                viewModel.navigate(to: .issues)
            } label: {
                Label("返回议题", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)

            Spacer()

            if viewModel.state.issueDraft != nil {
                Label("草稿已保存在本机", systemImage: "checkmark.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GitMateTheme.success)
            }

            Button("发布议题") {
                publish()
            }
            .buttonStyle(GitMateButtonStyle(role: .primary))
            .disabled(
                draft.title
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            )
            .accessibilityIdentifier("workspace.issue.publish.top")
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("议题内容")
                        .font(.system(size: 13, weight: .bold))
                    Text("支持 GitHub Flavored Markdown")
                        .font(.system(size: 9))
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
                Spacer()
                Picker("", selection: $selectedTab) {
                    Text("编写").tag("write")
                    Text("预览").tag("preview")
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            .padding(14)

            Divider()

            VStack(spacing: 12) {
                TextField("议题标题", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(GitMateTheme.border)
                    }

                if selectedTab == "write" {
                    TextEditor(text: $draft.body)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(GitMateTheme.border)
                        }
                } else {
                    ScrollView {
                        if draft.body.isEmpty {
                            WorkspaceEmptyView(
                                icon: "doc.richtext",
                                title: "暂无可预览内容",
                                message: "切换到编写页签并输入 Markdown。"
                            )
                        } else {
                            IssueMarkdownView(markdown: draft.body)
                                .padding(16)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(GitMateTheme.border)
                    }
                }

                HStack {
                    Menu {
                        Button("错误报告") {
                            applyTemplate(
                                name: "错误报告",
                                body: """
                                ## 问题描述


                                ## 复现步骤
                                1.

                                ## 预期结果


                                ## 环境信息
                                """
                            )
                        }
                        Button("功能建议") {
                            applyTemplate(
                                name: "功能建议",
                                body: """
                                ## 使用场景


                                ## 建议方案


                                ## 补充说明
                                """
                            )
                        }
                        Button("清空模板") {
                            draft.templateName = nil
                            draft.body = ""
                        }
                    } label: {
                        Label(
                            draft.templateName ?? "选择模板",
                            systemImage: "doc.text"
                        )
                    }
                    .menuStyle(.borderlessButton)
                    Spacer()
                    Text("\(draft.body.count) 个字符")
                        .font(.system(size: 9))
                        .foregroundStyle(GitMateTheme.textTertiary)
                }
            }
            .padding(14)
            .frame(maxHeight: .infinity)
        }
        .workspacePanel()
    }

    private var publishingPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    panelSection("负责人", icon: "person.2") {
                        TextField(
                            "GitHub 用户名，逗号分隔",
                            text: $assigneesText
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onChange(of: assigneesText) { _, value in
                            draft.assigneeLogins = parsedList(value)
                        }
                    }

                    panelSection("标签", icon: "tag") {
                        if viewModel.state.labels.isEmpty {
                            Text("仓库没有可用标签")
                                .font(.system(size: 10))
                                .foregroundStyle(GitMateTheme.textTertiary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(viewModel.state.labels) { label in
                                    Toggle(
                                        isOn: Binding(
                                            get: {
                                                draft.labelNames
                                                    .contains(label.name)
                                            },
                                            set: { selected in
                                                setLabel(
                                                    label.name,
                                                    selected: selected
                                                )
                                            }
                                        )
                                    ) {
                                        IssueLabelChip(label: label)
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }
                    }

                    panelSection("里程碑", icon: "signpost.right") {
                        Picker(
                            "",
                            selection: Binding(
                                get: { draft.milestoneNumber ?? -1 },
                                set: {
                                    draft.milestoneNumber =
                                        $0 == -1 ? nil : $0
                                }
                            )
                        ) {
                            Text("无里程碑").tag(-1)
                            ForEach(viewModel.state.milestones) { milestone in
                                Text(milestone.title).tag(milestone.number)
                            }
                        }
                        .labelsHidden()
                    }

                    panelSection("发布检查", icon: "checkmark.seal") {
                        checklistRow(
                            "标题",
                            complete: !draft.title
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                .isEmpty
                        )
                        checklistRow(
                            "正文",
                            complete: !draft.body
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                .isEmpty
                        )
                        checklistRow(
                            "分类标签",
                            complete: !draft.labelNames.isEmpty
                        )
                    }
                }
                .padding(15)
            }

            Divider()

            Button("发布议题") {
                publish()
            }
            .buttonStyle(GitMateButtonStyle(role: .primary))
            .frame(maxWidth: .infinity)
            .padding(14)
            .disabled(
                draft.title
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            )
            .accessibilityIdentifier("workspace.issue.publish")
        }
        .frame(maxHeight: .infinity)
        .workspacePanel()
    }

    private func panelSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .bold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func checklistRow(_ text: String, complete: Bool) -> some View {
        HStack(spacing: 8) {
            Image(
                systemName: complete
                    ? "checkmark.circle.fill"
                    : "circle"
            )
            .foregroundStyle(
                complete ? GitMateTheme.success : GitMateTheme.textTertiary
            )
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
    }

    private func setLabel(_ name: String, selected: Bool) {
        if selected {
            if !draft.labelNames.contains(name) {
                draft.labelNames.append(name)
            }
        } else {
            draft.labelNames.removeAll { $0 == name }
        }
    }

    private func parsedList(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func applyTemplate(name: String, body: String) {
        draft.templateName = name
        if draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.body = body
        } else {
            draft.body += "\n\n---\n\n" + body
        }
    }

    private func publish() {
        draft.assigneeLogins = parsedList(assigneesText)
        viewModel.saveDraft(draft)
        Task {
            await viewModel.publishIssue(
                CreateIssueInput(
                    title: draft.title
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    body: draft.body.isEmpty ? nil : draft.body,
                    assigneeLogins: draft.assigneeLogins,
                    labelNames: draft.labelNames,
                    milestoneNumber: draft.milestoneNumber
                )
            )
        }
    }
}
