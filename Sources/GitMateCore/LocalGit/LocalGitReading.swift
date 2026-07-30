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
    /// 分页读取全部本地与远程分支提交，每页按最早到最新排列。
    func commits(
        repositoryURL: URL,
        cursor: String?,
        limit: Int
    ) async throws -> GitCommitPage
    /// 读取全部本地与远程分支中的最近提交，按最新到最早排列。
    func recentCommits(
        repositoryURL: URL,
        limit: Int
    ) async throws -> [GitCommit]
    func commit(repositoryURL: URL, hash: String) async throws -> GitCommitDetail
    func diff(repositoryURL: URL, hash: String) async throws -> GitDiff
    func graph(
        repositoryURL: URL,
        cursor: String?,
        limit: Int
    ) async throws -> CommitGraphPage
}

public extension LocalGitReading {
    func recentCommits(
        repositoryURL: URL,
        limit: Int
    ) async throws -> [GitCommit] {
        guard (1...200).contains(limit) else {
            throw LocalGitReaderError.invalidLimit(limit)
        }

        var cursor: String?
        var recent: [GitCommit] = []
        var visitedCursors: Set<String> = []
        repeat {
            let page = try await commits(
                repositoryURL: repositoryURL,
                cursor: cursor,
                limit: 200
            )
            recent.append(contentsOf: page.commits)
            recent = Array(
                Dictionary(
                    recent.map { ($0.fullHash, $0) },
                    uniquingKeysWith: { current, _ in current }
                )
                .values
                .sorted(by: isNewerCommit)
                .prefix(limit)
            )

            guard let nextCursor = page.nextCursor,
                  visitedCursors.insert(nextCursor).inserted
            else {
                cursor = nil
                continue
            }
            cursor = nextCursor
        } while cursor != nil
        return recent
    }

    private func isNewerCommit(_ lhs: GitCommit, _ rhs: GitCommit) -> Bool {
        if lhs.authoredAt != rhs.authoredAt {
            return lhs.authoredAt > rhs.authoredAt
        }
        return lhs.fullHash < rhs.fullHash
    }
}
