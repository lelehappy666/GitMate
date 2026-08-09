import GitMateCore
import SwiftUI

struct BranchRulesView: View {
    @Bindable var viewModel: RepositoryWorkspaceViewModel
    @State private var searchText = ""
    @State private var selectedID: Int64?
    @State private var editorPresentation: RulesetEditorPresentation?

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            summary

            HStack(spacing: 12) {
                rulesetList
                    .frame(
                        minWidth: 380,
                        idealWidth: GitMateTheme.workspaceListWidth
                    )

                if let selectedRuleset {
                    RulesetDetailView(
                        ruleset: selectedRuleset,
                        viewModel: viewModel,
                        onEdit: {
                            editorPresentation = RulesetEditorPresentation(
                                ruleset: selectedRuleset
                            )
                        }
                    )
                } else {
                    WorkspaceEmptyView(
                        icon: "shield.lefthalf.filled",
                        title: "选择一组规则",
                        message: "查看适用范围、执行模式和分支保护要求。"
                    )
                    .workspacePanel()
                }
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            RulesetEditorSheet(
                ruleset: presentation.ruleset,
                onCancel: {
                    editorPresentation = nil
                },
                onSave: { input in
                    let original = presentation.ruleset
                    editorPresentation = nil
                    if let original,
                       input.weakensProtection(comparedTo: original) {
                        viewModel.requestUpdateRuleset(
                            original,
                            input: input
                        )
                    } else {
                        Task {
                            if let original {
                                await viewModel.updateRuleset(
                                    original,
                                    input: input
                                )
                            } else {
                                await viewModel.createRuleset(input)
                            }
                        }
                    }
                }
            )
        }
        .onChange(
            of: viewModel.state.rulesets.map(\.id),
            initial: true
        ) { _, identifiers in
            if selectedID == nil || !identifiers.contains(selectedID ?? -1) {
                selectedID = identifiers.first
            }
        }
    }

    private var filteredRulesets: [RepositoryRuleset] {
        guard !searchText.isEmpty else {
            return viewModel.state.rulesets
        }
        return viewModel.state.rulesets.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || sourceText(for: $0)
                    .localizedCaseInsensitiveContains(searchText)
                || $0.rules.contains {
                    ruleTitle($0.type)
                        .localizedCaseInsensitiveContains(searchText)
                }
        }
    }

    private var selectedRuleset: RepositoryRuleset? {
        viewModel.state.rulesets.first { $0.id == selectedID }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(GitMateTheme.textTertiary)
                TextField("搜索规则名称、来源或规则类型", text: $searchText)
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
                editorPresentation = RulesetEditorPresentation(
                    ruleset: nil
                )
            } label: {
                Label("新建规则", systemImage: "plus")
            }
            .buttonStyle(GitMateButtonStyle(role: .primary))
            .accessibilityIdentifier("workspace.rules.create")
        }
    }

    private var summary: some View {
        HStack(spacing: 0) {
            summaryItem(
                value: viewModel.state.rulesets.count,
                title: "全部规则集",
                color: GitMateTheme.textPrimary
            )
            summaryItem(
                value: viewModel.state.rulesets.filter {
                    $0.enforcement == .active
                }.count,
                title: "正在执行",
                color: GitMateTheme.success
            )
            summaryItem(
                value: viewModel.state.rulesets.filter {
                    $0.enforcement == .evaluate
                }.count,
                title: "评估模式",
                color: GitMateTheme.warning
            )
            summaryItem(
                value: viewModel.state.rulesets.filter {
                    !$0.isEditable
                }.count,
                title: "组织继承",
                color: .purple
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

    private var rulesetList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("规则集")
                Spacer()
                Text("状态")
                    .frame(width: 84, alignment: .leading)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(GitMateTheme.textTertiary)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(GitMateTheme.panel)

            Divider()

            if filteredRulesets.isEmpty {
                WorkspaceEmptyView(
                    icon: "shield.slash",
                    title: searchText.isEmpty ? "尚未配置规则" : "没有匹配结果",
                    message: "创建规则集，为重要分支设置合并与提交要求。"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredRulesets) { ruleset in
                            rulesetRow(ruleset)
                            Divider()
                                .padding(.leading, 14)
                        }
                    }
                }
            }
        }
        .workspacePanel()
    }

    private func rulesetRow(_ ruleset: RepositoryRuleset) -> some View {
        Button {
            selectedID = ruleset.id
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            selectedID == ruleset.id
                                ? GitMateTheme.accent
                                : GitMateTheme.accent.opacity(0.10)
                        )
                    Image(
                        systemName: ruleset.isEditable
                            ? "shield.checkered"
                            : "building.2.crop.circle"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        selectedID == ruleset.id
                            ? .white
                            : GitMateTheme.accent
                    )
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(ruleset.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GitMateTheme.textPrimary)
                        .lineLimit(1)
                    Text("\(sourceText(for: ruleset)) · \(ruleset.rules.count) 条规则")
                        .font(.system(size: 10))
                        .foregroundStyle(GitMateTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                WorkspaceStatusChip(
                    text: enforcementText(ruleset.enforcement),
                    color: enforcementColor(ruleset.enforcement)
                )
                .frame(width: 84, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(height: 64)
            .contentShape(Rectangle())
            .background(
                selectedID == ruleset.id
                    ? GitMateTheme.selection
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
    }
}

private struct RulesetEditorPresentation: Identifiable {
    let id = UUID()
    let ruleset: RepositoryRuleset?
}

struct RulesetEditorSheet: View {
    let ruleset: RepositoryRuleset?
    let onCancel: () -> Void
    let onSave: (RepositoryRulesetInput) -> Void

    @State private var name: String
    @State private var enforcement: RulesetEnforcement
    @State private var target: RulesetTarget
    @State private var includedRefs: String
    @State private var excludedRefs: String
    @State private var requiresPullRequest: Bool
    @State private var requiresLinearHistory: Bool
    @State private var requiresSignedCommits: Bool
    @State private var blocksForcePushes: Bool
    @State private var dismissesStaleReviews: Bool
    @State private var requiredApprovals: Int

    init(
        ruleset: RepositoryRuleset?,
        onCancel: @escaping () -> Void,
        onSave: @escaping (RepositoryRulesetInput) -> Void
    ) {
        self.ruleset = ruleset
        self.onCancel = onCancel
        self.onSave = onSave

        let pullRequestRule = ruleset?.rules.first {
            $0.type == "pull_request"
        }
        _name = State(initialValue: ruleset?.name ?? "")
        _enforcement = State(initialValue: ruleset?.enforcement ?? .active)
        _target = State(initialValue: ruleset?.target ?? .branch)
        _includedRefs = State(
            initialValue: (ruleset?.includedRefs ?? ["~DEFAULT_BRANCH"])
                .joined(separator: "\n")
        )
        _excludedRefs = State(
            initialValue: (ruleset?.excludedRefs ?? []).joined(separator: "\n")
        )
        _requiresPullRequest = State(
            initialValue: pullRequestRule != nil
        )
        _requiresLinearHistory = State(
            initialValue: ruleset?.rules.contains {
                $0.type == "required_linear_history"
            } ?? true
        )
        _requiresSignedCommits = State(
            initialValue: ruleset?.rules.contains {
                $0.type == "required_signatures"
            } ?? false
        )
        _blocksForcePushes = State(
            initialValue: ruleset?.rules.contains {
                $0.type == "non_fast_forward"
            } ?? true
        )
        _dismissesStaleReviews = State(
            initialValue: pullRequestRule?.parameters[
                "dismiss_stale_reviews_on_push"
            ] == .boolean(true)
        )
        if case let .integer(value)? = pullRequestRule?.parameters[
            "required_approving_review_count"
        ] {
            _requiredApprovals = State(initialValue: value)
        } else {
            _requiredApprovals = State(initialValue: 1)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ruleset == nil ? "新建规则集" : "编辑规则集")
                        .font(.system(size: 18, weight: .bold))
                    Text("设置规则的适用范围与仓库保护要求。")
                        .font(.system(size: 11))
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                Button("保存") {
                    onSave(input)
                }
                .buttonStyle(GitMateButtonStyle(role: .primary))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    editorSection("基础设置") {
                        LabeledContent("名称") {
                            TextField("例如：保护 main 分支", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 340)
                        }
                        LabeledContent("执行模式") {
                            Picker("", selection: $enforcement) {
                                Text("正在执行").tag(RulesetEnforcement.active)
                                Text("仅评估").tag(RulesetEnforcement.evaluate)
                                Text("已停用").tag(RulesetEnforcement.disabled)
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                        LabeledContent("目标") {
                            Picker("", selection: $target) {
                                Text("分支").tag(RulesetTarget.branch)
                                Text("标签").tag(RulesetTarget.tag)
                                Text("推送").tag(RulesetTarget.push)
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                    }

                    editorSection("适用范围") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("包含的引用")
                                .font(.system(size: 11, weight: .semibold))
                            TextEditor(text: $includedRefs)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(height: 74)
                                .padding(6)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(GitMateTheme.border)
                                }
                            Text("每行一个，例如 ~DEFAULT_BRANCH 或 refs/heads/release/*")
                                .font(.system(size: 10))
                                .foregroundStyle(GitMateTheme.textTertiary)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("排除的引用")
                                .font(.system(size: 11, weight: .semibold))
                            TextEditor(text: $excludedRefs)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(height: 58)
                                .padding(6)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(GitMateTheme.border)
                                }
                        }
                    }

                    editorSection("保护规则") {
                        Toggle("合并前必须通过拉取请求", isOn: $requiresPullRequest)
                        if requiresPullRequest {
                            Stepper(
                                "至少 \(requiredApprovals) 位批准者",
                                value: $requiredApprovals,
                                in: 1...10
                            )
                            .padding(.leading, 22)
                            Toggle(
                                "有新提交时撤销旧批准",
                                isOn: $dismissesStaleReviews
                            )
                            .padding(.leading, 22)
                        }
                        Toggle("要求线性提交历史", isOn: $requiresLinearHistory)
                        Toggle("要求签名提交", isOn: $requiresSignedCommits)
                        Toggle("阻止强制推送", isOn: $blocksForcePushes)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 620, height: 660)
        .background(.white)
    }

    private var input: RepositoryRulesetInput {
        var rules: [RepositoryRule] = []
        if requiresPullRequest {
            var parameters: [String: GitHubJSONValue] = [
                "required_approving_review_count":
                    .integer(requiredApprovals),
                "dismiss_stale_reviews_on_push":
                    .boolean(dismissesStaleReviews)
            ]
            if ruleset == nil {
                parameters["require_code_owner_review"] = .boolean(false)
                parameters["require_last_push_approval"] = .boolean(false)
                parameters["required_review_thread_resolution"] =
                    .boolean(true)
            }
            rules.append(
                RepositoryRule(
                    type: "pull_request",
                    parameters: parameters
                )
            )
        }
        if requiresLinearHistory {
            rules.append(RepositoryRule(type: "required_linear_history"))
        }
        if requiresSignedCommits {
            rules.append(RepositoryRule(type: "required_signatures"))
        }
        if blocksForcePushes {
            rules.append(RepositoryRule(type: "non_fast_forward"))
        }

        return RepositoryRulesetInput.preservingUneditedConfiguration(
            from: ruleset,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            enforcement: enforcement,
            target: target,
            includedRefs: parsedRefs(includedRefs),
            excludedRefs: parsedRefs(excludedRefs),
            editableRules: rules,
            editableRuleTypes: [
                "pull_request",
                "required_linear_history",
                "required_signatures",
                "non_fast_forward"
            ]
        )
    }

    private func editorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitMateTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func parsedRefs(_ value: String) -> [String] {
        value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

func enforcementText(_ enforcement: RulesetEnforcement) -> String {
    switch enforcement {
    case .active:
        "执行中"
    case .evaluate:
        "评估中"
    case .disabled:
        "已停用"
    }
}

func enforcementColor(_ enforcement: RulesetEnforcement) -> Color {
    switch enforcement {
    case .active:
        GitMateTheme.success
    case .evaluate:
        GitMateTheme.warning
    case .disabled:
        GitMateTheme.textTertiary
    }
}

func sourceText(for ruleset: RepositoryRuleset) -> String {
    switch ruleset.source {
    case .repository:
        "当前仓库"
    case let .organization(login):
        "组织 \(login)"
    }
}

func ruleTitle(_ type: String) -> String {
    switch type {
    case "pull_request":
        "必须通过拉取请求"
    case "required_linear_history":
        "要求线性提交历史"
    case "required_signatures":
        "要求签名提交"
    case "non_fast_forward":
        "阻止强制推送"
    case "deletion":
        "阻止删除引用"
    case "creation":
        "限制创建引用"
    case "update":
        "限制更新引用"
    case "required_status_checks":
        "要求状态检查"
    case "code_scanning":
        "要求代码扫描"
    default:
        type.replacingOccurrences(of: "_", with: " ")
    }
}
