import Foundation

public final class URLSessionGitHubIssuesAPI:
    GitHubIssuesAPI,
    LabelMergeAPI,
    @unchecked Sendable
{
    private struct CommentBody: Encodable {
        let body: String
    }

    private struct LockBody: Encodable {
        let lockReason: String?

        private enum CodingKeys: String, CodingKey {
            case lockReason = "lock_reason"
        }
    }

    private struct LabelNamesBody: Encodable {
        let labels: [String]
    }

    private struct UpdateLabelBody: Encodable {
        let newName: String
        let color: String
        let description: String?

        private enum CodingKeys: String, CodingKey {
            case newName = "new_name"
            case color
            case description
        }
    }

    private let client: GitHubRESTClient
    private let repositoryFullName: String

    public init(
        client: GitHubRESTClient,
        repositoryFullName: String
    ) {
        self.client = client
        self.repositoryFullName = repositoryFullName
    }

    public func issues(
        query: IssueQuery,
        pageURL: URL?,
        token: String
    ) async throws -> GitHubPage<GitHubIssue> {
        let isSearch = pageURL?.path == "/search/issues"
            || (pageURL == nil && query.usesSearchEndpoint)
        let request: GitHubRequest
        if let pageURL {
            request = GitHubRequest(absoluteURL: pageURL)
        } else if isSearch {
            request = GitHubRequest(
                method: .get,
                path: "/search/issues",
                queryItems: query.searchQueryItems(
                    repositoryFullName: repositoryFullName
                )
            )
        } else {
            request = GitHubRequest(
                method: .get,
                path: "\(repositoryPath)/issues",
                queryItems: query.repositoryQueryItems()
            )
        }

        if isSearch {
            let response: GitHubRESTResponse<SearchIssuesPayload> =
                try await client.sendWithMetadata(request, token: token)
            return issuePage(
                payloads: response.value.items,
                metadata: response.metadata
            )
        }
        let response: GitHubRESTResponse<[IssuePayload]> =
            try await client.sendWithMetadata(request, token: token)
        return issuePage(
            payloads: response.value,
            metadata: response.metadata
        )
    }

    public func issue(number: Int, token: String) async throws -> GitHubIssue {
        let payload: IssuePayload = try await client.send(
            GitHubRequest(
                method: .get,
                path: "\(repositoryPath)/issues/\(number)"
            ),
            token: token
        )
        return payload.model
    }

    public func timeline(
        number: Int,
        token: String
    ) async throws -> [IssueTimelineEvent] {
        var response: GitHubRESTResponse<[IssueTimelinePayload]> =
            try await client.sendWithMetadata(
                GitHubRequest(
                    method: .get,
                    path: "\(repositoryPath)/issues/\(number)/timeline",
                    queryItems: [URLQueryItem(name: "per_page", value: "100")]
                ),
                token: token
            )
        var events = response.value.compactMap(\.model)
        while let next = nextPageURL(metadata: response.metadata) {
            try Task.checkCancellation()
            response = try await client.sendWithMetadata(
                GitHubRequest(absoluteURL: next),
                token: token
            )
            events.append(contentsOf: response.value.compactMap(\.model))
        }
        return events
    }

    public func comments(
        number: Int,
        token: String
    ) async throws -> [IssueComment] {
        var response: GitHubRESTResponse<[IssueCommentPayload]> =
            try await client.sendWithMetadata(
                GitHubRequest(
                    method: .get,
                    path: "\(repositoryPath)/issues/\(number)/comments",
                    queryItems: [URLQueryItem(name: "per_page", value: "100")]
                ),
                token: token
            )
        var comments = response.value.map(\.model)
        while let next = nextPageURL(metadata: response.metadata) {
            try Task.checkCancellation()
            response = try await client.sendWithMetadata(
                GitHubRequest(absoluteURL: next),
                token: token
            )
            comments.append(contentsOf: response.value.map(\.model))
        }
        return comments
    }

    public func createIssue(
        _ input: CreateIssueInput,
        token: String
    ) async throws -> GitHubIssue {
        let payload: IssuePayload = try await client.send(
            try GitHubRequest(
                method: .post,
                path: "\(repositoryPath)/issues",
                encodableBody: input
            ),
            token: token
        )
        return payload.model
    }

    public func updateIssue(
        number: Int,
        input: UpdateIssueInput,
        token: String
    ) async throws -> GitHubIssue {
        let payload: IssuePayload = try await client.send(
            try GitHubRequest(
                method: .patch,
                path: "\(repositoryPath)/issues/\(number)",
                encodableBody: input
            ),
            token: token
        )
        return payload.model
    }

    public func createComment(
        number: Int,
        body: String,
        token: String
    ) async throws -> IssueComment {
        let payload: IssueCommentPayload = try await client.send(
            try GitHubRequest(
                method: .post,
                path: "\(repositoryPath)/issues/\(number)/comments",
                encodableBody: CommentBody(body: body)
            ),
            token: token
        )
        return payload.model
    }

    public func updateComment(
        id: Int64,
        body: String,
        token: String
    ) async throws -> IssueComment {
        let payload: IssueCommentPayload = try await client.send(
            try GitHubRequest(
                method: .patch,
                path: "\(repositoryPath)/issues/comments/\(id)",
                encodableBody: CommentBody(body: body)
            ),
            token: token
        )
        return payload.model
    }

    public func lockIssue(
        number: Int,
        reason: IssueLockReason?,
        token: String
    ) async throws {
        try await client.sendWithoutResponse(
            try GitHubRequest(
                method: .put,
                path: "\(repositoryPath)/issues/\(number)/lock",
                encodableBody: LockBody(lockReason: reason?.rawValue)
            ),
            token: token
        )
    }

    public func unlockIssue(number: Int, token: String) async throws {
        try await client.sendWithoutResponse(
            GitHubRequest(
                method: .delete,
                path: "\(repositoryPath)/issues/\(number)/lock"
            ),
            token: token
        )
    }

    public func milestones(
        state: IssueState?,
        token: String
    ) async throws -> [IssueMilestone] {
        var page: GitHubPage<IssueMilestonePayload> = try await client.sendPage(
            GitHubRequest(
                method: .get,
                path: "\(repositoryPath)/milestones",
                queryItems: [
                    URLQueryItem(name: "state", value: state?.rawValue ?? "all"),
                    URLQueryItem(name: "per_page", value: "100")
                ]
            ),
            token: token
        )
        var models = page.items.map(\.model)
        while let next = page.nextPageURL {
            try Task.checkCancellation()
            page = try await client.sendPage(
                GitHubRequest(absoluteURL: next),
                token: token
            )
            models.append(contentsOf: page.items.map(\.model))
        }
        return models
    }

    public func createMilestone(
        _ input: MilestoneInput,
        token: String
    ) async throws -> IssueMilestone {
        let payload: IssueMilestonePayload = try await client.send(
            try GitHubRequest(
                method: .post,
                path: "\(repositoryPath)/milestones",
                encodableBody: input
            ),
            token: token
        )
        return payload.model
    }

    public func updateMilestone(
        number: Int,
        input: MilestoneInput,
        token: String
    ) async throws -> IssueMilestone {
        let payload: IssueMilestonePayload = try await client.send(
            try GitHubRequest(
                method: .patch,
                path: "\(repositoryPath)/milestones/\(number)",
                encodableBody: input
            ),
            token: token
        )
        return payload.model
    }

    public func deleteMilestone(number: Int, token: String) async throws {
        try await client.sendWithoutResponse(
            GitHubRequest(
                method: .delete,
                path: "\(repositoryPath)/milestones/\(number)"
            ),
            token: token
        )
    }

    public func labels(token: String) async throws -> [IssueLabel] {
        var page: GitHubPage<IssueLabelPayload> = try await client.sendPage(
            GitHubRequest(
                method: .get,
                path: "\(repositoryPath)/labels",
                queryItems: [URLQueryItem(name: "per_page", value: "100")]
            ),
            token: token
        )
        var models = page.items.map(\.model)
        while let next = page.nextPageURL {
            try Task.checkCancellation()
            page = try await client.sendPage(
                GitHubRequest(absoluteURL: next),
                token: token
            )
            models.append(contentsOf: page.items.map(\.model))
        }
        return models
    }

    public func createLabel(
        _ input: IssueLabelInput,
        token: String
    ) async throws -> IssueLabel {
        let payload: IssueLabelPayload = try await client.send(
            try GitHubRequest(
                method: .post,
                path: "\(repositoryPath)/labels",
                encodableBody: input
            ),
            token: token
        )
        return payload.model
    }

    public func updateLabel(
        name: String,
        input: IssueLabelInput,
        token: String
    ) async throws -> IssueLabel {
        let payload: IssueLabelPayload = try await client.send(
            try GitHubRequest(
                method: .patch,
                path: "\(repositoryPath)/labels/\(name)",
                encodableBody: UpdateLabelBody(
                    newName: input.name,
                    color: input.color,
                    description: input.description
                )
            ),
            token: token
        )
        return payload.model
    }

    public func deleteLabel(name: String, token: String) async throws {
        try await client.sendWithoutResponse(
            GitHubRequest(
                method: .delete,
                path: "\(repositoryPath)/labels/\(name)"
            ),
            token: token
        )
    }

    public func issueNumbers(
        labelName: String,
        token: String
    ) async throws -> [Int] {
        let query = IssueQuery(state: nil, labels: [labelName])
        var page = try await issues(query: query, pageURL: nil, token: token)
        var numbers = page.items.map(\.number)
        while let next = page.nextPageURL {
            try Task.checkCancellation()
            page = try await issues(
                query: query,
                pageURL: next,
                token: token
            )
            numbers.append(contentsOf: page.items.map(\.number))
        }
        return numbers
    }

    public func addLabels(
        to issueNumber: Int,
        names: [String],
        token: String
    ) async throws {
        let _: [IssueLabelPayload] = try await client.send(
            try GitHubRequest(
                method: .post,
                path: "\(repositoryPath)/issues/\(issueNumber)/labels",
                encodableBody: LabelNamesBody(labels: names)
            ),
            token: token
        )
    }

    public func removeLabel(
        from issueNumber: Int,
        name: String,
        token: String
    ) async throws {
        let _: [IssueLabelPayload] = try await client.send(
            GitHubRequest(
                method: .delete,
                path: "\(repositoryPath)/issues/\(issueNumber)/labels/\(name)"
            ),
            token: token
        )
    }

    private func issuePage(
        payloads: [IssuePayload],
        metadata: GitHubResponseMetadata
    ) -> GitHubPage<GitHubIssue> {
        GitHubPage(
            items: payloads.filter { !$0.isPullRequest }.map(\.model),
            nextPageURL: nextPageURL(metadata: metadata)
        )
    }

    private func nextPageURL(metadata: GitHubResponseMetadata) -> URL? {
        guard let linkHeader = metadata.headerValue(for: "Link") else {
            return nil
        }
        for segment in linkHeader.split(separator: ",") {
            let parts = segment.split(separator: ";")
            guard
                let first = parts.first,
                parts.dropFirst().contains(where: { $0.contains("rel=\"next\"") })
            else {
                continue
            }
            let rawURL = first.trimmingCharacters(in: .whitespacesAndNewlines)
            guard rawURL.hasPrefix("<"), rawURL.hasSuffix(">") else {
                continue
            }
            return URL(string: String(rawURL.dropFirst().dropLast()))
        }
        return nil
    }

    private var repositoryPath: String {
        "/repos/\(repositoryFullName)"
    }
}
