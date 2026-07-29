import Foundation

public enum GitHubAPIError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
    case invalidResponse
    case httpStatus(Int, String?)
    case forbidden(String)
    case rateLimited(resetAt: Date?, message: String)
    case conflict(String)
    case validationFailed(message: String, fields: [String])
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
        case let .rateLimited(resetAt, message):
            resetAt.map {
                "\(message) 可在 \($0.formatted(date: .abbreviated, time: .shortened)) 后重试。"
            } ?? message
        case let .conflict(message):
            "GitHub 资源冲突：\(message)"
        case let .validationFailed(message, fields):
            fields.isEmpty
                ? message
                : "\(message) 请检查：\(fields.joined(separator: "、"))。"
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
}
