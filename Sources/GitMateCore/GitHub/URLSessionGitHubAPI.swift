import Foundation

public final class URLSessionGitHubAPI: GitHubAPI, @unchecked Sendable {
    private let session: URLSession
    private let apiBaseURL: URL
    private let serverURL: URL
    private let accountKind: GitHubAccountKind

    public init(
        session: URLSession = .shared,
        apiBaseURL: URL = URL(string: "https://api.github.com")!,
        serverURL: URL = URL(string: "https://github.com")!,
        accountKind: GitHubAccountKind = .githubDotCom
    ) {
        self.session = session
        self.apiBaseURL = apiBaseURL
        self.serverURL = serverURL
        self.accountKind = accountKind
    }

    public func currentUser(token: String) async throws -> GitHubAccount {
        let request = try makeRequest(path: "/user", token: token)
        let (data, response) = try await session.data(for: request)
        let httpResponse = try validatedHTTPResponse(response, data: data)

        let payload: UserPayload
        do {
            payload = try JSONDecoder().decode(UserPayload.self, from: data)
        } catch {
            throw GitHubAPIError.decoding(error.localizedDescription)
        }

        let scopes = Set(
            (httpResponse.value(forHTTPHeaderField: "X-OAuth-Scopes") ?? "")
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
        let request = try makeRequest(
            path: "/user/repos",
            token: token,
            queryItems: [
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "sort", value: "updated")
            ]
        )
        let (data, response) = try await session.data(for: request)
        _ = try validatedHTTPResponse(response, data: data)

        let payloads: [RepositoryPayload]
        do {
            payloads = try JSONDecoder().decode([RepositoryPayload].self, from: data)
        } catch {
            throw GitHubAPIError.decoding(error.localizedDescription)
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

    private func makeRequest(
        path: String,
        token: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        let relativePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = apiBaseURL.appending(path: relativePath)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw GitHubAPIError.invalidConfiguration("GitHub API 地址无效。")
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let finalURL = components.url else {
            throw GitHubAPIError.invalidConfiguration("GitHub API 请求地址无效。")
        }

        var request = URLRequest(url: finalURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func validatedHTTPResponse(
        _ response: URLResponse,
        data: Data
    ) throws -> HTTPURLResponse {
        guard let response = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GitHubAPIError.httpStatus(
                response.statusCode,
                GitHubErrorPayload.message(from: data)
            )
        }
        return response
    }
}

struct GitHubErrorPayload: Decodable {
    let message: String

    static func message(from data: Data) -> String? {
        try? JSONDecoder().decode(Self.self, from: data).message
    }
}

private struct UserPayload: Decodable {
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

private struct RepositoryPayload: Decodable {
    struct Owner: Decodable {
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
