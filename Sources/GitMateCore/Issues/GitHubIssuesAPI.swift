import Foundation

public struct CreateIssueInput: Equatable, Codable, Sendable {
    public var title: String
    public var body: String?
    public var assigneeLogins: [String]
    public var labelNames: [String]
    public var milestoneNumber: Int?

    public init(
        title: String,
        body: String?,
        assigneeLogins: [String] = [],
        labelNames: [String] = [],
        milestoneNumber: Int? = nil
    ) {
        self.title = title
        self.body = body
        self.assigneeLogins = assigneeLogins
        self.labelNames = labelNames
        self.milestoneNumber = milestoneNumber
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case body
        case assigneeLogins = "assignees"
        case labelNames = "labels"
        case milestoneNumber = "milestone"
    }
}

public struct UpdateIssueInput: Equatable, Encodable, Sendable {
    public var title: String
    public var body: String
    public var state: IssueState
    public var assigneeLogins: [String]
    public var labelNames: [String]
    public var milestoneNumber: Int?

    public init(
        title: String,
        body: String,
        state: IssueState,
        assigneeLogins: [String],
        labelNames: [String],
        milestoneNumber: Int?
    ) {
        self.title = title
        self.body = body
        self.state = state
        self.assigneeLogins = assigneeLogins
        self.labelNames = labelNames
        self.milestoneNumber = milestoneNumber
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case body
        case state
        case assigneeLogins = "assignees"
        case labelNames = "labels"
        case milestoneNumber = "milestone"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encode(state, forKey: .state)
        try container.encode(assigneeLogins, forKey: .assigneeLogins)
        try container.encode(labelNames, forKey: .labelNames)
        if let milestoneNumber {
            try container.encode(milestoneNumber, forKey: .milestoneNumber)
        } else {
            try container.encodeNil(forKey: .milestoneNumber)
        }
    }
}

public enum IssueLockReason: String, Codable, Sendable {
    case offTopic = "off-topic"
    case tooHeated = "too heated"
    case resolved
    case spam
}

public struct MilestoneInput: Equatable, Encodable, Sendable {
    public var title: String
    public var description: String?
    public var state: IssueState
    public var dueOn: Date?

    public init(
        title: String,
        description: String?,
        state: IssueState,
        dueOn: Date?
    ) {
        self.title = title
        self.description = description
        self.state = state
        self.dueOn = dueOn
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case description
        case state
        case dueOn = "due_on"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(state, forKey: .state)
        if let dueOn {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            try container.encode(formatter.string(from: dueOn), forKey: .dueOn)
        } else {
            try container.encodeNil(forKey: .dueOn)
        }
    }
}

public struct IssueLabelInput: Equatable, Codable, Sendable {
    public var name: String
    public var color: String
    public var description: String?

    public init(name: String, color: String, description: String?) {
        self.name = name
        self.color = IssueLabel(
            id: 0,
            name: name,
            color: color
        ).normalizedColorHex
        self.description = description
    }
}

public protocol GitHubIssuesAPI: Sendable {
    func issues(
        query: IssueQuery,
        pageURL: URL?,
        token: String
    ) async throws -> GitHubPage<GitHubIssue>
    func issue(number: Int, token: String) async throws -> GitHubIssue
    func timeline(number: Int, token: String) async throws -> [IssueTimelineEvent]
    func comments(number: Int, token: String) async throws -> [IssueComment]
    func createIssue(
        _ input: CreateIssueInput,
        token: String
    ) async throws -> GitHubIssue
    func updateIssue(
        number: Int,
        input: UpdateIssueInput,
        token: String
    ) async throws -> GitHubIssue
    func createComment(
        number: Int,
        body: String,
        token: String
    ) async throws -> IssueComment
    func updateComment(
        id: Int64,
        body: String,
        token: String
    ) async throws -> IssueComment
    func lockIssue(
        number: Int,
        reason: IssueLockReason?,
        token: String
    ) async throws
    func unlockIssue(number: Int, token: String) async throws
    func milestones(
        state: IssueState?,
        token: String
    ) async throws -> [IssueMilestone]
    func createMilestone(
        _ input: MilestoneInput,
        token: String
    ) async throws -> IssueMilestone
    func updateMilestone(
        number: Int,
        input: MilestoneInput,
        token: String
    ) async throws -> IssueMilestone
    func deleteMilestone(number: Int, token: String) async throws
    func labels(token: String) async throws -> [IssueLabel]
    func createLabel(
        _ input: IssueLabelInput,
        token: String
    ) async throws -> IssueLabel
    func updateLabel(
        name: String,
        input: IssueLabelInput,
        token: String
    ) async throws -> IssueLabel
    func deleteLabel(name: String, token: String) async throws
}
