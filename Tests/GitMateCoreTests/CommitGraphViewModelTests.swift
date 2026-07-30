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
    TestCase("视口模型一次应用同一显示帧的有序交互") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL
        )
        let changes: [GraphViewportChange] = [
            .zoom(
                multiplier: 1.1,
                anchor: GraphPoint(x: 120, y: 80)
            ),
            .pan(GraphPoint(x: 24, y: -16)),
            .zoom(
                multiplier: 0.9,
                anchor: GraphPoint(x: 640, y: 360)
            )
        ]
        let expected = CommitGraphViewportProjector.applying(
            changes,
            to: viewModel.viewport
        )

        viewModel.applyViewportChanges(changes)

        try expectEqual(
            viewModel.viewport,
            expected,
            "同一显示帧的交互必须按事件顺序一次应用到视口"
        )
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
    },
    TestCase("选择提交后创建分组且移动与线型切换保持固定端口") { @MainActor in
        let store = InMemoryCommitGraphSceneStore()
        let viewModel = CommitGraphViewModel(
            reader: PagedCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 42,
            sceneStore: store,
            pageSize: 2
        )
        await viewModel.load()
        await viewModel.loadOlderCommits()

        viewModel.toggleSelection(hash: "hash-a", modifiers: [.command])
        viewModel.appendSelection(hash: "hash-b")
        try expectEqual(
            viewModel.selectedHashes,
            Set(["hash-a", "hash-b"]),
            "Command 切换和 Shift 追加必须形成多选"
        )

        let groupID = try viewModel.createManualGroup(title: "同步修复")
        let groupBefore = viewModel.scene.groups.first { $0.id == groupID }
        let anchorsBefore = viewModel.scene.boundaryPorts
        let topologyBefore = viewModel.layout

        viewModel.moveGroup(
            id: groupID,
            by: GraphPoint(x: 40, y: 20)
        )
        viewModel.setLineStyle(.orthogonal)

        let groupAfter = viewModel.scene.groups.first { $0.id == groupID }
        try expectEqual(
            groupAfter?.origin,
            groupBefore.map {
                GraphPoint(x: $0.origin.x + 40, y: $0.origin.y + 20)
            },
            "移动 Group 只能平移唯一 origin"
        )
        try expectEqual(
            groupAfter?.relativePositions,
            groupBefore?.relativePositions,
            "移动 Group 不得改写成员相对坐标"
        )
        try expectEqual(
            viewModel.scene.boundaryPorts,
            anchorsBefore,
            "移动和切换线型不得改变固定端口"
        )
        try expectEqual(
            viewModel.layout,
            topologyBefore,
            "场景交互不得重新计算 Git 拓扑"
        )
    },
    TestCase("组内节点拖动只修改成员相对坐标") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: PagedCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            pageSize: 2
        )
        await viewModel.load()
        await viewModel.loadOlderCommits()
        viewModel.appendSelection(hash: "hash-a")
        viewModel.appendSelection(hash: "hash-b")
        let groupID = try viewModel.createManualGroup(title: "本地整理")
        let before = viewModel.scene.groups.first { $0.id == groupID }!
        let anchorsBefore = viewModel.scene.boundaryPorts

        viewModel.moveNode(
            hash: "hash-a",
            by: GraphPoint(x: 12, y: -8)
        )

        let after = viewModel.scene.groups.first { $0.id == groupID }!
        try expectEqual(after.origin, before.origin, "拖动成员不得移动 Group origin")
        try expectEqual(
            after.relativePositions["hash-a"],
            before.relativePositions["hash-a"].map {
                GraphPoint(x: $0.x + 12, y: $0.y - 8)
            },
            "组内成员只保存相对坐标变化"
        )
        try expectEqual(
            viewModel.scene.boundaryPorts,
            anchorsBefore,
            "拖动节点不得重新分配 Group 端口"
        )
    },
    TestCase("自动分组建议确认前不创建分组") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: PagedCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            pageSize: 2
        )
        await viewModel.load()

        await viewModel.prepareGroupSuggestions()

        try expectEqual(
            viewModel.scene.groups,
            [],
            "读取自动分组建议不得直接创建 Group"
        )
        let suggestion = try required(
            viewModel.groupSuggestions.first,
            "完整历史应产生 main 分支建议"
        )
        _ = try viewModel.confirmGroupSuggestion(id: suggestion.id)
        try expectEqual(
            viewModel.scene.groups.count,
            1,
            "仅在用户确认候选后创建 Group"
        )
        try expect(
            viewModel.scene.groups[0].memberHashes
                .isSuperset(of: ["hash-a", "hash-b", "hash-c"]),
            "确认建议应使用完整历史中的成员"
        )
    },
    TestCase("提交图恢复本地场景且保存失败不阻断交互") { @MainActor in
        let storedScene = CommitGraphSceneState(
            nodePositions: [
                "hash-a": GraphPoint(x: 720, y: 160),
                "hash-b": GraphPoint(x: 720, y: 300)
            ],
            lineStyle: .orthogonal
        )
        let store = InMemoryCommitGraphSceneStore(
            scenes: [88: storedScene],
            shouldFailSave: true
        )
        let viewModel = CommitGraphViewModel(
            reader: PagedCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 88,
            sceneStore: store,
            pageSize: 2
        )

        await viewModel.load()
        try expectEqual(
            viewModel.scene.nodePositions["hash-a"],
            GraphPoint(x: 720, y: 160),
            "加载提交历史后必须恢复仓库专属场景"
        )
        viewModel.moveNode(
            hash: "hash-a",
            by: GraphPoint(x: 20, y: 10)
        )
        await viewModel.persistSceneImmediately()

        try expectEqual(
            viewModel.scene.nodePositions["hash-a"],
            GraphPoint(x: 740, y: 170),
            "持久化失败不得回滚本地交互"
        )
        try expectEqual(
            viewModel.sceneWarningMessage,
            "画布布局暂时无法保存。",
            "保存失败应显示非阻塞稳定提示"
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

private actor InMemoryCommitGraphSceneStore: CommitGraphSceneStoring {
    enum Failure: Error {
        case save
    }

    private var scenes: [Int64: CommitGraphSceneState]
    private let shouldFailSave: Bool

    init(
        scenes: [Int64: CommitGraphSceneState] = [:],
        shouldFailSave: Bool = false
    ) {
        self.scenes = scenes
        self.shouldFailSave = shouldFailSave
    }

    func load(repositoryID: Int64) async throws -> CommitGraphSceneState? {
        scenes[repositoryID]
    }

    func save(
        _ scene: CommitGraphSceneState,
        repositoryID: Int64
    ) async throws {
        guard !shouldFailSave else { throw Failure.save }
        scenes[repositoryID] = scene
    }
}

private func required<T>(
    _ value: T?,
    _ message: String
) throws -> T {
    guard let value else {
        throw TestFailure(description: message)
    }
    return value
}
