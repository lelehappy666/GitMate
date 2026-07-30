import Foundation
import GitMateCore

let commitGraphViewModelTests = [
    TestCase("画布缩放限制在安全范围") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL
        )

        viewModel.zoom(by: 10, anchor: .zero)
        try expectEqual(viewModel.viewport.scale, 2, "最大缩放必须限制为 2")

        viewModel.zoom(by: 0.01, anchor: .zero)
        try expectEqual(viewModel.viewport.scale, 0.35, "最小缩放必须限制为 0.35")
    },
    TestCase("双击空白区域可适配全部提交内容") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: PagedCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            pageSize: 2
        )
        await viewModel.load()
        let screenSize = GraphSize(width: 600, height: 400)

        viewModel.fitAll(in: screenSize, padding: 40)

        let expectedScale = min(
            (screenSize.width - 80) / viewModel.layout.contentWidth,
            (screenSize.height - 80) / viewModel.layout.contentHeight
        )
        try expectEqual(
            viewModel.viewport,
            GraphViewport(
                offsetX: (
                    screenSize.width
                        - viewModel.layout.contentWidth * expectedScale
                ) / 2,
                offsetY: (
                    screenSize.height
                        - viewModel.layout.contentHeight * expectedScale
                ) / 2,
                scale: expectedScale
            ),
            "适配全部内容必须居中并保留指定边距"
        )
    },
    TestCase("切换节点时旧详情不得覆盖最新提交") { @MainActor in
        let reader = ControlledCommitGraphReader()
        let viewModel = CommitGraphViewModel(
            reader: reader,
            repositoryURL: commitGraphRepositoryURL
        )
        await viewModel.load()
        viewModel.viewport = GraphViewport(
            offsetX: 120,
            offsetY: -80,
            scale: 1.2
        )

        let first = Task { @MainActor in
            await viewModel.select(hash: "hash-a")
        }
        await reader.waitForSelection(hash: "hash-a")

        let second = Task { @MainActor in
            await viewModel.select(hash: "hash-b")
        }
        await reader.waitForSelection(hash: "hash-b")
        await reader.resumeSelection(hash: "hash-b")
        await second.value
        await reader.resumeSelection(hash: "hash-a")
        await first.value

        try expectEqual(
            viewModel.selectedCommit?.commit.fullHash,
            "hash-b",
            "取消后完成的旧详情不得覆盖最新节点"
        )
        try expectEqual(
            viewModel.selectedDiff?.commitHash,
            "hash-b",
            "取消后完成的旧差异不得覆盖最新节点"
        )
        try expectEqual(
            viewModel.viewport,
            GraphViewport(offsetX: 120, offsetY: -80, scale: 1.2),
            "选择提交不得重置画布视口"
        )
    },
    TestCase("提交分页去重且已有节点列保持稳定") { @MainActor in
        let reader = PagedCommitGraphReader()
        let viewModel = CommitGraphViewModel(
            reader: reader,
            repositoryURL: commitGraphRepositoryURL,
            pageSize: 2
        )

        await viewModel.load()
        let initialColumns = Dictionary(
            uniqueKeysWithValues: viewModel.layout.nodes.map {
                ($0.hash, $0.column)
            }
        )
        await viewModel.loadOlderCommits()

        try expectEqual(
            viewModel.layout.nodes.map(\.hash),
            ["hash-a", "hash-b", "hash-c"],
            "分页必须按完整哈希去重并保持提交顺序"
        )
        try expectEqual(
            viewModel.layout.nodes.first { $0.hash == "hash-a" }?.column,
            initialColumns["hash-a"],
            "追加分页不得移动已显示节点"
        )
        try expectEqual(
            viewModel.layout.nodes.first { $0.hash == "hash-b" }?.column,
            initialColumns["hash-b"],
            "追加分页不得移动已有父节点"
        )
    },
    TestCase("差异失败时仍保留已加载的提交详情") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: FailingDiffCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL
        )
        await viewModel.load()
        viewModel.viewport = GraphViewport(
            offsetX: 48,
            offsetY: -32,
            scale: 1.1
        )

        await viewModel.select(hash: "hash-a")

        try expectEqual(
            viewModel.selectedCommit?.commit.fullHash,
            "hash-a",
            "差异读取失败不得丢弃已成功加载的提交详情"
        )
        try expectEqual(
            viewModel.selectedDiff,
            nil,
            "差异失败时不应保留无效差异"
        )
        try expectEqual(
            viewModel.errorMessage,
            "提交详情已打开，但暂时无法读取差异。",
            "应以稳定错误提示差异模块失败"
        )
        try expectEqual(
            viewModel.viewport,
            GraphViewport(offsetX: 48, offsetY: -32, scale: 1.1),
            "差异失败不得重置画布视口"
        )
    }
]

private let commitGraphRepositoryURL = URL(
    fileURLWithPath: "/tmp/GitMateCommitGraph"
)

private protocol CommitGraphTestReading: LocalGitReading {}

private extension CommitGraphTestReading {
    func status(repositoryURL _: URL) async throws -> LocalRepositoryStatus {
        LocalRepositoryStatus(
            branch: "main",
            upstream: "origin/main",
            ahead: 0,
            behind: 0,
            stagedCount: 0,
            unstagedCount: 0,
            untrackedCount: 0,
            conflictCount: 0
        )
    }

