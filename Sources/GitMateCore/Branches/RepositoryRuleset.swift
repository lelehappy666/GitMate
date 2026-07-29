public enum RulesetEnforcement: String, Codable, Sendable {
    case active
    case evaluate
    case disabled
}

public enum RulesetSource: Equatable, Codable, Sendable {
    case repository
    case organization(login: String)
}

public enum RulesetTarget: String, Codable, Sendable {
    case branch
    case tag
    case push
}

public struct RepositoryRule: Identifiable, Equatable, Codable, Sendable {
    public var id: String { type }

    public let type: String
    public let summary: String?

    public init(type: String, summary: String? = nil) {
        self.type = type
        self.summary = summary
    }
}

public struct RepositoryRuleset: Identifiable, Equatable, Codable, Sendable {
    public let id: Int64
    public var name: String
    public var enforcement: RulesetEnforcement
    public let source: RulesetSource
    public var target: RulesetTarget
    public var includedRefs: [String]
    public var excludedRefs: [String]
    public var rules: [RepositoryRule]
    public var bypassActors: [String]

    public init(
        id: Int64,
        name: String,
        enforcement: RulesetEnforcement,
        source: RulesetSource,
        target: RulesetTarget = .branch,
        includedRefs: [String] = [],
        excludedRefs: [String] = [],
        rules: [RepositoryRule] = [],
        bypassActors: [String] = []
    ) {
        self.id = id
        self.name = name
        self.enforcement = enforcement
        self.source = source
        self.target = target
        self.includedRefs = includedRefs
        self.excludedRefs = excludedRefs
        self.rules = rules
        self.bypassActors = bypassActors
    }

    public var isEditable: Bool {
        if case .repository = source {
            return true
        }
        return false
    }
}
