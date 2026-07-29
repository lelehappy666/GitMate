import Foundation

public enum IssueState: String, Codable, Sendable {
    case open
    case closed
}

public struct IssueUser: Identifiable, Equatable, Codable, Sendable {
    public var id: String { login }

    public let databaseID: Int64?
    public let login: String
    public let name: String?
    public let avatarURL: URL?
    public let webURL: URL?

    public init(
        databaseID: Int64? = nil,
        login: String,
        name: String? = nil,
        avatarURL: URL? = nil,
        webURL: URL? = nil
    ) {
        self.databaseID = databaseID
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
        self.webURL = webURL
    }
}

public struct GitHubIssue: Identifiable, Equatable, Codable, Sendable {
    public let id: Int64
    public let number: Int
    public var title: String
    public var body: String?
    public var state: IssueState
    public let author: IssueUser
    public var assignees: [IssueUser]
    public var labels: [IssueLabel]
    public var milestone: IssueMilestone?
    public var commentsCount: Int
    public var isLocked: Bool
    public let createdAt: Date
    public var updatedAt: Date
    public var closedAt: Date?
    public let webURL: URL?

    public init(
        id: Int64,
        number: Int,
        title: String,
        body: String?,
        state: IssueState,
        author: IssueUser,
        assignees: [IssueUser] = [],
        labels: [IssueLabel] = [],
        milestone: IssueMilestone? = nil,
        commentsCount: Int = 0,
        isLocked: Bool = false,
        createdAt: Date = .distantPast,
        updatedAt: Date = .distantPast,
        closedAt: Date? = nil,
        webURL: URL? = nil
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.body = body
        self.state = state
        self.author = author
        self.assignees = assignees
        self.labels = labels
        self.milestone = milestone
        self.commentsCount = commentsCount
        self.isLocked = isLocked
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.closedAt = closedAt
        self.webURL = webURL
    }

    public var isOpen: Bool {
        state == .open
    }
}

public struct IssueComment: Identifiable, Equatable, Codable, Sendable {
    public let id: Int64
    public var body: String
    public let author: IssueUser
    public let createdAt: Date
    public var updatedAt: Date
    public let webURL: URL?

    public init(
        id: Int64,
        body: String,
        author: IssueUser,
        createdAt: Date,
        updatedAt: Date,
        webURL: URL? = nil
    ) {
        self.id = id
        self.body = body
        self.author = author
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.webURL = webURL
    }
}

public enum IssueTimelineEventKind: String, Codable, Sendable {
    case commented
    case closed
    case reopened
    case labeled
    case unlabeled
    case assigned
    case unassigned
    case milestoned
    case demilestoned
    case locked
    case unlocked
    case referenced
    case committed
}

public struct IssueTimelineEvent: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let kind: IssueTimelineEventKind
    public let actor: IssueUser?
    public let createdAt: Date
    public let detail: String?
    public let comment: IssueComment?

    public init(
        id: String,
        kind: IssueTimelineEventKind,
        actor: IssueUser?,
        createdAt: Date,
        detail: String? = nil,
        comment: IssueComment? = nil
    ) {
        self.id = id
        self.kind = kind
        self.actor = actor
        self.createdAt = createdAt
        self.detail = detail
        self.comment = comment
    }
}
