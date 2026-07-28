public protocol GitHubAPI: Sendable {
    func currentUser(token: String) async throws -> GitHubAccount
    func repositories(token: String) async throws -> [Repository]
}
