import Foundation

public protocol EnterpriseConnecting: Sendable {
    func verify(serverURL: URL, token: String) async throws -> GitHubAccount
}

public enum EnterpriseConnectionError: Error, Equatable, Sendable {
    case invalidServerURL
    case insecureServerURL
    case missingToken
    case authorizationExpired
    case untrustedCertificate
    case connectionFailed(String)
}

extension EnterpriseConnectionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            "企业 GitHub 服务器地址无效。"
        case .insecureServerURL:
            "企业 GitHub 必须使用 HTTPS 连接。"
        case .missingToken:
            "请输入 Personal Access Token。"
        case .authorizationExpired:
            "企业 GitHub 令牌无效或已过期。"
        case .untrustedCertificate:
            "无法信任企业服务器的安全证书。"
        case let .connectionFailed(message):
            "无法连接企业 GitHub：\(message)"
        }
    }
}

public struct EnterpriseEndpoint: Equatable, Sendable {
    public let serverURL: URL
    public let apiBaseURL: URL

    public init(
        serverURL: URL,
        allowsInsecureLocalhost: Bool = false
    ) throws {
        guard var components = URLComponents(
            url: serverURL,
            resolvingAgainstBaseURL: false
        ), let scheme = components.scheme?.lowercased(),
           let host = components.host?.lowercased(),
           !host.isEmpty else {
            throw EnterpriseConnectionError.invalidServerURL
        }

        let isLocalhost = host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
        guard scheme == "https" || (allowsInsecureLocalhost && isLocalhost) else {
            throw EnterpriseConnectionError.insecureServerURL
        }

        components.scheme = scheme
        components.host = host
        components.path = "/"
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil

        guard let normalizedServerURL = components.url,
              let apiBaseURL = URL(
                  string: "api/v3/",
                  relativeTo: normalizedServerURL
              )?.absoluteURL else {
            throw EnterpriseConnectionError.invalidServerURL
        }

        self.serverURL = normalizedServerURL
        self.apiBaseURL = apiBaseURL
    }
}

public final class EnterpriseConnectionService: EnterpriseConnecting, @unchecked Sendable {
    private let session: URLSession
    private let allowsInsecureLocalhost: Bool

    public init(
        session: URLSession = .shared,
        allowsInsecureLocalhost: Bool = false
    ) {
        self.session = session
        self.allowsInsecureLocalhost = allowsInsecureLocalhost
    }

    public func verify(serverURL: URL, token: String) async throws -> GitHubAccount {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EnterpriseConnectionError.missingToken
        }
        let endpoint = try EnterpriseEndpoint(
            serverURL: serverURL,
            allowsInsecureLocalhost: allowsInsecureLocalhost
        )
        let api = URLSessionGitHubAPI(
            session: session,
            apiBaseURL: endpoint.apiBaseURL,
            serverURL: endpoint.serverURL,
            accountKind: .enterprise
        )

        do {
            return try await api.currentUser(token: token)
        } catch GitHubAPIError.httpStatus(401, _) {
            throw EnterpriseConnectionError.authorizationExpired
        } catch let error as URLError where Self.isCertificateError(error) {
            throw EnterpriseConnectionError.untrustedCertificate
        } catch let error as EnterpriseConnectionError {
            throw error
        } catch {
            throw EnterpriseConnectionError.connectionFailed(error.localizedDescription)
        }
    }

    private static func isCertificateError(_ error: URLError) -> Bool {
        switch error.code {
        case .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            true
        default:
            false
        }
    }
}
