struct RulesetPayload: Decodable {
    struct Conditions: Decodable {
        struct ReferenceName: Decodable {
            let include: [String]
            let exclude: [String]
        }

        let referenceName: ReferenceName?

        private enum CodingKeys: String, CodingKey {
            case referenceName = "ref_name"
        }
    }

    struct Rule: Decodable {
        let type: String
        let parameters: [String: GitHubJSONValue]?
    }

    struct BypassActor: Decodable {
        let actorID: Int64?
        let actorType: String?
        let bypassMode: String?

        private enum CodingKeys: String, CodingKey {
            case actorID = "actor_id"
            case actorType = "actor_type"
            case bypassMode = "bypass_mode"
        }
    }

    let id: Int64
    let name: String
    let target: String
    let sourceType: String
    let source: String
    let enforcement: String
    let conditions: Conditions?
    let rules: [Rule]?
    let bypassActors: [BypassActor]?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case target
        case sourceType = "source_type"
        case source
        case enforcement
        case conditions
        case rules
        case bypassActors = "bypass_actors"
    }

    var model: RepositoryRuleset {
        let sourceModel: RulesetSource = sourceType == "Organization"
            ? .organization(login: source)
            : .repository
        return RepositoryRuleset(
            id: id,
            name: name,
            enforcement: RulesetEnforcement(rawValue: enforcement) ?? .disabled,
            source: sourceModel,
            target: RulesetTarget(rawValue: target) ?? .branch,
            includedRefs: conditions?.referenceName?.include ?? [],
            excludedRefs: conditions?.referenceName?.exclude ?? [],
            rules: (rules ?? []).map {
                RepositoryRule(
                    type: $0.type,
                    parameters: $0.parameters ?? [:]
                )
            },
            bypassActors: (bypassActors ?? []).map { actor in
                let type = actor.actorType ?? "未知"
                let identifier = actor.actorID.map(String.init) ?? "未知"
                let mode = actor.bypassMode ?? "always"
                return "\(type):\(identifier):\(mode)"
            }
        )
    }
}

struct RulesetRequestPayload: Encodable {
    struct Conditions: Encodable {
        struct ReferenceName: Encodable {
            let include: [String]
            let exclude: [String]
        }

        let referenceName: ReferenceName

        private enum CodingKeys: String, CodingKey {
            case referenceName = "ref_name"
        }
    }

    struct Rule: Encodable {
        let type: String
        let parameters: [String: GitHubJSONValue]?
    }

    let name: String
    let enforcement: String
    let target: String
    let bypassActors: [RulesetBypassActorInput]
    let conditions: Conditions
    let rules: [Rule]

    private enum CodingKeys: String, CodingKey {
        case name
        case enforcement
        case target
        case bypassActors = "bypass_actors"
        case conditions
        case rules
    }

    init(input: RepositoryRulesetInput) {
        name = input.name
        enforcement = input.enforcement.rawValue
        target = input.target.rawValue
        bypassActors = input.bypassActors
        conditions = Conditions(
            referenceName: .init(
                include: input.includedRefs,
                exclude: input.excludedRefs
            )
        )
        rules = input.rules.map {
            Rule(
                type: $0.type,
                parameters: $0.parameters.isEmpty ? nil : $0.parameters
            )
        }
    }
}
