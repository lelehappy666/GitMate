import Foundation

public final class URLSessionGitHubBranchesAPI:
    GitHubBranchesAPI,
    @unchecked Sendable
{
    private let client: GitHubRESTClient
    private let repositoryFullName: String

    public init(
        client: GitHubRESTClient,
        repositoryFullName: String
    ) {
        self.client = client
        self.repositoryFullName = repositoryFullName
    }

    public func remoteBranches(token: String) async throws -> [GitBranch] {
        var page: GitHubPage<BranchPayload> = try await client.sendPage(
            GitHubRequest(
                method: .get,
                path: "\(repositoryPath)/branches",
                queryItems: [URLQueryItem(name: "per_page", value: "100")]
            ),
            token: token
        )
        var branches = page.items.map(\.model)
        while let nextPageURL = page.nextPageURL {
            try Task.checkCancellation()
            page = try await client.sendPage(
                GitHubRequest(absoluteURL: nextPageURL),
                token: token
            )
            branches.append(contentsOf: page.items.map(\.model))
        }
        return branches.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public func branchProtection(
        name: String,
        token: String
    ) async throws -> BranchProtectionSummary? {
        do {
            let payload: BranchProtectionPayload = try await client.send(
                GitHubRequest(
                    method: .get,
                    path: "\(repositoryPath)/branches/\(name)/protection"
                ),
                token: token
            )
            return payload.model
        } catch GitHubAPIError.notFound {
            return nil
        }
    }

    public func rulesets(token: String) async throws -> [RepositoryRuleset] {
        var page: GitHubPage<RulesetPayload> = try await client.sendPage(
            GitHubRequest(
                method: .get,
                path: "\(repositoryPath)/rulesets",
                queryItems: [
                    URLQueryItem(name: "includes_parents", value: "true"),
                    URLQueryItem(name: "per_page", value: "100")
                ]
            ),
            token: token
        )
        var models = page.items.map(\.model)
        while let nextPageURL = page.nextPageURL {
            try Task.checkCancellation()
            page = try await client.sendPage(
                GitHubRequest(absoluteURL: nextPageURL),
                token: token
            )
            models.append(contentsOf: page.items.map(\.model))
        }
        return models
    }

    public func ruleset(
        id: Int64,
        token: String
    ) async throws -> RepositoryRuleset {
        let payload: RulesetPayload = try await client.send(
            GitHubRequest(
                method: .get,
                path: "\(repositoryPath)/rulesets/\(id)"
            ),
            token: token
        )
        return payload.model
    }

    public func createRuleset(
        _ input: RepositoryRulesetInput,
        token: String
    ) async throws -> RepositoryRuleset {
        let request = try GitHubRequest(
            method: .post,
            path: "\(repositoryPath)/rulesets",
            encodableBody: RulesetRequestPayload(input: input)
        )
        let payload: RulesetPayload = try await client.send(
            request,
            token: token
        )
        return payload.model
    }

    public func updateRuleset(
        _ ruleset: RepositoryRuleset,
        input: RepositoryRulesetInput,
        token: String
    ) async throws -> RepositoryRuleset {
        guard ruleset.isEditable else {
            throw RulesetOperationError.inheritedRulesetIsReadOnly
        }
        let request = try GitHubRequest(
            method: .patch,
            path: "\(repositoryPath)/rulesets/\(ruleset.id)",
            encodableBody: RulesetRequestPayload(input: input)
        )
        let payload: RulesetPayload = try await client.send(
            request,
            token: token
        )
        return payload.model
    }

    public func deleteRuleset(
        _ ruleset: RepositoryRuleset,
        token: String
    ) async throws {
        guard ruleset.isEditable else {
            throw RulesetOperationError.inheritedRulesetIsReadOnly
        }
        try await client.sendWithoutResponse(
            GitHubRequest(
                method: .delete,
                path: "\(repositoryPath)/rulesets/\(ruleset.id)"
            ),
            token: token
        )
    }

    public func tagReleaseSummary(
        name: String,
        token: String
    ) async throws -> TagReleaseSummary? {
        do {
            let payload: TagReleasePayload = try await client.send(
                GitHubRequest(
                    method: .get,
                    path: "\(repositoryPath)/releases/tags/\(name)"
                ),
                token: token
            )
            return payload.model
        } catch GitHubAPIError.notFound {
            return nil
        }
    }

    private var repositoryPath: String {
        "/repos/\(repositoryFullName)"
    }
}
