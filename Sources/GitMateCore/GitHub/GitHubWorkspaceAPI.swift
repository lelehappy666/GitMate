import Foundation

public protocol GitHubWorkspaceAPI: Sendable {
    func repositorySummary(
        repository: Repository,
        token: String
    ) async throws -> RepositoryOnlineSummary

    func readme(
        repository: Repository,
        token: String
    ) async throws -> GitHubREADME
}

public protocol GitHubWorkspaceAPIProviding: Sendable {
    func api(for account: GitHubAccount) throws -> any GitHubWorkspaceAPI
}

public struct DefaultGitHubWorkspaceAPIProvider:
    GitHubWorkspaceAPIProviding,
    @unchecked Sendable
{
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func api(for account: GitHubAccount) throws -> any GitHubWorkspaceAPI {
        switch account.kind {
        case .githubDotCom:
            return URLSessionGitHubWorkspaceAPI(session: session)
        case .enterprise:
            let endpoint = try EnterpriseEndpoint(serverURL: account.serverURL)
            return URLSessionGitHubWorkspaceAPI(
                session: session,
                baseURL: endpoint.apiBaseURL
            )
        }
    }
}

public struct ReauthorizationRequiredGitHubWorkspaceAPI: GitHubWorkspaceAPI {
    public init() {}

    public func repositorySummary(
        repository: Repository,
        token: String
    ) async throws -> RepositoryOnlineSummary {
        throw WorkspaceAPIError.authorizationRequired
    }

    public func readme(
        repository: Repository,
        token: String
    ) async throws -> GitHubREADME {
        throw WorkspaceAPIError.authorizationRequired
    }
}

public struct GitHubREADME: Equatable, Sendable {
    public let repositoryID: Int64
    public let path: String
    public let markdown: String
    public let downloadURL: URL?

    public init(
        repositoryID: Int64,
        path: String,
        markdown: String,
        downloadURL: URL?
    ) {
        self.repositoryID = repositoryID
        self.path = path
        self.markdown = markdown
        self.downloadURL = downloadURL
    }
}

public enum WorkspaceAPIError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidResponse
    case authorizationRequired
    case rateLimited(resetAt: Date)
    case httpStatus(Int, String?)
    case decoding
}

extension WorkspaceAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "GitHub 工作区 API 地址无效。"
        case .invalidResponse:
            "GitHub 工作区 API 返回了无法识别的响应。"
        case .authorizationRequired:
            "GitHub 授权已失效，请重新授权。"
        case let .rateLimited(resetAt):
            "GitHub API 已达到速率限制，可在 \(resetAt.formatted()) 后重试。"
        case let .httpStatus(statusCode, message):
            message.map { "GitHub 工作区请求失败（\(statusCode)）：\($0)" }
                ?? "GitHub 工作区请求失败（\(statusCode)）。"
        case .decoding:
            "无法解析 GitHub 工作区数据。"
        }
    }
}
