import Foundation
import GitMateCore

let commitGraphSceneReconcilerTests = [
    TestCase("刷新对账保留场景并安全解散不足两个成员的分组") {
        let groupID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let region = CommitGraphRegionMarker(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            title: "2.0",
            colorHex: "#1473E6",
            rect: GraphRect(x: 1, y: 2, width: 300, height: 400)
        )
        let group = CommitGraphGroup(
            id: groupID,
            title: "稳定版本",
            memberHashes: ["a", "b"],
            source: .manual,
            origin: GraphPoint(x: 100, y: 200),
            relativePositions: [
                "a": GraphPoint(x: 20, y: 30),
                "b": GraphPoint(x: 40, y: 60)
            ],
            isCollapsed: true
        )
        let scene = CommitGraphSceneState(
            nodePositions: [
                "a": GraphPoint(x: 999, y: 999),
                "outside": GraphPoint(x: 9, y: 9)
            ],
            groups: [group],
            regions: [region]
        )

        let reconciled = CommitGraphSceneReconciler.reconcile(
            scene: scene,
            oldSnapshot: reconcileSnapshot(hashes: ["a", "b", "outside"]),
            newSnapshot: reconcileSnapshot(hashes: ["a"]),
            defaultPositions: ["a": GraphPoint(x: 10, y: 20)]
        )

        try expectEqual(reconciled.groups, [], "单成员分组必须解散")
        try expectEqual(
            reconciled.nodePositions["a"],
            GraphPoint(x: 120, y: 230),
            "剩余节点必须保留分组内绝对位置"
        )
        try expectEqual(reconciled.regions, [region], "版本区域必须保留")
        try expectEqual(
            reconciled.nodePositions["outside"],
            nil,
            "已删除提交的位置必须清理"
        )
    },
    TestCase("有效分组保持折叠状态且成员只保留相对坐标") {
        let groupID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let group = CommitGraphGroup(
            id: groupID,
            title: "功能分组",
            memberHashes: ["a", "b", "deleted"],
            source: .branchSuggestion,
            origin: GraphPoint(x: 300, y: 400),
            relativePositions: [
                "a": GraphPoint(x: 10, y: 20),
                "b": GraphPoint(x: 30, y: 40),
                "deleted": GraphPoint(x: 50, y: 60)
            ],
            isCollapsed: true
        )
        let scene = CommitGraphSceneState(
            nodePositions: [
                "a": GraphPoint(x: 1, y: 1),
                "b": GraphPoint(x: 2, y: 2)
            ],
            groups: [group],
            lineStyle: .orthogonal
        )

        let reconciled = CommitGraphSceneReconciler.reconcile(
            scene: scene,
            oldSnapshot: reconcileSnapshot(hashes: ["a", "b", "deleted"]),
            newSnapshot: reconcileSnapshot(hashes: ["a", "b", "new"]),
            defaultPositions: ["new": GraphPoint(x: 70, y: 80)]
        )

        try expectEqual(reconciled.groups.count, 1, "双成员分组必须保留")
        try expectEqual(reconciled.groups[0].id, groupID, "分组身份必须稳定")
        try expectEqual(reconciled.groups[0].isCollapsed, true, "折叠状态必须保留")
        try expectEqual(reconciled.groups[0].origin, group.origin, "分组原点必须保留")
        try expectEqual(
            reconciled.groups[0].relativePositions,
            [
                "a": GraphPoint(x: 10, y: 20),
                "b": GraphPoint(x: 30, y: 40)
            ],
            "分组成员必须沿用相对坐标"
        )
        try expectEqual(reconciled.nodePositions["a"], nil, "分组成员不得拥有第二份位置")
        try expectEqual(reconciled.nodePositions["b"], nil, "分组成员不得拥有第二份位置")
        try expectEqual(
            reconciled.nodePositions["new"],
            GraphPoint(x: 70, y: 80),
            "新提交必须采用默认位置"
        )
        try expectEqual(reconciled.lineStyle, .orthogonal, "线型设置必须保留")
    },
    TestCase("对账会清理重叠成员以禁止分组嵌套或交叠") {
        let first = CommitGraphGroup(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            title: "第一组",
            memberHashes: ["a", "b"],
            source: .manual,
            origin: GraphPoint(x: 0, y: 0),
            relativePositions: [
                "a": GraphPoint(x: 10, y: 10),
                "b": GraphPoint(x: 20, y: 20)
            ],
            isCollapsed: false
        )
        let second = CommitGraphGroup(
            id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            title: "第二组",
            memberHashes: ["b", "c"],
            source: .manual,
            origin: GraphPoint(x: 100, y: 100),
            relativePositions: [
                "b": GraphPoint(x: 10, y: 10),
                "c": GraphPoint(x: 20, y: 20)
            ],
            isCollapsed: false
        )

        let reconciled = CommitGraphSceneReconciler.reconcile(
            scene: CommitGraphSceneState(groups: [first, second]),
            oldSnapshot: reconcileSnapshot(hashes: ["a", "b", "c"]),
            newSnapshot: reconcileSnapshot(hashes: ["a", "b", "c"]),
            defaultPositions: [
                "a": GraphPoint(x: 1, y: 1),
                "b": GraphPoint(x: 2, y: 2),
                "c": GraphPoint(x: 3, y: 3)
            ]
        )

        try expectEqual(reconciled.groups.count, 1, "重叠后的单成员分组必须解散")
        try expectEqual(reconciled.groups[0].id, first.id, "先存在的分组必须优先保留")
        try expectEqual(
            reconciled.nodePositions["c"],
            GraphPoint(x: 120, y: 120),
            "被解散分组的剩余成员必须保留绝对位置"
        )
    },
    TestCase("对账只复用仍存在跨组关系的稳定端口") {
        let groupID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let group = CommitGraphGroup(
            id: groupID,
            title: "发布组",
            memberHashes: ["a", "b"],
            source: .manual,
            origin: GraphPoint(x: 0, y: 0),
            relativePositions: [
                "a": GraphPoint(x: 10, y: 10),
                "b": GraphPoint(x: 20, y: 20)
            ],
            isCollapsed: true
        )
        let stableKey = CollapsedEdgeKey(
            groupID: groupID,
            externalNodeID: "c",
            direction: .leavingGroup
        )
        let internalKey = CollapsedEdgeKey(
            groupID: groupID,
            externalNodeID: "b",
            direction: .leavingGroup
        )
        let ports = CommitGraphEdgePorts(
            source: PortAnchor(side: .right, offset: 0.25),
            target: PortAnchor(side: .left, offset: 0.75)
        )
        let scene = CommitGraphSceneState(
            groups: [group],
            boundaryPorts: [stableKey: ports, internalKey: ports]
        )

        let reconciled = CommitGraphSceneReconciler.reconcile(
            scene: scene,
            oldSnapshot: reconcileSnapshot(
                commits: [
                    reconcileCommit(hash: "a", parents: ["c"]),
                    reconcileCommit(hash: "b"),
                    reconcileCommit(hash: "c")
                ]
            ),
            newSnapshot: reconcileSnapshot(
                commits: [
                    reconcileCommit(hash: "a", parents: ["c"]),
                    reconcileCommit(hash: "b"),
                    reconcileCommit(hash: "c")
                ]
            ),
            defaultPositions: [:]
        )

        try expectEqual(
            reconciled.boundaryPorts,
            [stableKey: ports],
            "聚合键未变化的端口必须复用，组内伪边必须清理"
        )
    }
]

private func reconcileSnapshot(hashes: [String]) -> CommitGraphSnapshot {
    reconcileSnapshot(commits: hashes.map { reconcileCommit(hash: $0) })
}

private func reconcileSnapshot(
    commits: [GitCommit]
) -> CommitGraphSnapshot {
    return CommitGraphSnapshot(
        repositoryPath: "/repo",
        fingerprint: CommitGraphReferenceFingerprint(
            references: [],
            headName: nil,
            headHash: nil,
            isShallow: false
        ),
        commitsNewestFirst: commits,
        expectedCommitCount: commits.count,
        shallowBoundaryParentHashes: [],
        generatedAt: Date(timeIntervalSince1970: 1)
    )
}

private func reconcileCommit(
    hash: String,
    parents: [String] = []
) -> GitCommit {
    GitCommit(
        shortHash: hash,
        fullHash: hash,
        subject: "提交 \(hash)",
        authorName: "测试用户",
        authorEmail: "test@example.com",
        authoredAt: Date(timeIntervalSince1970: 1),
        parentHashes: parents,
        decorations: []
    )
}
