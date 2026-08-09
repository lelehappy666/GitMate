import GitMateCore
import SwiftUI

struct RulesetDetailView: View {
    let ruleset: RepositoryRuleset
    @Bindable var viewModel: RepositoryWorkspaceViewModel
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    scopeSection
                    rulesSection
                    bypassSection
                }
                .padding(18)
            }
            Divider()
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .workspacePanel()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        ruleset.isEditable
                            ? GitMateTheme.accent.opacity(0.10)
                            : Color.purple.opacity(0.10)
                    )
                Image(
                    systemName: ruleset.isEditable
                        ? "shield.checkered"
                        : "building.2.crop.circle.fill"
                )
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    ruleset.isEditable ? GitMateTheme.accent : .purple
                )
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(ruleset.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(GitMateTheme.textPrimary)
                    WorkspaceStatusChip(
                        text: enforcementText(ruleset.enforcement),
                        color: enforcementColor(ruleset.enforcement)
                    )
                }
                Text(
                    ruleset.isEditable
                        ? "由当前仓库管理，可直接修改。"
                        : "\(sourceText(for: ruleset))继承，只能在组织设置中修改。"
                )
                .font(.system(size: 11))
                .foregroundStyle(GitMateTheme.textSecondary)
            }

            Spacer()

            if !ruleset.isEditable {
                Label("只读", systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.purple.opacity(0.10))
                    .clipShape(Capsule())
            }
        }
        .padding(18)
    }

    private var scopeSection: some View {
        detailSection(title: "适用范围", icon: "scope") {
            detailRow("目标", value: targetText)
            detailRow(
                "包含",
                value: ruleset.includedRefs.isEmpty
                    ? "未指定"
                    : ruleset.includedRefs.joined(separator: "、")
            )
            detailRow(
                "排除",
                value: ruleset.excludedRefs.isEmpty
                    ? "无"
                    : ruleset.excludedRefs.joined(separator: "、")
            )
        }
    }

    private var rulesSection: some View {
        detailSection(title: "保护规则", icon: "checklist") {
            if ruleset.rules.isEmpty {
                Text("当前规则集没有保护要求。")
                    .font(.system(size: 11))
                    .foregroundStyle(GitMateTheme.textSecondary)
            } else {
                ForEach(ruleset.rules) { rule in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(GitMateTheme.success)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ruleTitle(rule.type))
                                .font(.system(size: 12, weight: .semibold))
                            if let description = ruleDescription(rule) {
                                Text(description)
                                    .font(.system(size: 10))
                                    .foregroundStyle(
                                        GitMateTheme.textSecondary
                                    )
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var bypassSection: some View {
        detailSection(title: "绕过权限", icon: "person.badge.key") {
            Text(
                ruleset.bypassActors.isEmpty
                    ? "没有用户或团队可以绕过此规则集。"
                    : ruleset.bypassActors
                        .map(\.displayText)
                        .joined(separator: "、")
            )
            .font(.system(size: 11))
            .foregroundStyle(GitMateTheme.textSecondary)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if ruleset.isEditable {
                Button(role: .destructive) {
                    viewModel.requestDeleteRuleset(ruleset)
                } label: {
                    Label("删除规则集", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button {
                onEdit()
            } label: {
                Label(
                    ruleset.isEditable ? "编辑规则集" : "组织规则只读",
                    systemImage: ruleset.isEditable ? "pencil" : "lock"
                )
            }
            .buttonStyle(
                GitMateButtonStyle(
                    role: ruleset.isEditable ? .primary : .secondary
                )
            )
            .disabled(!ruleset.isEditable)
        }
        .padding(14)
    }

    private var targetText: String {
        switch ruleset.target {
        case .branch:
            "分支"
        case .tag:
            "标签"
        case .push:
            "推送"
        }
    }

    private func detailSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(GitMateTheme.textPrimary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitMateTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(GitMateTheme.textTertiary)
                .frame(width: 46, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(GitMateTheme.textPrimary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func ruleDescription(_ rule: RepositoryRule) -> String? {
        switch rule.type {
        case "pull_request":
            if case let .integer(count)? = rule.parameters[
                "required_approving_review_count"
            ] {
                return "至少需要 \(count) 位批准者"
            }
            return "所有变更必须先经过审查"
        case "required_status_checks":
            return "合并前需要通过指定的持续集成检查"
        case "code_scanning":
            return "代码扫描结果必须符合设定阈值"
        default:
            return rule.summary
        }
    }
}
