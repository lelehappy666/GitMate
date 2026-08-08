import Foundation
import GitMateCore

let commitGraphLayoutTests = [
    TestCase("同一提交页重复布局结果稳定") {
        let page = CommitGraphPage(
            commits: [
                graphCommit(
                    hash: "merge",
                    parents: ["main-parent", "feature-parent"]
                ),
                graphCommit(hash: "main-parent", parents: ["base"]),
                graphCommit(hash: "feature-parent", parents: ["base"]),
                graphCommit(hash: "base")
            ],
            nextCursor: nil
        )

        let first = CommitGraphLayout().layout(page: page)
        let second = CommitGraphLayout().layout(page: page)

        try expectEqual(first, second, "相同输入必须产生完全相同的节点和边")
    },
    TestCase("合并提交为每个父提交生成边") {
        let page = CommitGraphPage(
            commits: [
                graphCommit(
                    hash: "merge",
                    parents: ["main-parent", "feature-parent"]
                ),
                graphCommit(hash: "main-parent"),
                graphCommit(hash: "feature-parent")
            ],
            nextCursor: nil
        )

        let result = CommitGraphLayout().layout(page: page)
        let mergeEdges = result.edges.filter { $0.childHash == "merge" }

        try expectEqual(mergeEdges.count, 2, "双父提交必须生成两条关系边")
        try expect(
            mergeEdges.contains { $0.kind == .merge },
            "额外父提交的边必须明确标记为合并关系"
        )
    },
    TestCase("不同分支使用不同稳定列") {
        let page = CommitGraphPage(
            commits: [
                graphCommit(
                    hash: "main",
                    parents: ["base"],
                    decorations: ["HEAD -> main"]
                ),
                graphCommit(
                    hash: "feature",
                    parents: ["base"],
                    decorations: ["feature/sync"]
                ),
                graphCommit(hash: "base")
            ],
            nextCursor: nil
        )

        let result = CommitGraphLayout().layout(page: page)
        let mainColumn = result.nodes.first { $0.hash == "main" }?.column
        let featureColumn = result.nodes.first { $0.hash == "feature" }?.column

        try expect(mainColumn != featureColumn, "并行分支节点不得落在同一列")
    },
    TestCase("父提交优先页面将分支稳定布局在不同泳道") {
        let page = CommitGraphPage(
            commits: [
                graphCommit(hash: "root"),
                graphCommit(hash: "feature", parents: ["root"]),
                graphCommit(hash: "main", parents: ["root"]),
                graphCommit(hash: "merge", parents: ["feature", "main"])
            ],
            nextCursor: nil
        )

        let result = CommitGraphLayout().layout(page: page)
        guard let rootNode = result.nodes.first(where: { $0.hash == "root" }),
              let featureNode = result.nodes.first(where: { $0.hash == "feature" }),
              let mainNode = result.nodes.first(where: { $0.hash == "main" }),
              let mergeNode = result.nodes.first(where: { $0.hash == "merge" })
        else {
            throw TestFailure(description: "父提交优先页面必须包含所有提交节点")
        }

        try expect(
            rootNode.y < featureNode.y
                && rootNode.y < mainNode.y
                && featureNode.y < mergeNode.y
                && mainNode.y < mergeNode.y,
            "父提交必须位于所有子提交上方"
        )
        try expect(
            featureNode.column != mainNode.column,
            "同一父提交的不同分支必须进入不同泳道"
        )
        try expectEqual(
            mergeNode.column,
            featureNode.column,
            "合并提交必须继承第一父提交泳道"
        )
    },
    TestCase("画布布局反转共享拓扑行且不改变泳道") {
        let snapshot = layoutBranchingSnapshot()
        let topology = CommitGraphLaneTopology.build(snapshot: snapshot)

        let canvas = CommitGraphLayout().layout(topology: topology)
        let traditional = CommitGraphTraditionalLayout().layout(
            topology: topology
        )

        try expectEqual(
            canvas.nodes.map(\.hash),
            ["root", "main", "feature", "merge"],
            "画布必须最早提交在上"
        )
        try expectEqual(
            canvas.node(hash: "merge")?.column,
            topology.row(hash: "merge")?.lane,
            "画布和传统布局必须共用稳定泳道"
        )
        try expectEqual(canvas.node(hash: "merge")?.column, 0, "主分支必须保持核心泳道")
        for row in traditional.rows {
            try expectEqual(
                canvas.node(hash: row.commit.fullHash)?.column,
                row.lane,
                "传统和画布布局必须复用同一份泳道结果"
            )
        }
    },
    TestCase("画布布局以主分支为树干并让相邻分支向两侧生长") {
        let snapshot = layoutTreeBranchSnapshot()
        let topology = CommitGraphLaneTopology.build(snapshot: snapshot)

        let canvas = CommitGraphLayout().layout(topology: topology)
        guard let trunk = canvas.nodes.first(where: { $0.column == 0 }),
              let leftBranch = canvas.nodes.first(where: { $0.column == 1 }),
              let rightBranch = canvas.nodes.first(where: { $0.column == 2 })
        else {
            throw TestFailure(description: "树枝布局必须包含主干和左右分支")
        }

        try expect(leftBranch.x < trunk.x, "第一条分支必须从主干向左生长")
        try expect(rightBranch.x > trunk.x, "第二条分支必须从主干向右生长")
        try expectEqual(
            trunk.x - leftBranch.x,
            rightBranch.x - trunk.x,
            "左右树枝必须围绕主干保持对称间距"
        )
    },
    TestCase("画布布局将浅克隆缺失父提交建模为边界端点") {
        let snapshot = shallowBoundarySnapshot()

        let result = CommitGraphLayout().layout(
            topology: CommitGraphLaneTopology.build(snapshot: snapshot)
        )

        try expectEqual(
            result.nodes.map(\.hash),
            ["boundary", "tip"],
            "画布节点只能包含真实提交，并且必须保持最早提交在上"
        )
        try expectEqual(
            result.nodes.count,
            snapshot.commitsNewestFirst.count,
            "浅克隆边界不得计入提交数量"
        )
        try expectEqual(
            result.shallowBoundaryEndpoints.map(\.missingParentHash),
            ["missing-parent"],
            "缺失父哈希必须以独立边界端点保留"
        )
        guard let boundary = result.node(hash: "boundary"),
              let endpoint = result.shallowBoundaryEndpoints.first
        else {
            throw TestFailure(description: "浅克隆边界必须同时保留真实子提交和虚拟端点")
        }
        try expect(
            endpoint.y < boundary.y,
            "画布中的缺失父端点必须位于其最早可见子提交之上"
        )
    }
]

