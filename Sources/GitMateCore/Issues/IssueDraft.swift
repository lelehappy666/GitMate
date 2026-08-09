import Foundation

public struct IssueDraft: Equatable, Codable, Sendable {
    public var title: String
    public var body: String
    public var assigneeLogins: [String]
    public var labelNames: [String]
    public var milestoneNumber: Int?
    public var templateName: String?
    public var updatedAt: Date

    public init(
        title: String,
        body: String,
        assigneeLogins: [String] = [],
        labelNames: [String] = [],
        milestoneNumber: Int? = nil,
        templateName: String? = nil,
        updatedAt: Date = .now
    ) {
        self.title = title
        self.body = body
        self.assigneeLogins = assigneeLogins
        self.labelNames = labelNames
        self.milestoneNumber = milestoneNumber
        self.templateName = templateName
        self.updatedAt = updatedAt
    }
}

public struct SavedIssueView: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var query: String

    public init(id: UUID = UUID(), name: String, query: String) {
        self.id = id
        self.name = name
        self.query = query
    }
}
