import Foundation

public final class CommandLocalGitReader: LocalGitReading, CommitGraphSnapshotReading, @unchecked Sendable {
    public static let commitLogFormat =
        "--format=%h%x00%H%x00%s%x00%an%x00%ae%x00%aI%x00%P%x00%D%x00"
    private static let detailFormat =
        "--format=%h%x00%H%x00%s%x00%an%x00%ae%x00%aI%x00%P%x00%D%x00%G?%x00%GS%x00%B%x00"
    private static let diffFormat = "--format=%H%x00"

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
        let kind: GitFileContentKind
        if data.contains(0) {
            kind = .binary
        } else if decodedText == nil {
            kind = .invalidUTF8
        } else {
            kind = .text
        }
        return GitFileContent(
            path: path,
            data: data,
            text: kind == .text ? decodedText : nil,
            byteCount: data.count,
            kind: kind
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

    public func recentCommits(
        repositoryURL: URL,
        limit: Int
    ) async throws -> [GitCommit] {
        let repositoryPath = try validatedRepositoryPath(repositoryURL)
        guard (1...200).contains(limit) else {
            throw LocalGitReaderError.invalidLimit(limit)
        }
        let parsedCommits = try GitOutputParser.parseCommits(
            decode(
                await execute([
                    "-C", repositoryPath, "log",
                    "--branches", "--remotes", "--topo-order",
                    "--decorate=short", "-n", String(limit),
                    Self.commitLogFormat
                ]),
                context: "最近提交"
            )
        )
        var seen: Set<String> = []
        return parsedCommits.filter {
            seen.insert($0.fullHash).inserted
        }
    }

    public func commit(
        repositoryURL: URL,
        hash: String
    ) async throws -> GitCommitDetail {
        let repositoryPath = try validatedRepositoryPath(repositoryURL)
        try validateRevision(hash)
        let output = try decode(
            await execute([
                "-C", repositoryPath, "show", "--no-patch",
                Self.detailFormat, hash
            ]),
            context: "提交详情"
        )
        return try GitOutputParser.parseCommitDetail(output)
    }

    public func diff(
        repositoryURL: URL,
        hash: String
    ) async throws -> GitDiff {
        let repositoryPath = try validatedRepositoryPath(repositoryURL)
        try validateRevision(hash)
        let output = try decode(
            await execute([
                "-C", repositoryPath, "show", Self.diffFormat,
                "--numstat", "--patch", hash
            ]),
            context: "提交差异"
        )
        return try GitOutputParser.parseDiff(output)
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

    public func fingerprint(
        repositoryURL: URL
    ) async throws -> CommitGraphReferenceFingerprint {
        let repositoryPath = try validatedRepositoryPath(repositoryURL)
        let references = try GitOutputParser.parseCommitGraphReferences(
            decode(
                await execute([
                    "-C", repositoryPath, "for-each-ref",
                    "--format=%(refname)%00%(objectname)%00%(symref)%00",
                    "refs/heads", "refs/remotes"
                ]),
                context: "提交图引用"
            )
        )
        let rawHeadName = try decode(
            try await execute([
                "-C", repositoryPath, "rev-parse", "--abbrev-ref", "HEAD"
            ]),
            context: "HEAD 名称"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let headHash = try decode(
            try await execute([
                "-C", repositoryPath, "rev-parse", "HEAD"
            ]),
            context: "HEAD 哈希"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let isShallow = try GitOutputParser.parseGitBoolean(
            decode(
                await execute([
                    "-C", repositoryPath, "rev-parse", "--is-shallow-repository"
                ]),
                context: "浅克隆状态"
            )
        )

        return CommitGraphReferenceFingerprint(
            references: references,
            headName: rawHeadName == "HEAD" || rawHeadName.isEmpty
                ? nil
                : rawHeadName,
            headHash: headHash.isEmpty ? nil : headHash,
            isShallow: isShallow
        )
    }

    public func snapshot(
        repositoryURL: URL,
        fingerprint: CommitGraphReferenceFingerprint
    ) async throws -> CommitGraphSnapshot {
        let repositoryPath = try validatedRepositoryPath(repositoryURL)
        let expectedCommitCount = try GitOutputParser.parseCommitCount(
            decode(
                await execute([
                    "-C", repositoryPath, "rev-list",
                    "--branches", "--remotes", "--count"
                ]),
                context: "提交图总数"
            )
        )
        let parsedCommits = try GitOutputParser.parseCommits(
            decode(
                await execute([
                    "-C", repositoryPath, "log",
                    "--branches", "--remotes", "--topo-order",
                    "--decorate=short", Self.commitLogFormat
                ]),
                context: "提交图完整日志"
            )
        )
        var seenHashes: Set<String> = []
        let commitsNewestFirst = parsedCommits.filter {
            seenHashes.insert($0.fullHash).inserted
        }
        let shallowBoundaryParentHashes: Set<String>
        if fingerprint.isShallow {
            shallowBoundaryParentHashes = try GitOutputParser
                .parseShallowBoundaryParentHashes(
                    decode(
                        await execute([
                            "-C", repositoryPath, "rev-list", "--boundary",
                            "--branches", "--remotes"
                        ]),
                        context: "浅克隆边界"
                    )
                )
        } else {
            shallowBoundaryParentHashes = []
        }

        return CommitGraphSnapshot(
            repositoryPath: repositoryPath,
            fingerprint: fingerprint,
            commitsNewestFirst: commitsNewestFirst,
            expectedCommitCount: expectedCommitCount,
            shallowBoundaryParentHashes: shallowBoundaryParentHashes,
            generatedAt: Date()
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
        let total = try GitOutputParser.parseCommitCount(
            decode(
                await execute([
                    "-C", repositoryPath, "rev-list",
                    "--branches", "--remotes", "--count"
                ]),
                context: "提交总数"
            )
        )
        let window = oldestFirstWindow(
            total: total,
            offset: offset,
            limit: limit
        )
        let parsedCommits = try GitOutputParser.parseCommits(
            decode(
                await execute([
                    "-C", repositoryPath, "log",
                    "--branches", "--remotes", "--topo-order",
                    "--decorate=short", "--skip", String(window.skip),
                    "-n", String(window.count), Self.commitLogFormat
                ]),
                context: "提交列表"
            )
        )
        var seen: Set<String> = []
        let commits = parsedCommits.reversed().filter {
            seen.insert($0.fullHash).inserted
        }
        let nextOffset = offset + window.count
        let nextCursor = nextOffset < total
            ? String(nextOffset)
            : nil
        return (commits, nextCursor)
    }

    private func oldestFirstWindow(
        total: Int,
        offset: Int,
        limit: Int
    ) -> (skip: Int, count: Int) {
        let remaining = max(total - offset, 0)
        let count = min(limit, remaining)
        return (max(total - offset - count, 0), count)
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
