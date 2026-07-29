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
