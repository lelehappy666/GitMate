import Foundation

public enum IssueSort: String, Codable, Sendable {
    case created
    case updated
    case comments
}

public enum IssueDirection: String, Codable, Sendable {
    case ascending = "asc"
    case descending = "desc"
}

public struct IssueQuery: Equatable, Codable, Sendable {
    public var state: IssueState?
    public var author: String?
    public var assignee: String?
    public var labels: [String]
    public var milestone: String?
    public var sort: IssueSort
    public var direction: IssueDirection
    public var search: String?

    public init(
        state: IssueState? = nil,
        author: String? = nil,
        assignee: String? = nil,
        labels: [String] = [],
        milestone: String? = nil,
        sort: IssueSort = .created,
        direction: IssueDirection = .descending,
        search: String? = nil
    ) {
        self.state = state
        self.author = author
        self.assignee = assignee
        self.labels = labels
        self.milestone = milestone
        self.sort = sort
        self.direction = direction
        self.search = search
    }

    var usesSearchEndpoint: Bool {
        guard let search else {
            return false
        }
        return !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func repositoryQueryItems() -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "filter", value: "all"),
            URLQueryItem(name: "state", value: state?.rawValue ?? "all"),
            URLQueryItem(name: "sort", value: sort.rawValue),
            URLQueryItem(name: "direction", value: direction.rawValue),
            URLQueryItem(name: "per_page", value: "100")
        ]
        if let author, !author.isEmpty {
            items.append(URLQueryItem(name: "creator", value: author))
        }
        if let assignee, !assignee.isEmpty {
            items.append(URLQueryItem(name: "assignee", value: assignee))
        }
        if !labels.isEmpty {
            items.append(URLQueryItem(name: "labels", value: labels.joined(separator: ",")))
        }
        if let milestone, !milestone.isEmpty {
            items.append(URLQueryItem(name: "milestone", value: milestone))
        }
        return items
    }

    func searchQueryItems(repositoryFullName: String) -> [URLQueryItem] {
        var qualifiers = [
            "repo:\(repositoryFullName)",
            "is:issue"
        ]
        if let state {
            qualifiers.append("is:\(state.rawValue)")
        }
        if let author, !author.isEmpty {
            qualifiers.append("author:\(author)")
        }
        if let assignee, !assignee.isEmpty {
            qualifiers.append("assignee:\(assignee)")
        }
        qualifiers += labels.map { "label:\"\($0)\"" }
        if let milestone, !milestone.isEmpty {
            qualifiers.append("milestone:\"\(milestone)\"")
        }
        if let search {
            let value = search.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                qualifiers.append(value)
            }
        }
        return [
            URLQueryItem(name: "q", value: qualifiers.joined(separator: " ")),
            URLQueryItem(name: "sort", value: sort.rawValue),
            URLQueryItem(name: "order", value: direction.rawValue),
            URLQueryItem(name: "per_page", value: "100")
        ]
    }
}
