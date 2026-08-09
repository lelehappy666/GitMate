import Foundation

public final class URLSessionGitHubWorkspaceAPI: GitHubWorkspaceAPI, @unchecked Sendable {
    private let session: URLSession
    private let baseURL: URL
    private let now: @Sendable () -> Date

    public init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.github.com")!,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.baseURL = baseURL
        self.now = now
    }

    public func repositorySummary(
        repository: Repository,
        token: String
    ) async throws -> RepositoryOnlineSummary {
        let repositoryPayload: RepositorySummaryPayload = try await get(
            path: "/repos/\(repository.fullName)",
            token: token
        )
        let issuePayload: SearchCountPayload = try await get(
            path: "/search/issues",
            token: token,
            queryItems: [
                URLQueryItem(
                    name: "q",
                    value: "repo:\(repository.fullName) is:issue is:open"
                )
            ]
        )
        let pullRequestPayload: SearchCountPayload = try await get(
            path: "/search/issues",
            token: token,
            queryItems: [
                URLQueryItem(
                    name: "q",
                    value: "repo:\(repository.fullName) is:pr is:open"
                )
            ]
        )
        let actionsPayload: ActionsCountPayload = try await get(
            path: "/repos/\(repository.fullName)/actions/runs",
            token: token,
            queryItems: [
                URLQueryItem(name: "status", value: "failure"),
                URLQueryItem(name: "per_page", value: "1")
            ]
        )

        return RepositoryOnlineSummary(
            repositoryID: repository.id,
            primaryLanguage: repositoryPayload.language,
            openIssueCount: issuePayload.totalCount,
            openPullRequestCount: pullRequestPayload.totalCount,
            failedWorkflowCount: actionsPayload.totalCount,
            remoteUpdatedAt: repositoryPayload.updatedAt
        )
    }

    public func readme(
        repository: Repository,
        token: String
    ) async throws -> GitHubREADME {
        let payload: READMEPayload = try await get(
            path: "/repos/\(repository.fullName)/readme",
            token: token
        )
        guard payload.encoding.lowercased() == "base64" else {
            throw WorkspaceAPIError.decoding
        }
        let compactContent = payload.content.filter { !$0.isNewline }
        guard let data = Data(base64Encoded: compactContent),
              let markdown = String(data: data, encoding: .utf8)
        else {
            throw WorkspaceAPIError.decoding
        }

        return GitHubREADME(
            repositoryID: repository.id,
            path: payload.path,
            markdown: markdown,
            downloadURL: payload.downloadURL
        )
    }

    private func get<Payload: Decodable>(
        path: String,
        token: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Payload {
        let request = try makeRequest(
            path: path,
            token: token,
            queryItems: queryItems
        )
        let (data, response) = try await session.data(for: request)
        _ = try validatedHTTPResponse(response, data: data)

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Payload.self, from: data)
        } catch {
            throw WorkspaceAPIError.decoding
        }
    }

    private func makeRequest(
        path: String,
        token: String,
        queryItems: [URLQueryItem]
    ) throws -> URLRequest {
        let relativePath = path.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        let url = baseURL.appending(path: relativePath)
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            throw WorkspaceAPIError.invalidConfiguration
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let finalURL = components.url else {
            throw WorkspaceAPIError.invalidConfiguration
        }

        var request = URLRequest(url: finalURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "2022-11-28",
            forHTTPHeaderField: "X-GitHub-Api-Version"
        )
        return request
    }

    private func validatedHTTPResponse(
        _ response: URLResponse,
        data: Data
    ) throws -> HTTPURLResponse {
        guard let response = response as? HTTPURLResponse else {
            throw WorkspaceAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 {
                throw WorkspaceAPIError.authorizationRequired
            }
            if let resetAt = rateLimitResetAt(response, data: data) {
                throw WorkspaceAPIError.rateLimited(
                    resetAt: resetAt
                )
            }
            if response.statusCode == 403 {
                throw WorkspaceAPIError.authorizationRequired
            }
            throw WorkspaceAPIError.httpStatus(
                response.statusCode,
                GitHubErrorPayload.message(from: data)
            )
        }
        return response
    }

    private func rateLimitResetAt(
        _ response: HTTPURLResponse,
        data: Data
    ) -> Date? {
        let message = GitHubErrorPayload.message(from: data)?
            .lowercased() ?? ""
        let isRateLimited = response.statusCode == 429
            || (
                response.statusCode == 403
                    && (
                        response.value(
                            forHTTPHeaderField: "X-RateLimit-Remaining"
                        ) == "0"
                            || response.value(
                                forHTTPHeaderField: "Retry-After"
                            ) != nil
                            || message.contains("rate limit")
                    )
            )
        guard isRateLimited else { return nil }

        if let rawDelay = response.value(
            forHTTPHeaderField: "Retry-After"
        ),
           let delay = TimeInterval(rawDelay),
           delay.isFinite,
           delay >= 0
        {
            return now().addingTimeInterval(delay)
        }
        if response.value(
            forHTTPHeaderField: "X-RateLimit-Remaining"
        ) == "0",
           let rawTimestamp = response.value(
               forHTTPHeaderField: "X-RateLimit-Reset"
           ),
           let timestamp = TimeInterval(rawTimestamp)
        {
            return Date(timeIntervalSince1970: timestamp)
        }
        return now().addingTimeInterval(60)
    }
}

private struct RepositorySummaryPayload: Decodable {
    let language: String?
    let updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case language
        case updatedAt = "updated_at"
    }
}

private struct SearchCountPayload: Decodable {
    let totalCount: Int

    private enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
    }
}

private struct ActionsCountPayload: Decodable {
    let totalCount: Int

    private enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
    }
}

private struct READMEPayload: Decodable {
    let path: String
    let content: String
    let encoding: String
    let downloadURL: URL?

    private enum CodingKeys: String, CodingKey {
        case path
        case content
        case encoding
        case downloadURL = "download_url"
    }
}
