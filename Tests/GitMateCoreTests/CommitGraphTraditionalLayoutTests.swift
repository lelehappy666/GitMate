import Foundation
import GitMateCore

let commitGraphTraditionalLayoutTests = [
    TestCase("传统布局使用完整引用表显示本地与远程分支") {
        let snapshot = laneReferenceDisplaySnapshot()
        let topology = CommitGraphLaneTopology.build(snapshot: snapshot)

        let layout = CommitGraphTraditionalLayout().layout(
            topology: topology,
            fingerprint: snapshot.fingerprint
        )

        try expect(
            layout.references(hash: "local-tip").contains {
                $0.name == "feature/local" && $0.kind == .localBranch
            },
            "本地分支必须来自完整 refs，而不是依赖日志装饰文本"
        )
        try expect(
            layout.references(hash: "remote-tip").contains {
                $0.name == "origin/remote-only" && $0.kind == .remoteBranch
            },
            "仅远程存在的分支也必须显示"
        )
    },
    TestCase("工作区状态生成独立未提交变更摘要") {
        let summary = CommitGraphWorkingTreeSummary(
            status: LocalRepositoryStatus(
                branch: "main",
                upstream: "origin/main",
                ahead: 1,
                behind: 2,
                stagedCount: 3,
                unstagedCount: 4,
                untrackedCount: 5,
                conflictCount: 1
            )
        )

        try expectEqual(summary.totalCount, 13, "未提交数量必须覆盖四类工作区变化")
        try expect(summary.hasChanges, "存在变化时必须显示工作区记录")
        try expectEqual(summary.branch, "main", "工作区记录必须保留当前分支")
    },
    TestCase("传统布局保持最新在上且与共享泳道一致") {
        let topology = CommitGraphLaneTopology.build(
            snapshot: traditionalBranchingSnapshot()
        )

        let layout = CommitGraphTraditionalLayout().layout(topology: topology)

        try expectEqual(
            layout.rows.map(\.commit.fullHash),
            ["merge", "feature", "main", "root"],
            "传统布局必须最新优先"
        )
        try expectEqual(layout.row(hash: "merge")?.row, 0, "最新提交必须在首行")
        try expectEqual(layout.row(hash: "merge")?.lane, 0, "主分支必须在核心泳道")
        try expectEqual(
            layout.row(hash: "merge")?.connections.count,
            2,
            "传统布局必须保留 Merge 全部父边"
        )
        try expectEqual(layout.maximumLane, topology.maximumLane, "布局不得重算泳道")
    },
    TestCase("传统连线索引返回穿过可见行的长边") {
        let rows = (0..<100).map { index in
            CommitGraphTraditionalRow(
                commit: traditionalCommit(hash: "commit-\(index)"),
                row: index,
                lane: index == 0 ? 0 : 1,
                colorIndex: 0,
                connections: index == 0
                    ? [CommitGraphLaneConnection(
                        childHash: "commit-0",
                        parentHash: "commit-99",
                        parentIndex: 0,
                        sourceLane: 0,
                        targetLane: 1,
                        kind: .parent,
                        colorIndex: 0
                    )]
                    : []
            )
        }
        let layout = CommitGraphTraditionalLayoutResult(
            rows: rows,
            maximumLane: 1
        )

        let connections = layout.connectionSpans(
            intersecting: 40..<50
        )

        try expectEqual(
            connections.map(\.connection.id),
            ["commit-0->commit-99#0"],
            "两个端点都在预加载区外时仍必须返回穿过连线"
        )
        try expectEqual(connections[0].sourceRow, 0, "必须保留子提交行")
        try expectEqual(connections[0].targetRow, 99, "必须保留父提交行")
    },
    TestCase("传统连线索引拒绝空范围") {
        let layout = CommitGraphTraditionalLayoutResult(
            rows: [],
            maximumLane: 0
        )

        try expectEqual(
            layout.connectionSpans(intersecting: 5..<5),
            [],
            "空查询不得返回连线"
        )
    },
    TestCase("传统引用索引保留HEAD本地远程与标签") {
        let commit = GitCommit(
            shortHash: "abcdef0",
            fullHash: "abcdef012345",
            subject: "发布",
            authorName: "Lele",
            authorEmail: "lele@example.com",
            authoredAt: Date(timeIntervalSince1970: 1),
            parentHashes: [],
            decorations: [
                "HEAD -> main",
                "origin/main",
                "refs/remotes/upstream/main",
                "tag: v2.0"
            ]
        )
        let layout = CommitGraphTraditionalLayoutResult(
            rows: [CommitGraphTraditionalRow(
                commit: commit,
                row: 0,
                lane: 0,
                colorIndex: 0,
                connections: []
            )],
            maximumLane: 0
        )

        try expectEqual(
            layout.references(hash: commit.fullHash).map(\.kind),
            [.head, .localBranch, .remoteBranch, .remoteBranch, .tag],
            "不得过滤远程分支或标签"
        )
        try expectEqual(
            layout.references(hash: commit.fullHash).map(\.name),
            ["HEAD", "main", "origin/main", "upstream/main", "v2.0"],
            "引用名称必须保持可读且顺序稳定"
        )
    },
    TestCase("传统布局将浅克隆缺失父提交建模为边界端点") {
        let commits = [
            traditionalCommit(hash: "tip", parents: ["boundary"]),
            traditionalCommit(hash: "boundary", parents: ["missing-parent"])
        ]
        let snapshot = CommitGraphSnapshot(
            repositoryPath: "/repo",
            fingerprint: CommitGraphReferenceFingerprint(
                references: [],
                headName: "main",
                headHash: "tip",
                isShallow: true
            ),
            commitsNewestFirst: commits,
            expectedCommitCount: commits.count,
            shallowBoundaryParentHashes: ["missing-parent"],
            generatedAt: Date(timeIntervalSince1970: 1)
        )

        let layout = CommitGraphTraditionalLayout().layout(
            topology: CommitGraphLaneTopology.build(snapshot: snapshot)
        )

        try expectEqual(
            layout.rows.map(\.commit.fullHash),
            ["tip", "boundary"],
            "传统布局必须保持最新提交在上"
        )
        try expectEqual(layout.rows.count, commits.count, "边界端点不得伪装成提交行")
        try expectEqual(layout.contentRowCount, 3, "边界端点必须获得独立的可滚动显示行")
        try expectEqual(
            layout.shallowBoundaryEndpoints.map(\.missingParentHash),
            ["missing-parent"],
            "传统布局必须保留缺失父哈希"
        )
        try expectEqual(
            layout.shallowBoundaryEndpoints.first?.row,
            2,
            "传统布局中的缺失父端点必须位于最旧可见提交之后"
        )
    }
]