private func layoutBranchingSnapshot() -> CommitGraphSnapshot {
    let commits = [
        graphCommit(hash: "merge", parents: ["main", "feature"]),
        graphCommit(hash: "feature", parents: ["root"]),
        graphCommit(hash: "main", parents: ["root"]),
        graphCommit(hash: "root")
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

private func shallowBoundarySnapshot() -> CommitGraphSnapshot {
    let commits = [
        graphCommit(hash: "tip", parents: ["boundary"]),
        graphCommit(hash: "boundary", parents: ["missing-parent"])
    ]
    return CommitGraphSnapshot(
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
}

private func layoutTreeBranchSnapshot() -> CommitGraphSnapshot {
    let commits = [
        graphCommit(hash: "main", parents: ["root"]),
        graphCommit(hash: "left", parents: ["root"]),
        graphCommit(hash: "right", parents: ["root"]),
        graphCommit(hash: "root")
    ]
    return CommitGraphSnapshot(
        repositoryPath: "/repo",
        fingerprint: CommitGraphReferenceFingerprint(
            references: [
                CommitGraphReference(
                    name: "refs/heads/main",
                    targetHash: "main",
                    kind: .localBranch
                ),
                CommitGraphReference(
                    name: "refs/heads/left",
                    targetHash: "left",
                    kind: .localBranch
                ),
                CommitGraphReference(
                    name: "refs/remotes/origin/right",
                    targetHash: "right",
                    kind: .remoteBranch
                )
            ],
            headName: "main",
            headHash: "main",
            isShallow: false
        ),
        commitsNewestFirst: commits,
        expectedCommitCount: commits.count,
        shallowBoundaryParentHashes: [],
        generatedAt: Date(timeIntervalSince1970: 1)
    )
}

private func graphCommit(
    hash: String,
    parents: [String] = [],
    decorations: [String] = []
) -> GitCommit {
    GitCommit(
        shortHash: String(hash.prefix(7)),
        fullHash: hash,
        subject: "提交 \(hash)",
        authorName: "Lele",
        authorEmail: "lele@example.com",
        authoredAt: Date(timeIntervalSince1970: 100),
        parentHashes: parents,
        decorations: decorations
    )
}
