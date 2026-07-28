import Foundation

public enum GitHubAccountKind: String, Codable, Sendable {
    case githubDotCom
    case enterprise
}

public struct GitHubAccount: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let login: String
    public let name: String?
    public let avatarURL: URL?
    public let serverURL: URL
    public let kind: GitHubAccountKind
    public let scopes: Set<String>

    public init(
        id: String,
        login: String,
        name: String?,
        avatarURL: URL?,
        serverURL: URL,
        kind: GitHubAccountKind,
        scopes: Set<String>
    ) {
        self.id = id
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
        self.serverURL = serverURL
        self.kind = kind
        self.scopes = scopes
    }
}