    func tree(
        repositoryURL _: URL,
        revision _: String,
        path _: String
    ) async throws -> [GitFileEntry] {
        []
    }

    func file(
        repositoryURL _: URL,
        revision _: String,
        path: String
    ) async throws -> GitFileContent {
        throw LocalGitReaderError.invalidPath(path)
    }

    func commits(
        repositoryURL _: URL,
        cursor _: String?,
        limit _: Int
    ) async throws -> GitCommitPage {
        GitCommitPage(commits: [], nextCursor: nil)
    }

    func commit(
        repositoryURL _: URL,
        hash: String
    ) async throws -> GitCommitDetail {
        commitGraphDetail(hash: hash)
    }

    func diff(
        repositoryURL _: URL,
        hash: String
    ) async throws -> GitDiff {
        commitGraphDiff(hash: hash)
    }
}

private actor StaticCommitGraphReader: CommitGraphTestReading {
    func graph(
        repositoryURL _: URL,
        cursor _: String?,
        limit _: Int
    ) async throws -> CommitGraphPage {
        CommitGraphPage(commits: [], nextCursor: nil)
    }
}

private actor ControlledCommitGraphReader: CommitGraphTestReading {
    private var detailContinuations: [
        String: CheckedContinuation<GitCommitDetail, Error>
    ] = [:]
    private var diffContinuations: [
        String: CheckedContinuation<GitDiff, Error>
    ] = [:]

    func graph(
        repositoryURL _: URL,
        cursor _: String?,
        limit _: Int
    ) async throws -> CommitGraphPage {
        CommitGraphPage(
            commits: [
                commitGraphCommit(hash: "hash-a"),
                commitGraphCommit(hash: "hash-b")
            ],
            nextCursor: nil
        )
    }

    func commit(
        repositoryURL _: URL,
        hash: String
    ) async throws -> GitCommitDetail {
        try await withCheckedThrowingContinuation { continuation in
            detailContinuations[hash] = continuation
        }
    }

    func diff(
        repositoryURL _: URL,
        hash: String
    ) async throws -> GitDiff {
        try await withCheckedThrowingContinuation { continuation in
            diffContinuations[hash] = continuation
        }
    }

    func waitForSelection(hash: String) async {
        while detailContinuations[hash] == nil
            || diffContinuations[hash] == nil {
            await Task.yield()
        }
    }

    func resumeSelection(hash: String) {
        detailContinuations.removeValue(forKey: hash)?.resume(
            returning: commitGraphDetail(hash: hash)
        )
        diffContinuations.removeValue(forKey: hash)?.resume(
            returning: commitGraphDiff(hash: hash)
        )
    }
}

private actor PagedCommitGraphReader: CommitGraphTestReading {
    func graph(
        repositoryURL _: URL,
        cursor: String?,
        limit _: Int
    ) async throws -> CommitGraphPage {
        if cursor == nil {
            return CommitGraphPage(
                commits: [
                    commitGraphCommit(
                        hash: "hash-a",
                        parents: ["hash-b"]
                    ),
                    commitGraphCommit(
                        hash: "hash-b",
                        parents: ["hash-c"]
                    )
                ],
                nextCursor: "2"
            )
        }
        return CommitGraphPage(
            commits: [
                commitGraphCommit(
                    hash: "hash-b",
                    parents: ["hash-c"]
                ),
                commitGraphCommit(hash: "hash-c")
            ],
            nextCursor: nil
        )
    }
}

private actor FailingDiffCommitGraphReader: CommitGraphTestReading {
    func graph(
        repositoryURL _: URL,
        cursor _: String?,
        limit _: Int
    ) async throws -> CommitGraphPage {
        CommitGraphPage(
            commits: [commitGraphCommit(hash: "hash-a")],
            nextCursor: nil
        )
    }

    func diff(
        repositoryURL _: URL,
        hash _: String
    ) async throws -> GitDiff {
        throw LocalGitReaderError.invalidRevision("差异不可用")
    }
}

private func commitGraphCommit(
    hash: String,
    parents: [String] = []
) -> GitCommit {
    GitCommit(
        shortHash: String(hash.prefix(7)),
        fullHash: hash,
        subject: "提交 \(hash)",
        authorName: "Lele",
        authorEmail: "lele@example.com",
        authoredAt: Date(timeIntervalSince1970: 100),
        parentHashes: parents,
        decorations: hash == "hash-a" ? ["HEAD -> main"] : []
    )
}

private func commitGraphDetail(hash: String) -> GitCommitDetail {
    GitCommitDetail(
        commit: commitGraphCommit(hash: hash),
        message: "完整说明 \(hash)",
        signatureStatus: .verified,
        signer: "Lele"
    )
}

private func commitGraphDiff(hash: String) -> GitDiff {
    GitDiff(
        commitHash: hash,
        files: [
            GitChangedFile(
                path: "Sources/Sync.swift",
                additions: 8,
                deletions: 2,
                isBinary: false
            )
        ],
        patch: "diff --git a/Sync.swift b/Sync.swift",
        additions: 8,
        deletions: 2
    )
}
