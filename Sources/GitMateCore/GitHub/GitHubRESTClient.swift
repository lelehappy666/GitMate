import Foundation

public final class GitHubRESTClient: @unchecked Sendable {
    private let session: URLSession
    private let apiBaseURL: URL

    public init(
        session: URLSession = .shared,
        apiBaseURL: URL = URL(string: "https://api.github.com")!
    ) {
        self.session = session
        self.apiBaseURL = apiBaseURL
    }

    public func send<Response: Decodable>(
        _ request: GitHubRequest,
        token: String
    ) async throws -> Response {
        let response: GitHubRESTResponse<Response> = try await sendWithMetadata(
            request,
            token: token
        )
        return response.value
    }

    public func sendWithMetadata<Response: Decodable>(
        _ request: GitHubRequest,
        token: String
    ) async throws -> GitHubRESTResponse<Response> {
        let (data, response) = try await perform(request, token: token)
        do {
            let value = try makeDecoder().decode(Response.self, from: data)
            return GitHubRESTResponse(
                value: value,
                metadata: GitHubResponseMetadata(response: response)
            )
        } catch let error as GitHubAPIError {
            throw error
        } catch {
            throw GitHubAPIError.decoding(error.localizedDescription)
        }
    }

    public func sendPage<Element: Decodable>(
        _ request: GitHubRequest,
        token: String
    ) async throws -> GitHubPage<Element> {
        let response: GitHubRESTResponse<[Element]> = try await sendWithMetadata(
            request,
            token: token
        )
        return GitHubPage(
            items: response.value,
            nextPageURL: Self.nextPageURL(
                from: response.metadata.headerValue(for: "Link")
            )
        )
    }

    public func sendWithoutResponse(
        _ request: GitHubRequest,
        token: String
    ) async throws {
        _ = try await perform(request, token: token)
    }

    private func perform(
        _ request: GitHubRequest,
        token: String
    ) async throws -> (Data, HTTPURLResponse) {
        let url = try makeURL(for: request)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(
            acceptHeader(additional: request.additionalAccept),
            forHTTPHeaderField: "Accept"
        )
        urlRequest.setValue(
            "2022-11-28",
            forHTTPHeaderField: "X-GitHub-Api-Version"
        )
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw mapError(response: httpResponse, data: data)
        }
        return (data, httpResponse)
    }

    private func makeURL(for request: GitHubRequest) throws -> URL {
        let base: URL
        if let absoluteURL = request.absoluteURL {
            guard
                absoluteURL.scheme?.lowercased() == apiBaseURL.scheme?.lowercased(),
                absoluteURL.host()?.lowercased() == apiBaseURL.host()?.lowercased(),
                absoluteURL.port == apiBaseURL.port
            else {
                throw GitHubAPIError.invalidConfiguration(
                    "GitHub 分页地址与当前服务器不一致。"
                )
            }
            base = absoluteURL
        } else if let path = request.path {
            guard var baseComponents = URLComponents(
                url: apiBaseURL,
                resolvingAgainstBaseURL: false
            ) else {
                throw GitHubAPIError.invalidConfiguration(
                    "GitHub API 地址无效。"
                )
            }
            let basePath = baseComponents.percentEncodedPath
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let requestPath = path.trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
            baseComponents.percentEncodedPath = "/"
                + [basePath, requestPath]
                    .filter { !$0.isEmpty }
                    .joined(separator: "/")
            guard let encodedURL = baseComponents.url else {
                throw GitHubAPIError.invalidConfiguration(
                    "GitHub API 请求地址无效。"
                )
            }
            base = encodedURL
        } else {
            throw GitHubAPIError.invalidConfiguration("GitHub API 请求缺少地址。")
        }

        guard var components = URLComponents(
            url: base,
            resolvingAgainstBaseURL: false
        ) else {
            throw GitHubAPIError.invalidConfiguration("GitHub API 地址无效。")
        }
        if !request.queryItems.isEmpty {
            components.queryItems = request.queryItems
        }
        guard let finalURL = components.url else {
            throw GitHubAPIError.invalidConfiguration("GitHub API 请求地址无效。")
        }
        return finalURL
    }

    private func acceptHeader(additional: String?) -> String {
        guard let additional, !additional.isEmpty else {
            return "application/vnd.github+json"
        }
        return "application/vnd.github+json, \(additional)"
    }

    private func mapError(
        response: HTTPURLResponse,
        data: Data
    ) -> GitHubAPIError {
        let payload = try? JSONDecoder().decode(GitHubErrorPayload.self, from: data)
        let message = payload?.message

        switch response.statusCode {
        case 401:
            return .httpStatus(401, message)
        case 403 where response.value(
            forHTTPHeaderField: "X-RateLimit-Remaining"
        ) == "0":
            let resetAt = response.value(forHTTPHeaderField: "X-RateLimit-Reset")
                .flatMap(TimeInterval.init)
                .map(Date.init(timeIntervalSince1970:))
            return .rateLimited(
                resetAt: resetAt,
                message: message ?? "GitHub API 请求次数已用完。"
            )
        case 403:
            return .forbidden(message ?? "当前令牌没有执行此操作的权限。")
        case 404:
            return .notFound(message ?? "未找到 GitHub 资源。")
        case 409:
            return .conflict(message ?? "GitHub 资源状态发生冲突。")
        case 422:
            return .validationFailed(
                message: message ?? "GitHub 拒绝了请求数据。",
                fields: payload?.errors?.compactMap(\.field) ?? []
            )
        case 429:
            let resetAt = response.value(forHTTPHeaderField: "X-RateLimit-Reset")
                .flatMap(TimeInterval.init)
                .map(Date.init(timeIntervalSince1970:))
            return .rateLimited(
                resetAt: resetAt,
                message: message ?? "GitHub API 请求过于频繁。"
            )
        default:
            return .httpStatus(response.statusCode, message)
        }
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds
            ]
            if let date = fractional.date(from: value) {
                return date
            }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "无法解析 GitHub 日期：\(value)"
            )
        }
        return decoder
    }

    private static func nextPageURL(from linkHeader: String?) -> URL? {
        guard let linkHeader else {
            return nil
        }
        for segment in linkHeader.split(separator: ",") {
            let parts = segment.split(separator: ";", omittingEmptySubsequences: true)
            guard parts.count >= 2 else {
                continue
            }
            let relation = parts.dropFirst().joined(separator: ";")
            guard relation.contains("rel=\"next\"") else {
                continue
            }
            let rawURL = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard rawURL.hasPrefix("<"), rawURL.hasSuffix(">") else {
                continue
            }
            return URL(string: String(rawURL.dropFirst().dropLast()))
        }
        return nil
    }
}

struct GitHubErrorPayload: Decodable {
    struct Detail: Decodable {
        let field: String?
    }

    let message: String
    let errors: [Detail]?

    static func message(from data: Data) -> String? {
        try? JSONDecoder().decode(Self.self, from: data).message
    }
}