private func traditionalBranchingSnapshot() -> CommitGraphSnapshot {
    let commits = [
        traditionalCommit(hash: "merge", parents: ["main", "feature"]),
        traditionalCommit(hash: "feature", parents: ["root"]),
        traditionalCommit(hash: "main", parents: ["root"]),
        traditionalCommit(hash: "root")
    ]
    return CommitGraphSnapshot(
        repositoryPath: "/repo",
        fingerprint: CommitGraphReferenceFingerprint(
            references: [
                CommitGraphReference(
                    name: "refs/heads/main",
                    targetHash: "merge",
                    kind: .localBranch
                ),
                CommitGraphReference(
                    name: "refs/heads/feature/sync",
                    targetHash: "feature",
                    kind: .localBranch
                )
            ],
            headName: "main",
            headHash: "merge",
            isShallow: false
        ),
        commitsNewestFirst: commits,
        expectedCommitCount: commits.count,
        shallowBoundaryParentHashes: [],
        generatedAt: Date(timeIntervalSince1970: 1)
    )
}

private func laneReferenceDisplaySnapshot() -> CommitGraphSnapshot {
    let commits = [
        traditionalCommit(hash: "local-tip", parents: ["root"]),
        traditionalCommit(hash: "remote-tip", parents: ["root"]),
        traditionalCommit(hash: "root")
    ]
    return CommitGraphSnapshot(
        repositoryPath: "/repo",
        fingerprint: CommitGraphReferenceFingerprint(
            references: [
                CommitGraphReference(
                    name: "refs/heads/feature/local",
                    targetHash: "local-tip",
                    kind: .localBranch
                ),
                CommitGraphReference(
                    name: "refs/remotes/origin/remote-only",
                    targetHash: "remote-tip",
                    kind: .remoteBranch
                )
            ],
            headName: "feature/local",
            headHash: "local-tip",
            isShallow: false
        ),
        commitsNewestFirst: commits,
        expectedCommitCount: commits.count,
        shallowBoundaryParentHashes: [],
        generatedAt: Date(timeIntervalSince1970: 1)
    )
}

private func traditionalCommit(
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
        decorations: []
    )
}
