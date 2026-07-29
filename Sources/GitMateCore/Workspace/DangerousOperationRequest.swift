import Foundation

public struct DangerousOperationRequest: Identifiable, Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case deleteLocalBranch(name: String, force: Bool)
        case deleteRemoteBranch(remote: String, name: String)
        case deleteTag(name: String, remote: String?)
        case deleteRuleset(id: Int64, name: String)
        case updateRuleset(
            current: RepositoryRuleset,
            input: RepositoryRulesetInput
        )
        case deleteMilestone(number: Int, affectedIssues: Int)
        case deleteLabel(name: String, affectedIssues: Int)
        case mergeLabels(source: String, target: String, affectedIssues: Int)
    }

    public let id: UUID
    public let action: Action

    public init(id: UUID = UUID(), action: Action) {
        self.id = id
        self.action = action
    }
}
