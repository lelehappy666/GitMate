import Foundation

public final class CommandLocalGitReader: LocalGitReading, @unchecked Sendable {
    private static let logFormat =
        "--format=%h%x1f%H%x1f%s%x1f%an%x1f%ae%x1f%aI%x1f%P%x1f%D%x1e"
    private static let showFormat =
        "--format=%h%x1f%H%x1f%s%x1f%an%x1f%ae%x1f%aI%x1f%P%x1f%D%x1f%B%x1f%G?%x1f%GS%x1e"

    private let executor: any CommandExecuting

    public init(executor: any CommandExecuting = ProcessCommandExecutor()) {
        self.executor = executor
    }

    public func status(repositoryURL: URL) async throws -> LocalRepositoryStatus {
        let repositoryPath = try validatedRepositoryPath(repositoryURL)
        let output = try decode(
            await execute([
                "-C", repositoryPath, "status", "--porcelain=v2", "--branch", "-z"
            ]),
            context: "状态"
        )
        return try GitOutputParser.parseStatus(output)
    }

    public func tree(
        repositoryURL: URL,
        revision: String,
        path: String
    ) async throws -> [GitFileEntry] {
        let repositoryPath = try validatedRepositoryPath(repositoryURL)
        try validateRevision(revision)
        guard GitOutputParser.isSafeRelativePath(path, allowsEmpty: true) else {
            throw LocalGitReaderError.invalidPath(path)
        }
        let pathspec = path.isEmpty ? "." : path
        let output = try decode(
            await execute([
                "-C", repositoryPath, "ls-tree", "-z", "-l",
                revision, "--", pathspec
            ]),
            context: "文件树"
        )
        return try GitOutputParser.parseTree(output)
    }

    public func file(
        repositoryURL: URL,
        revision: String,
        path: String
    ) async throws -> GitFileContent {
        let repositoryPath = try validatedRepositoryPath(repositoryURL)
        try validateRevision(revision)
        guard GitOutputParser.isSafeRelativePath(path) else {
            throw LocalGitReaderError.invalidPath(path)
        }
        let data = try await execute([
            "-C", repositoryPath, "show", "\(revision):\(path)"
        ])
        let decodedText = String(data: data, encoding: .utf8)
        let isBinary = data.contains(0) || decodedText == nil
        return GitFileContent(
            path: path,
            data: data,
            text: isBinary ? nil : decodedText,
            byteCount: data.count,
            isBinary: isBinary
        )
    }

    public func commits(
        repositoryURL: URL,
        cursor: String?,
        limit: Int
    ) async throws -> GitCommitPage {
        let result = try await readCommitPage(
            repositoryURL: repositoryURL,
            cursor: cursor,
            limit: limit
        )
        return GitCommitPage(
            commits: result.commits,
            nextCursor: result.nextCursor
        )
    }

    public func commit(
        repositoryURL: URL,
        hash: String
    ) async throws -> GitCommitDetail {
        try await readShow(repositoryURL: repositoryURL, hash: hash).detail
    }

    public func diff(
        repositoryURL: URL,
        hash: String
    ) async throws -> GitDiff {
        try await readShow(repositoryURL: repositoryURL, hash: hash).diff
    }

    public func graph(
        repositoryURL: URL,
        cursor: String?,
        limit: Int
    ) async throws -> CommitGraphPage {
        let result = try await readCommitPage(
            repositoryURL: repositoryURL,
            cursor: cursor,
            limit: limit
        )
        return CommitGraphPage(
            commits: result.commits,
            nextCursor: result.nextCursor
        )
    }

    private func readCommitPage(
        repositoryURL: URL,
        cursor: String?,
        limit: Int
    ) async throws -> (commits: [GitCommit], nextCursor: String?) {
        let repositoryPath = try validatedRepositoryPath(repositoryURL)
        guard (1...200).contains(limit) else {
            throw LocalGitReaderError.invalidLimit(limit)
        }
        let offset = try validatedOffset(cursor)
        var arguments = [
            "-C", repositoryPath, "log", Self.logFormat, "-n", String(limit)
        ]
        if offset > 0 {
            arguments.append(contentsOf: ["--skip", String(offset)])
        }
        let commits = try GitOutputParser.parseCommits(
            decode(await execute(arguments), context: "提交列表")
        )
        let nextCursor = commits.count == limit
            ? String(offset + commits.count)
            : nil
        return (commits, nextCursor)
    }

    private func readShow(
        repositoryURL: URL,
        hash: String
    ) async throws -> ParsedGitShow {
        let repositoryPath = try validatedRepositoryPath(repositoryURL)
        try validateRevision(hash)
        let output = try decode(
            await execute([
                "-C", repositoryPath, "show", Self.showFormat,
                "--numstat", "--patch", hash
            ]),
            context: "提交详情"
        )
        return try GitOutputParser.parseShow(output)
    }

    private func execute(_ arguments: [String]) async throws -> Data {
        var data = Data()
        for try await output in executor.execute(
            arguments: arguments,
            environment: [:]
        ) {
            switch output {
            case let .standardOutput(value):
                data.append(contentsOf: value.utf8)
            case let .standardOutputData(value):
                data.append(value)
            case .standardError, .standardErrorData:
                break
            }
        }
        return data
    }

    private func decode(_ data: Data, context: String) throws -> String {
        guard let output = String(data: data, encoding: .utf8) else {
            throw GitOutputParsingError.invalidUTF8(context)
        }
        return output
    }

    private func validatedRepositoryPath(_ repositoryURL: URL) throws -> String {
        guard repositoryURL.isFileURL, repositoryURL.path.hasPrefix("/") else {
            throw LocalGitReaderError.invalidRepositoryURL(
                repositoryURL.absoluteString
            )
        }
        return repositoryURL.standardizedFileURL.path
    }

    private func validateRevision(_ revision: String) throws {
        let allowedPunctuation = CharacterSet(charactersIn: "._/-^~@{}")
        guard !revision.isEmpty,
              !revision.hasPrefix("-"),
              revision.unicodeScalars.allSatisfy({
                  $0.isASCII
                      && (CharacterSet.alphanumerics.contains($0)
                          || allowedPunctuation.contains($0))
              })
        else {
            throw LocalGitReaderError.invalidRevision(revision)
        }
    }

    private func validatedOffset(_ cursor: String?) throws -> Int {
        guard let cursor else { return 0 }
        guard !cursor.isEmpty,
              cursor.unicodeScalars.allSatisfy({
                  $0.isASCII && CharacterSet.decimalDigits.contains($0)
              }),
              let offset = Int(cursor),
              offset >= 0
        else {
            throw LocalGitReaderError.invalidCursor(cursor)
        }
        return offset
    }
}
