import Foundation

public protocol LocalGitReading: Sendable {
    func status(repositoryURL: URL) async throws -> LocalRepositoryStatus
    func tree(
        repositoryURL: URL,
        revision: String,
        path: String
    ) async throws -> [GitFileEntry]
    func file(
        repositoryURL: URL,
        revision: String,
        path: String
    ) async throws -> GitFileContent
    func commits(
        repositoryURL: URL,
        cursor: String?,
        limit: Int
    ) async throws -> GitCommitPage
    func commit(repositoryURL: URL, hash: String) async throws -> GitCommitDetail
    func diff(repositoryURL: URL, hash: String) async throws -> GitDiff
    func graph(
        repositoryURL: URL,
        cursor: String?,
        limit: Int
    ) async throws -> CommitGraphPage
}
