import Foundation
import GitMateCore

let commitGraphTraditionalSegmentProjectionTests = [
    TestCase("主干与功能分支独有区段各自占用固定泳道") {
        let fixture = segmentFixture(
            commits: [
                segmentCommit("feature-2", parents: ["feature-1"], time: 5),
                segmentCommit("main-2", parents: ["main-1"], time: 4),
                segmentCommit("feature-1", parents: ["main-1"], time: 3),
                segmentCommit("main-1", parents: ["root"], time: 2),
                segmentCommit("root", time: 1)
            ],
            references: [
                segmentReference("refs/heads/main", "main-2", .localBranch),
                segmentReference("refs/remotes/origin/main", "main-1", .remoteBranch),
                segmentReference("refs/heads/feature/a", "feature-2", .localBranch)
            ],
            headName: "feature/a",
            headHash: "feature-2"
        )

        try expectEqual(fixture.segments.lane(for: "main-2"), 0, "主干 tip 必须位于第零泳道")
        try expectEqual(fixture.segments.lane(for: "main-1"), 0, "共享祖先必须只绘制在主干")
        try expectEqual(fixture.segments.lane(for: "root"), 0, "主干根提交不得继承当前 feature")
        try expectEqual(fixture.segments.lane(for: "feature-2"), 1, "功能分支 tip 必须在自己的泳道")
        try expectEqual(fixture.segments.lane(for: "feature-1"), 1, "功能分支独有区段不得占用主干")

        guard let relation = fixture.segments.connection(
            childHash: "feature-1",
            parentHash: "main-1"
        ) else {
            throw TestFailure(description: "功能分支必须连接回共享祖先")
        }
        try expectEqual(relation.sourceLane, 1, "关系边必须从功能分支泳道出发")
        try expectEqual(relation.targetLane, 0, "关系边必须进入主干泳道")
    },
    TestCase("没有main时零号泳道不承载任何提交") {
        let fixture = segmentFixture(
            commits: [
                segmentCommit("develop-2", parents: ["develop-1"], time: 4),
                segmentCommit("feature-1", parents: ["develop-1"], time: 3),
                segmentCommit("develop-1", parents: ["root"], time: 2),
                segmentCommit("root", time: 1)
            ],
            references: [
                segmentReference("refs/heads/develop", "develop-2", .localBranch),
                segmentReference("refs/heads/feature/a", "feature-1", .localBranch)
            ],
            headName: "develop",
            headHash: "develop-2"
        )

        try expect(
            fixture.topology.rowsNewestFirst.allSatisfy {
                fixture.segments.lane(for: $0.commit.fullHash) != 0
            },
            "没有 main 时任何提交都不得进入保留泳道"
        )
        try expectEqual(fixture.segments.lane(for: "develop-2"), 1, "当前 develop 必须从第一号真实泳道开始")
        try expectEqual(fixture.segments.lane(for: "feature-1"), 2, "功能分支必须独占下一条泳道")
    },
    TestCase("Merge非第一父边只建立关系线不改变节点泳道") {
        let fixture = segmentFixture(
            commits: [
                segmentCommit("merge", parents: ["main-1", "feature-1"], time: 4),
                segmentCommit("feature-1", parents: ["root"], time: 3),
                segmentCommit("main-1", parents: ["root"], time: 2),
                segmentCommit("root", time: 1)
            ],
            references: [
                segmentReference("refs/heads/main", "merge", .localBranch),
                segmentReference("refs/heads/feature/a", "feature-1", .localBranch)
            ],
            headName: "main",
            headHash: "merge"
        )

        try expectEqual(fixture.segments.lane(for: "merge"), 0, "Merge 提交必须保留在 main")
        try expectEqual(fixture.segments.lane(for: "feature-1"), 1, "被合并分支提交仍属于自己的泳道")
        guard let mergeEdge = fixture.segments.connection(
            childHash: "merge",
            parentHash: "feature-1"
        ) else {
            throw TestFailure(description: "Merge 的第二父边不得丢失")
        }
        try expectEqual(mergeEdge.kind, .merge, "第二父边必须保留 Merge 语义")
        try expectEqual(mergeEdge.sourceLane, 0, "Merge 从 main 发出")
        try expectEqual(mergeEdge.targetLane, 1, "Merge 连接到功能分支")
    },
    TestCase("当前HEAD变化不改变主干颜色与泳道") {
        let commits = [
            segmentCommit("feature", parents: ["main"], time: 2),
            segmentCommit("main", time: 1)
        ]
        let references = [
            segmentReference("refs/heads/main", "main", .localBranch),
            segmentReference("refs/heads/feature/a", "feature", .localBranch)
        ]
        let mainHead = segmentFixture(
            commits: commits,
            references: references,
            headName: "main",
            headHash: "main"
        )
        let featureHead = segmentFixture(
            commits: commits,
            references: references,
            headName: "feature/a",
            headHash: "feature"
        )

        try expectEqual(mainHead.segments.lane(for: "main"), 0, "main HEAD 时主干在零号泳道")
        try expectEqual(featureHead.segments.lane(for: "main"), 0, "feature HEAD 时主干仍在零号泳道")
        try expectEqual(mainHead.segments.colorIndex(for: "main"), 0, "main 颜色必须绑定零号逻辑泳道")
        try expectEqual(featureHead.segments.colorIndex(for: "main"), 0, "切换 HEAD 不得改变 main 颜色")
    }
]

private struct SegmentFixture {
    let topology: CommitGraphLaneTopology
    let segments: CommitGraphTraditionalSegmentProjection
}

private func segmentFixture(
    commits: [GitCommit],
    references: [CommitGraphReference],
    headName: String,
    headHash: String
) -> SegmentFixture {
    let snapshot = CommitGraphSnapshot(
        repositoryPath: "/tmp/segment-projection",
        fingerprint: CommitGraphReferenceFingerprint(
            references: references,
            headName: headName,
            headHash: headHash,
            isShallow: false
        ),
        commitsNewestFirst: commits,
        expectedCommitCount: commits.count,
        shallowBoundaryParentHashes: [],
        generatedAt: Date(timeIntervalSince1970: 10)
    )
    let topology = CommitGraphLaneTopology.build(snapshot: snapshot)
    let catalog = CommitGraphBranchCatalog.build(
        topology: topology,
        fingerprint: snapshot.fingerprint
    )
    let branches = CommitGraphTraditionalBranchProjector.project(
        CommitGraphTraditionalBranchProjectionInput(
            catalog: catalog,
            topology: topology,
            totalWidth: 600,
            selectedHash: nil,
            pinnedBranchIDs: [],
            lastSelectedBranchID: nil
        )
    )
    return SegmentFixture(
        topology: topology,
        segments: CommitGraphTraditionalSegmentProjector.project(
            topology: topology,
            catalog: catalog,
            branchProjection: branches
        )
    )
}

private func segmentCommit(
    _ hash: String,
    parents: [String] = [],
    time: TimeInterval
) -> GitCommit {
    GitCommit(
        shortHash: String(hash.prefix(7)),
        fullHash: hash,
        subject: hash,
        authorName: "Lele",
        authorEmail: "lele@example.com",
        authoredAt: Date(timeIntervalSince1970: time),
        parentHashes: parents,
        decorations: []
    )
}

private func segmentReference(
    _ name: String,
    _ hash: String,
    _ kind: CommitGraphReferenceKind
) -> CommitGraphReference {
    CommitGraphReference(name: name, targetHash: hash, kind: kind)
}
