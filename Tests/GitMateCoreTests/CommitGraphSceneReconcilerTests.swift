import Foundation
import GitMateCore

let commitGraphSceneReconcilerTests = [
    TestCase("刷新对账保留手动位置和传统分支偏好") {
        let scene = CommitGraphSceneState(
            nodePositions: ["a": GraphPoint(x: 90, y: 120)],
            manuallyPositionedHashes: ["a", "deleted"],
            pinnedTraditionalBranchIDs: ["local:main", "remote:origin/release"],
            lastTraditionalBranchID: "remote:origin/release"
        )

        let reconciled = CommitGraphSceneReconciler.reconcile(
            scene: scene,
            oldSnapshot: reconcileSnapshot(hashes: ["a", "deleted"]),
            newSnapshot: reconcileSnapshot(hashes: ["a", "new"]),
            defaultPositions: [
                "a": GraphPoint(x: 10, y: 20),
                "new": GraphPoint(x: 30, y: 40)
            ]
        )

        try expectEqual(
            reconciled.manuallyPositionedHashes,
            Set(["a"]),
            "对账必须保留存在提交的手动位置标记"
        )
        try expectEqual(
            reconciled.nodePositions["a"],
            GraphPoint(x: 90, y: 120),
            "手动节点必须保留位置"
        )
        try expectEqual(
            reconciled.pinnedTraditionalBranchIDs,
            scene.pinnedTraditionalBranchIDs,
            "分支固定偏好必须留给分支目录阶段再对账"
        )
        try expectEqual(
            reconciled.lastTraditionalBranchID,
            scene.lastTraditionalBranchID,
            "最近分支选择不得在场景对账中丢失"
        )
    },
    TestCase("旧画布算法场景自动迁移到树枝布局且保留分组状态") {
        let groupID = UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")!
        let scene = CommitGraphSceneState(
            schemaVersion: 5,
            layoutAlgorithmVersion: 3,
            nodePositions: ["main": GraphPoint(x: 100, y: 100)],
            groups: [CommitGraphGroup(
                id: groupID,
                title: "保留的分组",
                memberHashes: ["left", "right"],
                source: .manual,
                origin: GraphPoint(x: 10, y: 20),
                relativePositions: [
                    "left": GraphPoint(x: 10, y: 10),
                    "right": GraphPoint(x: 20, y: 20)
                ],
                isCollapsed: true
            )],
            regions: [CommitGraphRegionMarker(
                title: "v2",
                colorHex: "#2F80ED",
                rect: GraphRect(x: 1, y: 2, width: 3, height: 4)
            )],
            edgePorts: [
                "main->left#0": CommitGraphEdgePorts(
                    source: PortAnchor(side: .left, offset: 0.23),
                    target: PortAnchor(side: .right, offset: 0.71)
                )
            ],
            manuallyPositionedHashes: ["main"]
        )
        let defaults = [
            "main": GraphPoint(x: 600, y: 100),
            "left": GraphPoint(x: 350, y: 200),
            "right": GraphPoint(x: 850, y: 300)
        ]

        let reconciled = CommitGraphSceneReconciler.reconcile(
            scene: scene,
            oldSnapshot: reconcileSnapshot(commits: [
                reconcileCommit(hash: "main", parents: ["left"]),
                reconcileCommit(hash: "left"),
                reconcileCommit(hash: "right")
            ]),
            newSnapshot: reconcileSnapshot(commits: [
                reconcileCommit(hash: "main", parents: ["left"]),
                reconcileCommit(hash: "left"),
                reconcileCommit(hash: "right")
            ]),
            defaultPositions: defaults
        )

        try expectEqual(
            reconciled.layoutAlgorithmVersion,
            CommitGraphSceneState.currentLayoutAlgorithmVersion,
            "迁移后必须记录树枝布局版本，避免每次刷新重排"
        )
        try expectEqual(reconciled.layoutAlgorithmVersion, 4, "组织树布局必须使用算法版本四")
        try expectEqual(
            reconciled.nodePositions["main"],
            GraphPoint(x: 100, y: 100),
            "手动节点不得因组织树升级移动"
        )
        try expectEqual(reconciled.groups.first?.isCollapsed, true, "折叠状态必须保留")
        try expectEqual(reconciled.groups.first?.title, "保留的分组", "分组名称必须保留")
        try expectEqual(reconciled.regions, scene.regions, "版本区域必须保留")
        try expectEqual(
            reconciled.groups.first?.origin,
            GraphPoint(x: 10, y: 20),
            "已有 Group 原点不得因自动布局升级移动"
        )
        try expectEqual(
            reconciled.groups.first?.relativePositions,
            [
                "left": GraphPoint(x: 10, y: 10),
                "right": GraphPoint(x: 20, y: 20)
            ],
            "Group 成员相对坐标必须保持唯一真值"
        )
        try expectEqual(
            reconciled.edgePorts["main->left#0"],
            scene.edgePorts["main->left#0"],
            "布局升级不得重新分配已保存端口"
        )
    },
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
    },
    TestCase("刷新新增跨组边时创建端口且不改变已有端口") {
        let groupID = UUID(uuidString: "12121212-1212-1212-1212-121212121212")!
        let group = CommitGraphGroup(
            id: groupID,
            title: "功能组",
            memberHashes: ["a", "b"],
            source: .manual,
            origin: GraphPoint(x: 100, y: 100),
            relativePositions: [
                "a": GraphPoint(x: 20, y: 20),
                "b": GraphPoint(x: 40, y: 40)
            ],
            isCollapsed: true
        )
        let stableKey = CollapsedEdgeKey(
            groupID: groupID,
            externalNodeID: "c",
            direction: .leavingGroup
        )
        let newKey = CollapsedEdgeKey(
            groupID: groupID,
            externalNodeID: "d",
            direction: .leavingGroup
        )
        let stablePorts = CommitGraphEdgePorts(
            source: PortAnchor(side: .bottom, offset: 0.18),
            target: PortAnchor(side: .top, offset: 0.82)
        )
        let oldSnapshot = reconcileSnapshot(
            commits: [
                reconcileCommit(hash: "a", parents: ["c"]),
                reconcileCommit(hash: "b"),
                reconcileCommit(hash: "c")
            ]
        )
        let newSnapshot = reconcileSnapshot(
            commits: [
                reconcileCommit(hash: "a", parents: ["c", "d"]),
                reconcileCommit(hash: "b"),
                reconcileCommit(hash: "c"),
                reconcileCommit(hash: "d")
            ]
        )

        let reconciled = CommitGraphSceneReconciler.reconcile(
            scene: CommitGraphSceneState(
                groups: [group],
                boundaryPorts: [stableKey: stablePorts]
            ),
            oldSnapshot: oldSnapshot,
            newSnapshot: newSnapshot,
            defaultPositions: [
                "c": GraphPoint(x: 420, y: 220),
                "d": GraphPoint(x: 520, y: 320)
            ]
        )

        try expectEqual(
            reconciled.boundaryPorts[stableKey],
            stablePorts,
            "聚合键未变化时 side 和 offset 必须原样复用"
        )
        try expect(
            reconciled.boundaryPorts[newKey] != nil,
            "新增跨组边必须创建稳定端口"
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
