import Foundation
import GitMateCore

let commitGraphOrganizationTreeLayoutTests = [
    TestCase("组织树保持父节点在上并使用双倍层级间距") {
        let topology = CommitGraphLaneTopology.build(
            snapshot: organizationTreeBranchMergeSnapshot()
        )

        let result = CommitGraphOrganizationTreeLayout().layout(
            topology: topology,
            preserving: nil
        )

        try expectEqual(
            result.nodes.map(\.hash),
            ["root", "main-1", "feature-1", "merge"],
            "组织树必须保持最早提交在上、最新提交在下"
        )
        for edge in result.edges {
            guard let child = result.node(hash: edge.childHash),
                  let parent = result.node(hash: edge.parentHash)
            else {
                throw TestFailure(description: "每条父边都必须找到两个真实节点")
            }
            try expect(
                parent.y < child.y,
                "父提交必须严格位于子提交上方"
            )
            try expect(
                child.y - parent.y >= 252,
                "父子层级必须保留至少 252 像素间距"
            )
        }
    },
    TestCase("多分支组织树为同层兄弟保留五百像素中心间距") {
        let topology = CommitGraphLaneTopology.build(
            snapshot: organizationTreeWideSnapshot(branchCount: 12)
        )

        let result = CommitGraphOrganizationTreeLayout().layout(
            topology: topology,
            preserving: nil
        )
        let siblings = result.nodes.filter { $0.hash != "root" }
            .sorted { $0.x < $1.x }

        try expectEqual(siblings.count, 12, "所有分支节点都必须进入组织树")
        for pair in zip(siblings, siblings.dropFirst()) {
            try expect(
                pair.1.x - pair.0.x >= 500,
                "相邻兄弟提交中心必须至少相距 500 像素"
            )
        }
        for (index, first) in result.nodes.enumerated() {
            for second in result.nodes.dropFirst(index + 1) {
                try expect(
                    !organizationTreeRectsIntersect(
                        organizationTreeRect(first),
                        organizationTreeRect(second)
                    ),
                    "任意两张提交卡片都不得重叠"
                )
            }
        }
    },
    TestCase("组织树保留全部Merge父边且重复布局稳定") {
        let topology = CommitGraphLaneTopology.build(
            snapshot: organizationTreeBranchMergeSnapshot()
        )
        let layout = CommitGraphOrganizationTreeLayout()

        let first = layout.layout(topology: topology, preserving: nil)
        let second = layout.layout(topology: topology, preserving: nil)

        try expectEqual(first, second, "相同完整拓扑必须产生稳定组织树")
        try expectEqual(
            first.edges.filter { $0.childHash == "merge" }.count,
            2,
            "Merge 的第一父边和额外父边都不能丢失"
        )
    }
]

private func organizationTreeBranchMergeSnapshot() -> CommitGraphSnapshot {
    organizationTreeSnapshot(
        commitsNewestFirst: [
            organizationTreeCommit(
                "merge",
                parents: ["main-1", "feature-1"]
            ),
            organizationTreeCommit("feature-1", parents: ["root"]),
            organizationTreeCommit("main-1", parents: ["root"]),
            organizationTreeCommit("root")
        ],
        references: [
            CommitGraphReference(
                name: "refs/heads/main",
                targetHash: "merge",
                kind: .localBranch
            ),
            CommitGraphReference(
                name: "refs/heads/feature/tree",
                targetHash: "feature-1",
                kind: .localBranch
            )
        ],
        headHash: "merge"
    )
}

private func organizationTreeWideSnapshot(
    branchCount: Int
) -> CommitGraphSnapshot {
    let children = (0..<branchCount).map {
        organizationTreeCommit("branch-\($0)", parents: ["root"])
    }
    let references = (0..<branchCount).map {
        CommitGraphReference(
            name: $0 == 0
                ? "refs/heads/main"
                : "refs/heads/feature/\($0)",
            targetHash: "branch-\($0)",
            kind: .localBranch
        )
    }
    return organizationTreeSnapshot(
        commitsNewestFirst: children + [organizationTreeCommit("root")],
        references: references,
        headHash: "branch-0"
    )
}

private func organizationTreeSnapshot(
    commitsNewestFirst: [GitCommit],
    references: [CommitGraphReference],
    headHash: String
) -> CommitGraphSnapshot {
    CommitGraphSnapshot(
        repositoryPath: "/organization-tree",
        fingerprint: CommitGraphReferenceFingerprint(
            references: references,
            headName: "main",
            headHash: headHash,
            isShallow: false
        ),
        commitsNewestFirst: commitsNewestFirst,
        expectedCommitCount: commitsNewestFirst.count,
        shallowBoundaryParentHashes: [],
        generatedAt: Date(timeIntervalSince1970: 1)
    )
}

private func organizationTreeCommit(
    _ hash: String,
    parents: [String] = []
) -> GitCommit {
    GitCommit(
        shortHash: String(hash.prefix(7)),
        fullHash: hash,
        subject: hash,
        authorName: "Lele",
        authorEmail: "lele@example.com",
        authoredAt: Date(timeIntervalSince1970: 1),
        parentHashes: parents,
        decorations: []
    )
}

private func organizationTreeRect(_ node: CommitGraphNode) -> GraphRect {
    GraphRect(
        x: node.x - 112,
        y: node.y - 37,
        width: 224,
        height: 74
    )
}

private func organizationTreeRectsIntersect(
    _ first: GraphRect,
    _ second: GraphRect
) -> Bool {
    first.minimumX < second.maximumX
        && first.maximumX > second.minimumX
        && first.minimumY < second.maximumY
        && first.maximumY > second.minimumY
}
