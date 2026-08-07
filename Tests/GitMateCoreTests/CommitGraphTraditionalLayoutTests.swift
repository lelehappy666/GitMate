import Foundation
import GitMateCore

let commitGraphTraditionalLayoutTests = [
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
