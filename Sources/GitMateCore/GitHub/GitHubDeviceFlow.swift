import Foundation

public protocol GitHubDeviceAuthorizing: Sendable {
    func start() async throws -> DeviceCode
    func poll(deviceCode: String, interval: Int) async throws -> DeviceAccessToken
}

public struct DeviceCode: Decodable, Equatable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURI: URL
    public let expiresIn: Int
    public let interval: Int

    private enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

public struct DeviceAccessToken: Equatable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let scopes: Set<String>

    public init(accessToken: String, tokenType: String, scopes: Set<String>) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.scopes = scopes
    }
}

public struct GitHubDeviceFlow: GitHubDeviceAuthorizing, @unchecked Sendable {
    public typealias Sleeper = @Sendable (_ seconds: Int) async throws -> Void

    private let clientIDProvider: @Sendable () -> String
    private let scopes: [String]
    private let session: URLSession
    private let baseURL: URL
    private let sleeper: Sleeper

    public init(
        clientID: String,
        scopes: [String],
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://github.com")!,
        sleeper: @escaping Sleeper = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.clientIDProvider = { clientID }
        self.scopes = scopes
        self.session = session
        self.baseURL = baseURL
        self.sleeper = sleeper
    }

    public init(
        clientIDProvider: @escaping @Sendable () -> String,
        scopes: [String],
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://github.com")!,
        sleeper: @escaping Sleeper = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.clientIDProvider = clientIDProvider
        self.scopes = scopes
        self.session = session
        self.baseURL = baseURL
        self.sleeper = sleeper
    }

    public func start() async throws -> DeviceCode {
        let clientID = clientIDProvider()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            throw GitHubAPIError.invalidConfiguration("缺少 GitHub OAuth App 的客户端编号。")
        }

        let request = try makeFormRequest(
            path: "/login/device/code",
            items: [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "scope", value: scopes.joined(separator: " "))
            ]
        )
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        do {
            return try JSONDecoder().decode(DeviceCode.self, from: data)
        } catch {
            throw GitHubAPIError.decoding(error.localizedDescription)
        }
    }

    public func poll(deviceCode: String, interval: Int) async throws -> DeviceAccessToken {
        let clientID = clientIDProvider()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            throw GitHubAPIError.invalidConfiguration("缺少 GitHub OAuth App 的客户端编号。")
        }

        var pollingInterval = max(interval, 1)

        while !Task.isCancelled {
            try await sleeper(pollingInterval)
            let request = try makeFormRequest(
                path: "/login/oauth/access_token",
                items: [
                    URLQueryItem(name: "client_id", value: clientID),
                    URLQueryItem(name: "device_code", value: deviceCode),
                    URLQueryItem(
                        name: "grant_type",
                        value: "urn:ietf:params:oauth:grant-type:device_code"
                    )
                ]
            )
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)

            let payload: TokenPayload
            do {
                payload = try JSONDecoder().decode(TokenPayload.self, from: data)
            } catch {
                throw GitHubAPIError.decoding(error.localizedDescription)
            }

            if let accessToken = payload.accessToken {
                let scopes = Set(
                    (payload.scope ?? "")
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
                return DeviceAccessToken(
                    accessToken: accessToken,
                    tokenType: payload.tokenType ?? "bearer",
                    scopes: scopes
                )
            }

            switch payload.error {
            case "authorization_pending":
                continue
            case "slow_down":
                pollingInterval += max(payload.interval ?? 5, 1)
            case "expired_token":
                throw GitHubAPIError.expiredToken
            case "access_denied":
                throw GitHubAPIError.accessDenied
            case .some:
                throw GitHubAPIError.invalidResponse
            case .none:
                throw GitHubAPIError.missingAccessToken
            }
        }

        throw CancellationError()
    }

    private func makeFormRequest(path: String, items: [URLQueryItem]) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw GitHubAPIError.invalidConfiguration("GitHub 授权地址无效。")
        }
        var components = URLComponents()
        components.queryItems = items

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GitHubAPIError.httpStatus(
                response.statusCode,
                GitHubErrorPayload.message(from: data)
            )
        }
    }
}

private struct TokenPayload: Decodable {
    let accessToken: String?
    let tokenType: String?
    let scope: String?
    let error: String?
    let interval: Int?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case error
        case interval
    }
}
