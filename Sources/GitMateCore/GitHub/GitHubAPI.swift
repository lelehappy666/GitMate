public struct GitHubRepositoryPage: Equatable, Sendable {
    public let repositories: [Repository]
    public let page: Int
    public let hasNextPage: Bool

    public init(
        repositories: [Repository],
        page: Int,
        hasNextPage: Bool
    ) {
        self.repositories = repositories
        self.page = page
        self.hasNextPage = hasNextPage
    }
}

public protocol GitHubAPI: Sendable {
    func currentUser(token: String) async throws -> GitHubAccount
    func repositories(token: String) async throws -> [Repository]
    func repositoryPage(
        token: String,
        page: Int,
        perPage: Int
    ) async throws -> GitHubRepositoryPage
}
