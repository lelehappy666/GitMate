import Foundation
import GitMateCore

let commitGraphLaneTopologyTests = [
    TestCase("共享泳道保留主分支、分叉和 Merge 全部父边") {
        let topology = CommitGraphLaneTopology.build(
            snapshot: laneBranchingSnapshot()
        )

        try expectEqual(
            topology.rowsNewestFirst.map(\.commit.fullHash),
            ["merge", "feature", "main", "root"],
            "泳道拓扑必须保持快照的最新优先顺序"
        )
        try expectEqual(
            topology.row(hash: "merge")?.lane,
            0,
            "默认分支顶点必须使用核心泳道"
        )
        try expect(
            topology.row(hash: "feature")?.lane != 0,
            "功能分支必须使用相邻泳道"
        )
        try expectEqual(
            topology.row(hash: "merge")?.connections.count,
            2,
            "Merge 必须保留全部父边"
        )
        try expectEqual(
            topology.row(hash: "merge")?.connections.map(\.kind),
            [.parent, .merge],
            "第一父边与额外 Merge 边必须保持语义"
        )
    },
    TestCase("其他分支引用按名称稳定分配泳道") {
        let first = CommitGraphLaneTopology.build(
            snapshot: laneReferenceOrderingSnapshot(
                references: ["refs/heads/zeta", "refs/heads/alpha"]
            )
        )
        let second = CommitGraphLaneTopology.build(
            snapshot: laneReferenceOrderingSnapshot(
                references: ["refs/heads/alpha", "refs/heads/zeta"]
            )
        )

        try expectEqual(
            first.row(hash: "alpha")?.lane,
            second.row(hash: "alpha")?.lane,
            "引用输入顺序不得改变分支泳道"
        )
        try expectEqual(
            first.row(hash: "zeta")?.lane,
            second.row(hash: "zeta")?.lane,
            "引用输入顺序不得改变分支泳道"
        )
        try expectEqual(
            first.row(hash: "alpha")?.lane,
            1,
            "名称较前的非默认分支必须先获得相邻泳道"
        )
        try expectEqual(
            first.row(hash: "zeta")?.lane,
            2,
            "名称较后的非默认分支必须获得后续泳道"
        )
    },
    TestCase("50000 个线性提交使用线性数量的行和边") {
        let commitCount = 50_000
        let commits = (0..<commitCount).reversed().map { index in
            laneCommit(
                hash: "commit-\(index)",
                parents: index == 0 ? [] : ["commit-\(index - 1)"]
            )
        }
        let snapshot = laneSnapshot(
            commits: commits,
            references: [
                CommitGraphReference(
                    name: "refs/heads/main",
                    targetHash: "commit-\(commitCount - 1)",
                    kind: .localBranch
                )
            ],
            headName: "main",
            headHash: "commit-\(commitCount - 1)"
        )
        let startedAt = Date()

        let topology = CommitGraphLaneTopology.build(snapshot: snapshot)
        let elapsed = Date().timeIntervalSince(startedAt)
        let edgeCount = topology.rowsNewestFirst.reduce(0) {
            $0 + $1.connections.count
        }

        try expectEqual(
            topology.rowsNewestFirst.count,
            commitCount,
            "大仓库必须保留所有提交行"
        )
        try expectEqual(
            edgeCount,
            commitCount - 1,
            "线性历史必须保留所有父边"
        )
        try expectEqual(topology.maximumLane, 0, "线性历史不得增加泳道")
        try expect(
            elapsed < 5,
            "50000 提交泳道构建不得出现隐式 O(N²)"
        )
        print(
            "  性能证据：50000 提交共享泳道耗时 "
                + String(format: "%.3f", elapsed) + " 秒"
        )
    }
]

private func laneBranchingSnapshot() -> CommitGraphSnapshot {
    laneSnapshot(
        commits: [
            laneCommit(hash: "merge", parents: ["main", "feature"]),
            laneCommit(hash: "feature", parents: ["root"]),
            laneCommit(hash: "main", parents: ["root"]),
            laneCommit(hash: "root")
        ],
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
        headHash: "merge"
    )
}

private func laneReferenceOrderingSnapshot(
    references names: [String]
) -> CommitGraphSnapshot {
    let targetByName = [
        "refs/heads/alpha": "alpha",
        "refs/heads/zeta": "zeta"
    ]
    let references = [
        CommitGraphReference(
            name: "refs/heads/main",
            targetHash: "main",
            kind: .localBranch
        )
    ] + names.map {
        CommitGraphReference(
            name: $0,
            targetHash: targetByName[$0]!,
            kind: .localBranch
        )
    }
    return laneSnapshot(
        commits: [
            laneCommit(hash: "zeta", parents: ["root"]),
            laneCommit(hash: "alpha", parents: ["root"]),
            laneCommit(hash: "main", parents: ["root"]),
            laneCommit(hash: "root")
        ],
        references: references,
        headName: "main",
        headHash: "main"
    )
}

private func laneSnapshot(
    commits: [GitCommit],
    references: [CommitGraphReference],
    headName: String?,
    headHash: String?
) -> CommitGraphSnapshot {
    CommitGraphSnapshot(
        repositoryPath: "/repo",
        fingerprint: CommitGraphReferenceFingerprint(
            references: references,
            headName: headName,
            headHash: headHash,
            isShallow: false
        ),
        commitsNewestFirst: commits,
        expectedCommitCount: commits.count,
        shallowBoundaryParentHashes: [],
        generatedAt: Date(timeIntervalSince1970: 1)
    )
}

private func laneCommit(
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
