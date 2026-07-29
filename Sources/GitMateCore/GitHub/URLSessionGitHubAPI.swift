import Foundation

public final class URLSessionGitHubAPI: GitHubAPI, @unchecked Sendable {
    private let client: GitHubRESTClient
    private let serverURL: URL
    private let accountKind: GitHubAccountKind

    public init(
        session: URLSession = .shared,
        apiBaseURL: URL = URL(string: "https://api.github.com")!,
        serverURL: URL = URL(string: "https://github.com")!,
        accountKind: GitHubAccountKind = .githubDotCom
    ) {
        client = GitHubRESTClient(session: session, apiBaseURL: apiBaseURL)
        self.serverURL = serverURL
        self.accountKind = accountKind
    }

    public func currentUser(token: String) async throws -> GitHubAccount {
        let response: GitHubRESTResponse<UserPayload> = try await client.sendWithMetadata(
            GitHubRequest(method: .get, path: "/user"),
            token: token
        )
        let payload = response.value

        let scopes = Set(
            (response.metadata.headerValue(for: "X-OAuth-Scopes") ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let host = serverURL.host() ?? serverURL.absoluteString

        return GitHubAccount(
            id: "\(host):\(payload.id)",
            login: payload.login,
            name: payload.name,
            avatarURL: payload.avatarURL,
            serverURL: serverURL,
            kind: accountKind,
            scopes: scopes
        )
    }

    public func repositories(token: String) async throws -> [Repository] {
        var page: GitHubPage<RepositoryPayload> = try await client.sendPage(
            GitHubRequest(
                method: .get,
            path: "/user/repos",
            queryItems: [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "sort", value: "updated")
            ]
            ),
            token: token
        )
        var payloads = page.items
        while let nextPageURL = page.nextPageURL {
            try Task.checkCancellation()
            page = try await client.sendPage(
                GitHubRequest(absoluteURL: nextPageURL),
                token: token
            )
            payloads.append(contentsOf: page.items)
        }

        return payloads.map {
            Repository(
                id: $0.id,
                name: $0.name,
                fullName: $0.fullName,
                isPrivate: $0.isPrivate,
                defaultBranch: $0.defaultBranch,
                sizeInKilobytes: $0.size,
                cloneURL: $0.cloneURL,
                ownerAvatarURL: $0.owner.avatarURL
            )
        }
    }
}

private struct UserPayload: Decodable, Sendable {
    let id: Int64
    let login: String
    let name: String?
    let avatarURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id
        case login
        case name
        case avatarURL = "avatar_url"
    }
}

private struct RepositoryPayload: Decodable, Sendable {
    struct Owner: Decodable, Sendable {
        let avatarURL: URL?

        private enum CodingKeys: String, CodingKey {
            case avatarURL = "avatar_url"
        }
    }

    let id: Int64
    let name: String
    let fullName: String
    let isPrivate: Bool
    let defaultBranch: String
    let size: Int
    let cloneURL: URL
    let owner: Owner

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case isPrivate = "private"
        case defaultBranch = "default_branch"
        case size
        case cloneURL = "clone_url"
        case owner
    }
}
