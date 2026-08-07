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
