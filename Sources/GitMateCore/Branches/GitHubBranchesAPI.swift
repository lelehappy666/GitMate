import Foundation

public struct BranchProtectionSummary: Equatable, Codable, Sendable {
    public let requiredApprovingReviews: Int
    public let requiredStatusChecks: [String]
    public let requiresStrictStatusChecks: Bool
    public let dismissesStaleReviews: Bool
    public let requiresCodeOwnerReview: Bool
    public let enforcesAdmins: Bool
    public let hasPushRestrictions: Bool

    public init(
        requiredApprovingReviews: Int,
        requiredStatusChecks: [String],
        requiresStrictStatusChecks: Bool,
        dismissesStaleReviews: Bool,
        requiresCodeOwnerReview: Bool,
        enforcesAdmins: Bool,
        hasPushRestrictions: Bool
    ) {
        self.requiredApprovingReviews = requiredApprovingReviews
        self.requiredStatusChecks = requiredStatusChecks
        self.requiresStrictStatusChecks = requiresStrictStatusChecks
        self.dismissesStaleReviews = dismissesStaleReviews
        self.requiresCodeOwnerReview = requiresCodeOwnerReview
        self.enforcesAdmins = enforcesAdmins
        self.hasPushRestrictions = hasPushRestrictions
    }
}

public struct TagReleaseSummary: Identifiable, Equatable, Codable, Sendable {
    public let id: Int64
    public let tagName: String
    public let name: String?
    public let isDraft: Bool
    public let isPrerelease: Bool
    public let publishedAt: Date?
    public let webURL: URL

    public init(
        id: Int64,
        tagName: String,
        name: String?,
        isDraft: Bool,
        isPrerelease: Bool,
        publishedAt: Date?,
        webURL: URL
    ) {
        self.id = id
        self.tagName = tagName
        self.name = name
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
        self.publishedAt = publishedAt
        self.webURL = webURL
    }
}

public struct RulesetBypassActorInput: Equatable, Codable, Sendable {
    public let actorID: Int64
    public let actorType: String
    public let bypassMode: String

    public init(actorID: Int64, actorType: String, bypassMode: String) {
        self.actorID = actorID
        self.actorType = actorType
        self.bypassMode = bypassMode
    }

    private enum CodingKeys: String, CodingKey {
        case actorID = "actor_id"
        case actorType = "actor_type"
        case bypassMode = "bypass_mode"
    }

    public var displayText: String {
        "\(actorType):\(actorID):\(bypassMode)"
    }
}

public struct RepositoryRulesetInput: Equatable, Sendable {
    public var name: String
    public var enforcement: RulesetEnforcement
    public var target: RulesetTarget
    public var includedRefs: [String]
    public var excludedRefs: [String]
    public var rules: [RepositoryRule]
    public var bypassActors: [RulesetBypassActorInput]

    public init(
        name: String,
        enforcement: RulesetEnforcement,
        target: RulesetTarget,
        includedRefs: [String] = [],
        excludedRefs: [String] = [],
        rules: [RepositoryRule] = [],
        bypassActors: [RulesetBypassActorInput] = []
    ) {
        self.name = name
        self.enforcement = enforcement
        self.target = target
        self.includedRefs = includedRefs
        self.excludedRefs = excludedRefs
        self.rules = rules
        self.bypassActors = bypassActors
    }

    public static func preservingUneditedConfiguration(
        from original: RepositoryRuleset?,
        name: String,
        enforcement: RulesetEnforcement,
        target: RulesetTarget,
        includedRefs: [String],
        excludedRefs: [String],
        editableRules: [RepositoryRule],
        editableRuleTypes: Set<String>
    ) -> RepositoryRulesetInput {
        let retainedRules = (original?.rules ?? []).filter {
            !editableRuleTypes.contains($0.type)
        }
        let mergedEditableRules = editableRules.map { edited in
            guard let existing = original?.rules.first(where: {
                $0.type == edited.type
            }) else {
                return edited
            }
            var parameters = existing.parameters
            parameters.merge(edited.parameters) { _, editedValue in
                editedValue
            }
            return RepositoryRule(
                type: edited.type,
                summary: existing.summary,
                parameters: parameters
            )
        }
        return RepositoryRulesetInput(
            name: name,
            enforcement: enforcement,
            target: target,
            includedRefs: includedRefs,
            excludedRefs: excludedRefs,
            rules: retainedRules + mergedEditableRules,
            bypassActors: original?.bypassActors ?? []
        )
    }

    public func weakensProtection(
        comparedTo original: RepositoryRuleset
    ) -> Bool {
        let enforcementRank: [RulesetEnforcement: Int] = [
            .disabled: 0,
            .evaluate: 1,
            .active: 2
        ]
        if
            enforcementRank[enforcement, default: 0]
                < enforcementRank[original.enforcement, default: 0]
        {
            return true
        }
        if
            target != original.target
                || includedRefs != original.includedRefs
                || excludedRefs != original.excludedRefs
                || bypassActors != original.bypassActors
        {
            return true
        }

        let updatedByType = Dictionary(
            uniqueKeysWithValues: rules.map { ($0.type, $0) }
        )
        for originalRule in original.rules {
            guard let updated = updatedByType[originalRule.type] else {
                return true
            }
            for (key, oldValue) in originalRule.parameters {
                guard let newValue = updated.parameters[key] else {
                    return true
                }
                switch (oldValue, newValue) {
                case let (.integer(old), .integer(new)) where new < old:
                    return true
                case (.boolean(true), .boolean(false)):
                    return true
                default:
                    continue
                }
            }
        }
        return false
    }
}

public enum RulesetOperationError: Error, Equatable, Sendable {
    case inheritedRulesetIsReadOnly
}

extension RulesetOperationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .inheritedRulesetIsReadOnly:
            "该规则继承自组织，只能在组织设置中修改。"
        }
    }
}

public protocol GitHubBranchesAPI: Sendable {
    func remoteBranches(token: String) async throws -> [GitBranch]
    func remoteTags(token: String) async throws -> [GitTag]
    func branchProtection(
        name: String,
        token: String
    ) async throws -> BranchProtectionSummary?
    func rulesets(token: String) async throws -> [RepositoryRuleset]
    func ruleset(id: Int64, token: String) async throws -> RepositoryRuleset
    func createRuleset(
        _ input: RepositoryRulesetInput,
        token: String
    ) async throws -> RepositoryRuleset
    func updateRuleset(
        _ ruleset: RepositoryRuleset,
        input: RepositoryRulesetInput,
        token: String
    ) async throws -> RepositoryRuleset
    func deleteRuleset(
        _ ruleset: RepositoryRuleset,
        token: String
    ) async throws
    func tagReleaseSummary(
        name: String,
        token: String
    ) async throws -> TagReleaseSummary?
}
