import Foundation

public struct IssueMilestone: Identifiable, Equatable, Codable, Sendable {
    public let id: Int64
    public let number: Int
    public var title: String
    public var description: String?
    public var state: IssueState
    public var openIssues: Int
    public var closedIssues: Int
    public var dueOn: Date?
    public let createdAt: Date
    public var updatedAt: Date
    public var closedAt: Date?
    public let creator: IssueUser?
    public let webURL: URL?

    public init(
        id: Int64,
        number: Int,
        title: String,
        description: String? = nil,
        state: IssueState,
        openIssues: Int,
        closedIssues: Int,
        dueOn: Date? = nil,
        createdAt: Date = .distantPast,
        updatedAt: Date = .distantPast,
        closedAt: Date? = nil,
        creator: IssueUser? = nil,
        webURL: URL? = nil
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.description = description
        self.state = state
        self.openIssues = max(0, openIssues)
        self.closedIssues = max(0, closedIssues)
        self.dueOn = dueOn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.closedAt = closedAt
        self.creator = creator
        self.webURL = webURL
    }

    public var progress: Double {
        let total = openIssues + closedIssues
        guard total > 0 else {
            return 0
        }
        return min(1, max(0, Double(closedIssues) / Double(total)))
    }
}
