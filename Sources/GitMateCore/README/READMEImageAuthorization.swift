import Foundation

public struct READMEImageAuthorization: Sendable {
    private static let githubPublicResourceHosts: Set<String> = [
        "github.com",
        "api.github.com",
        "raw.githubusercontent.com"
    ]

    private let account: GitHubAccount
    private let accessToken: String

    public init(
        account: GitHubAccount,
        accessToken: String
    ) {
        self.account = account
        self.accessToken = accessToken
    }

    public func authorizationHeader(for imageURL: URL) -> String? {
        guard !accessToken.isEmpty,
              let imageOrigin = HTTPSOrigin(url: imageURL)
        else {
            return nil
        }

        switch account.kind {
        case .githubDotCom:
            guard Self.isGitHubPublicResourceHost(imageOrigin.host),
                  imageOrigin.port == 443
            else {
                return nil
            }
        case .enterprise:
            guard !Self.isGitHubPublicResourceHost(imageOrigin.host),
                  let serverOrigin = HTTPSOrigin(url: account.serverURL),
                  imageOrigin == serverOrigin
            else {
                return nil
            }
        }

        return "Bearer \(accessToken)"
    }

    private static func isGitHubPublicResourceHost(
        _ host: String
    ) -> Bool {
        githubPublicResourceHosts.contains(host)
            || host == "githubusercontent.com"
            || host.hasSuffix(".githubusercontent.com")
    }
}

private struct HTTPSOrigin: Equatable {
    let host: String
    let port: Int

    init?(url: URL) {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
        components.scheme?.lowercased() == "https",
        components.user == nil,
        components.password == nil,
        var host = components.host?.lowercased(),
        !host.isEmpty
        else {
            return nil
        }

        while host.hasSuffix(".") {
            host.removeLast()
        }
        guard !host.isEmpty else {
            return nil
        }

        self.host = host
        port = components.port ?? 443
    }
}
