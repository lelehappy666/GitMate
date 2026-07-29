import Foundation

struct IssueUserPayload: Decodable {
    let id: Int64?
    let login: String
    let name: String?
    let avatarURL: URL?
    let htmlURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id
        case login
        case name
        case avatarURL = "avatar_url"
        case htmlURL = "html_url"
    }

    var model: IssueUser {
        IssueUser(
            databaseID: id,
            login: login,
            name: name,
            avatarURL: avatarURL,
            webURL: htmlURL
        )
    }
}

struct IssueLabelPayload: Decodable {
    let id: Int64?
    let name: String
    let color: String
    let description: String?
    let isDefault: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case description
        case isDefault = "default"
    }

    var model: IssueLabel {
        IssueLabel(
            id: id ?? stableIdentifier(name),
            name: name,
            color: color,
            description: description,
            isDefault: isDefault ?? false
        )
    }
}

struct IssueMilestonePayload: Decodable {
    let id: Int64
    let number: Int
    let title: String
    let description: String?
    let state: IssueState
    let openIssues: Int
    let closedIssues: Int
    let dueOn: Date?
    let createdAt: Date?
    let updatedAt: Date?
    let closedAt: Date?
    let creator: IssueUserPayload?
    let htmlURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case description
        case state
        case openIssues = "open_issues"
        case closedIssues = "closed_issues"
        case dueOn = "due_on"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case closedAt = "closed_at"
        case creator
        case htmlURL = "html_url"
    }

    var model: IssueMilestone {
        IssueMilestone(
            id: id,
            number: number,
            title: title,
            description: description,
            state: state,
            openIssues: openIssues,
            closedIssues: closedIssues,
            dueOn: dueOn,
            createdAt: createdAt ?? .distantPast,
            updatedAt: updatedAt ?? .distantPast,
            closedAt: closedAt,
            creator: creator?.model,
            webURL: htmlURL
        )
    }
}

struct IssuePayload: Decodable {
    let id: Int64
    let number: Int
    let title: String
    let body: String?
    let state: IssueState
    let user: IssueUserPayload
    let assignees: [IssueUserPayload]?
    let labels: [IssueLabelPayload]?
    let milestone: IssueMilestonePayload?
    let comments: Int?
    let locked: Bool?
    let createdAt: Date?
    let updatedAt: Date?
    let closedAt: Date?
    let htmlURL: URL?
    let pullRequest: GitHubJSONValue?

    private enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case body
        case state
        case user
        case assignees
        case labels
        case milestone
        case comments
        case locked
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case closedAt = "closed_at"
        case htmlURL = "html_url"
        case pullRequest = "pull_request"
    }

    var isPullRequest: Bool {
        pullRequest != nil
    }

    var model: GitHubIssue {
        GitHubIssue(
            id: id,
            number: number,
            title: title,
            body: body,
            state: state,
            author: user.model,
            assignees: (assignees ?? []).map(\.model),
            labels: (labels ?? []).map(\.model),
            milestone: milestone?.model,
            commentsCount: comments ?? 0,
            isLocked: locked ?? false,
            createdAt: createdAt ?? .distantPast,
            updatedAt: updatedAt ?? .distantPast,
            closedAt: closedAt,
            webURL: htmlURL
        )
    }
}

struct IssueCommentPayload: Decodable {
    let id: Int64
    let body: String
    let user: IssueUserPayload
    let createdAt: Date
    let updatedAt: Date
    let htmlURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id
        case body
        case user
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case htmlURL = "html_url"
    }

    var model: IssueComment {
        IssueComment(
            id: id,
            body: body,
            author: user.model,
            createdAt: createdAt,
            updatedAt: updatedAt,
            webURL: htmlURL
        )
    }
}

struct IssueTimelinePayload: Decodable {
    struct NamedValue: Decodable {
        let name: String?
        let title: String?
    }

    let id: Int64?
    let nodeID: String?
    let event: String?
    let actor: IssueUserPayload?
    let user: IssueUserPayload?
    let createdAt: Date
    let updatedAt: Date?
    let body: String?
    let htmlURL: URL?
    let label: NamedValue?
    let milestone: NamedValue?
    let commitID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case nodeID = "node_id"
        case event
        case actor
        case user
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case body
        case htmlURL = "html_url"
        case label
        case milestone
        case commitID = "commit_id"
    }

    var model: IssueTimelineEvent? {
        let kind: IssueTimelineEventKind
        if body != nil {
            kind = .commented
        } else if let event, let parsed = IssueTimelineEventKind(rawValue: event) {
            kind = parsed
        } else {
            return nil
        }
        let comment: IssueComment?
        if let id, let body, let user {
            comment = IssueComment(
                id: id,
                body: body,
                author: user.model,
                createdAt: createdAt,
                updatedAt: updatedAt ?? createdAt,
                webURL: htmlURL
            )
        } else {
            comment = nil
        }
        let detail = label?.name
            ?? milestone?.title
            ?? commitID
        return IssueTimelineEvent(
            id: nodeID ?? id.map(String.init) ?? "\(kind.rawValue)-\(createdAt.timeIntervalSince1970)",
            kind: kind,
            actor: actor?.model ?? user?.model,
            createdAt: createdAt,
            detail: detail,
            comment: comment
        )
    }
}

struct SearchIssuesPayload: Decodable {
    let items: [IssuePayload]
}

private func stableIdentifier(_ value: String) -> Int64 {
    value.utf8.reduce(5_381) { partial, byte in
        ((partial << 5) &+ partial) &+ Int64(byte)
    }
}
