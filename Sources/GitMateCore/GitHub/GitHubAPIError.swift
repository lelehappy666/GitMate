import Foundation

public struct GitHubValidationErrorDetail:
    Equatable,
    Codable,
    Sendable
{
    public let resource: String?
    public let field: String?
    public let code: String?
    public let message: String?

    public init(
        resource: String?,
        field: String?,
        code: String?,
        message: String?
    ) {
        self.resource = resource
        self.field = field
        self.code = code
        self.message = message
    }
}

public enum GitHubAPIError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
    case invalidResponse
    case httpStatus(Int, String?)
    case forbidden(String)
    case rateLimited(resetAt: Date)
    case detailedRateLimit(resetAt: Date?, message: String)
    case conflict(String)
    case validationFailed(
        message: String,
        details: [GitHubValidationErrorDetail]
    )
    case notFound(String)
    case decoding(String)
    case authorizationPending
    case slowDown
    case expiredToken
    case accessDenied
    case missingAccessToken
}

extension GitHubAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            message
        case .invalidResponse:
            "GitHub 返回了无法识别的响应。"
        case let .httpStatus(statusCode, message):
            message.map { "GitHub 请求失败（\(statusCode)）：\($0)" }
                ?? "GitHub 请求失败（\(statusCode)）。"
        case let .forbidden(message):
            "GitHub 权限不足：\(message)"
        case let .rateLimited(resetAt):
            "GitHub API 已达到速率限制，请在 \(resetAt.formatted()) 后重试。"
        case let .detailedRateLimit(resetAt, message):
            resetAt.map {
                "\(message) 可在 \($0.formatted(date: .abbreviated, time: .shortened)) 后重试。"
            } ?? message
        case let .conflict(message):
            "GitHub 资源冲突：\(message)"
        case let .validationFailed(message, details):
            details.isEmpty
                ? message
                : "\(message) 请检查：\(details.map(Self.validationDetail).joined(separator: "；"))。"
        case let .notFound(message):
            "GitHub 资源不存在：\(message)"
        case let .decoding(message):
            "无法解析 GitHub 数据：\(message)"
        case .authorizationPending:
            "正在等待你在浏览器中完成授权。"
        case .slowDown:
            "GitHub 要求降低授权检查频率。"
        case .expiredToken:
            "设备验证码已过期，请重新登录。"
        case .accessDenied:
            "你已取消 GitHub 授权。"
        case .missingAccessToken:
            "GitHub 未返回访问令牌。"
        }
    }

    private static func validationDetail(
        _ detail: GitHubValidationErrorDetail
    ) -> String {
        let location = [detail.resource, detail.field]
            .compactMap { value in
                value?.isEmpty == false ? value : nil
            }
            .joined(separator: ".")
        let code = detail.code.flatMap { value in
            value.isEmpty ? nil : "（\(value)）"
        } ?? ""
        let prefix = location.isEmpty ? "请求字段" : location
        guard let message = detail.message, !message.isEmpty else {
            return prefix + code
        }
        return prefix + code + "：" + message
    }
}
