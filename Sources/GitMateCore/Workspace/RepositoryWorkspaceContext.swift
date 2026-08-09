import Foundation

public struct RepositoryWorkspaceContext: Equatable, Codable, Sendable {
    public let account: GitHubAccount
    public let repository: Repository
    public let localDirectory: URL?
    public let tokenAccountID: String

    public init(
        account: GitHubAccount,
        repository: Repository,
        localDirectory: URL?,
        tokenAccountID: String
    ) {
        self.account = account
        self.repository = repository
        self.localDirectory = localDirectory
        self.tokenAccountID = tokenAccountID
    }
}
