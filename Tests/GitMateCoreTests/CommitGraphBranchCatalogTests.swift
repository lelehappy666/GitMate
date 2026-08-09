import Foundation
import GitMateCore

let commitGraphBranchCatalogTests = [
    TestCase("分支目录使用完整引用并为默认分支保留主干") {
        let snapshot = branchCatalogSnapshot()
        let topology = CommitGraphLaneTopology.build(snapshot: snapshot)

        let catalog = CommitGraphBranchCatalog.build(
            topology: topology,
            fingerprint: snapshot.fingerprint
        )

        try expectEqual(
            catalog.branch(id: "local:main")?.side,
            .trunk,
            "HEAD 默认分支必须固定在居中主干"
        )
        try expectEqual(
            catalog.branch(id: "remote:origin/remote-only")?.source,
            .remote,
            "只存在于远程的分支也必须进入目录"
        )
        try expectEqual(
            catalog.branch(containing: "main-tip")?.id,
            "local:main",
            "主干提交必须映射到默认分支稳定身份"
        )
    },
    TestCase("相同快照重复建立分支目录结果稳定") {
        let snapshot = branchCatalogSnapshot()
        let topology = CommitGraphLaneTopology.build(snapshot: snapshot)

        let first = CommitGraphBranchCatalog.build(
            topology: topology,
            fingerprint: snapshot.fingerprint
        )
        let second = CommitGraphBranchCatalog.build(
            topology: topology,
            fingerprint: snapshot.fingerprint
        )

        try expectEqual(first, second, "分支身份、左右侧和排序不得随机变化")
        try expect(
            first.branches.contains { $0.side == .left || $0.side == .right },
            "非主干分支必须向主干两侧生长"
        )
    },
    TestCase("拓扑泳道被回收复用时分支身份仍然隔离") {
        let oldCommit = branchCatalogCommit(hash: "old-tip")
        let newCommit = branchCatalogCommit(hash: "new-tip")
        let topology = CommitGraphLaneTopology(
            rowsNewestFirst: [
                CommitGraphLaneRow(
                    commit: newCommit,
                    lane: 1,
                    colorIndex: 1,
                    connections: []
                ),
                CommitGraphLaneRow(
                    commit: oldCommit,
                    lane: 1,
                    colorIndex: 1,
                    connections: []
                )
            ],
            maximumLane: 1
        )
        let catalog = CommitGraphBranchCatalog.build(
            topology: topology,
            fingerprint: CommitGraphReferenceFingerprint(
                references: [
                    CommitGraphReference(
                        name: "refs/heads/old",
                        targetHash: "old-tip",
                        kind: .localBranch
                    ),
                    CommitGraphReference(
                        name: "refs/remotes/origin/new",
                        targetHash: "new-tip",
                        kind: .remoteBranch
                    )
                ],
                headName: nil,
                headHash: nil,
                isShallow: false
            )
        )

        try expectEqual(
            catalog.branch(containing: "old-tip")?.id,
            "local:old",
            "旧生命周期提交必须属于旧分支"
        )
        try expectEqual(
            catalog.branch(containing: "new-tip")?.id,
            "remote:origin/new",
            "同一拓扑泳道上的新分支不得与旧分支串联"
        )
        try expect(
            catalog.branch(id: "local:old")?.memberHashes
                .contains("new-tip") == false,
            "分支成员不得使用整条可回收拓扑泳道"
        )
    }
]

private func branchCatalogSnapshot() -> CommitGraphSnapshot {
    let commits = [
        branchCatalogCommit(hash: "main-tip", parents: ["base"]),
        branchCatalogCommit(hash: "remote-tip", parents: ["base"]),
        branchCatalogCommit(hash: "base")
    ]
    return CommitGraphSnapshot(
        repositoryPath: "/repo",
        fingerprint: CommitGraphReferenceFingerprint(
            references: [
                CommitGraphReference(
                    name: "refs/heads/main",
                    targetHash: "main-tip",
                    kind: .localBranch
                ),
                CommitGraphReference(
                    name: "refs/remotes/origin/remote-only",
                    targetHash: "remote-tip",
                    kind: .remoteBranch
                )
            ],
            headName: "main",
            headHash: "main-tip",
            isShallow: false
        ),
        commitsNewestFirst: commits,
        expectedCommitCount: commits.count,
        shallowBoundaryParentHashes: [],
        generatedAt: Date(timeIntervalSince1970: 1)
    )
}

private func branchCatalogCommit(
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
