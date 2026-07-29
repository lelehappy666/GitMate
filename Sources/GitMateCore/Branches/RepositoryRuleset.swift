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

public enum GitHubJSONValue: Equatable, Codable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case array([GitHubJSONValue])
    case object([String: GitHubJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([GitHubJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: GitHubJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .boolean(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct RepositoryRule: Identifiable, Equatable, Codable, Sendable {
    public var id: String { type }

    public let type: String
    public let summary: String?
    public let parameters: [String: GitHubJSONValue]

    public init(
        type: String,
        summary: String? = nil,
        parameters: [String: GitHubJSONValue] = [:]
    ) {
        self.type = type
        self.summary = summary
        self.parameters = parameters
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
