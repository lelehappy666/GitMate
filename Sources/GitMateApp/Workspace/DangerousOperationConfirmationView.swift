import GitMateCore
import SwiftUI

struct DangerousOperationConfirmationView: View {
    let request: DangerousOperationRequest
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 25))
                    .foregroundStyle(GitMateTheme.danger)
                VStack(alignment: .leading, spacing: 4) {
                    Text("确认危险操作")
                        .font(.system(size: 20, weight: .bold))
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }
            }

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(GitMateTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(
                        GitMateButtonStyle(role: .secondary)
                    )
                Button("确认执行", action: onConfirm)
                    .buttonStyle(
                        GitMateButtonStyle(role: .destructive)
                    )
                    .accessibilityIdentifier("workspace.danger.confirm")
            }
        }
        .padding(28)
        .frame(width: 460)
        .background(.white)
    }

    private var title: String {
        switch request.action {
        case let .deleteLocalBranch(name, _):
            "删除本地分支 \(name)"
        case let .deleteRemoteBranch(remote, name):
            "删除 \(remote)/\(name)"
        case let .deleteTag(name, _):
            "删除标签 \(name)"
        case let .deleteRuleset(_, name):
            "删除规则 \(name)"
        case let .updateRuleset(current, _):
            "降低规则 \(current.name) 的保护"
        case let .deleteMilestone(number, _):
            "删除里程碑 #\(number)"
        case let .deleteLabel(name, _):
            "删除标签 \(name)"
        case let .mergeLabels(source, target, _):
            "将 \(source) 合并到 \(target)"
        }
    }

    private var message: String {
        switch request.action {
        case let .deleteLocalBranch(_, force):
            return force
                ? "该分支将被强制删除，即使其中仍有未合并提交。此操作无法自动恢复。"
                : "Git 会拒绝删除尚未合并的分支。删除成功后仍可从远端重新签出。"
        case .deleteRemoteBranch:
            return "远端引用会立即删除，并影响所有协作者。已有本地副本不会自动删除。"
        case let .deleteTag(_, remote):
            return remote == nil
                ? "只删除本地标签，不影响 GitHub 上的同名标签。"
                : "远端版本标签会被删除，相关 Release 不会自动删除。"
        case .deleteRuleset:
            return "受保护分支可能立即失去合并、签名或状态检查限制。"
        case let .updateRuleset(current, input):
            let references = current.includedRefs.isEmpty
                ? "当前规则覆盖的引用"
                : current.includedRefs.joined(separator: "、")
            return "保存后 \(references) 的保护要求会降低，执行模式将变为"
                + "\(enforcementText(input.enforcement))。请确认这是有意修改。"
        case let .deleteMilestone(_, affectedIssues):
            return "该里程碑关联 \(affectedIssues) 个议题，删除后这些议题将不再归属此版本。"
        case let .deleteLabel(_, affectedIssues):
            return "该标签用于 \(affectedIssues) 个议题，删除后会从所有议题中移除。"
        case let .mergeLabels(_, _, affectedIssues):
            return "将依次更新 \(affectedIssues) 个议题。失败项会保留进度，全部成功后才删除来源标签。"
        }
    }
}
