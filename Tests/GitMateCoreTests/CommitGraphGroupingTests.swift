import Foundation
import GitMateCore

let commitGraphGroupingTests = [
    TestCase("包含分叉与合并的连通提交允许组成分组") {
        let validation = CommitGraphGrouping.validateConnectedSelection(
            hashes: ["main-1", "feature-1", "feature-2", "merge"],
            layout: groupingLayoutFixture
        )

        try expect(validation.isConnected, "连通 Git 子图必须允许创建 Group")
        try expectEqual(
            validation.disconnectedHashes,
            [],
            "连通选择不应报告断开的提交"
        )
    },
    TestCase("互不连接的提交拒绝组成分组") {
        let validation = CommitGraphGrouping.validateConnectedSelection(
            hashes: ["main-1", "unrelated"],
            layout: groupingLayoutFixture
        )

        try expect(!validation.isConnected, "断开的提交选择必须拒绝")
        try expectEqual(
            validation.disconnectedHashes,
            ["unrelated"],
            "应稳定报告无法从首个选择到达的提交"
        )
    },
    TestCase("自动分组只生成建议并排除共享祖先") {
        let scene = CommitGraphSceneState.defaultState(
            layout: groupingLayoutFixture
        )

        let suggestions = CommitGraphGrouping.branchSuggestions(
            layout: groupingLayoutFixture,
            occupiedHashes: []
        )

        try expectEqual(scene.groups, [], "生成建议不得直接创建 Group")
        try expect(
            suggestions.allSatisfy {
                !$0.memberHashes.contains("root")
                    && !$0.memberHashes.contains("unrelated")
            },
            "共享祖先和无分支提交不得进入自动建议"
        )
        try expect(
            suggestions.contains {
                $0.branchName == "feature/sync"
                    && $0.memberHashes == Set(["feature-1", "feature-2"])
            },
            "功能分支独有的连通提交必须形成建议"
        )
    },
    TestCase("自动分组建议排除已经属于现有分组的提交") {
        let suggestions = CommitGraphGrouping.branchSuggestions(
            layout: groupingLayoutFixture,
            occupiedHashes: ["feature-1"]
        )

        try expect(
            !suggestions.contains {
                $0.memberHashes.contains("feature-1")
            },
            "已经属于 Group 的提交不得再次进入建议"
        )
    },
    TestCase("修改分组成员复用未变化聚合键的端口") {
        let groupID = UUID(
            uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )!
        var scene = CommitGraphSceneState.defaultState(
            layout: groupingLayoutFixture
        )
        scene = try CommitGraphGrouping.creatingGroup(
            id: groupID,
            title: "功能分支",
            memberHashes: ["feature-1", "feature-2"],
            source: .manual,
            layout: groupingLayoutFixture,
            scene: scene
        )
        let preservedKey = CollapsedEdgeKey(
            groupID: groupID,
            externalNodeID: "root",
            direction: .leavingGroup
        )
        let originalPorts = scene.boundaryPorts[preservedKey]

        let updated = try CommitGraphGrouping.updatingGroupMembers(
            groupID: groupID,
            memberHashes: ["feature-1", "feature-2", "merge"],
            layout: groupingLayoutFixture,
            scene: scene
        )

        try expectEqual(
            updated.boundaryPorts[preservedKey],
            originalPorts,
            "聚合键未变化时必须复用原有 side 和 offset"
        )
    },
    TestCase("重命名分组只改变标题") {
        let groupID = UUID(
            uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )!
        var scene = CommitGraphSceneState.defaultState(
            layout: groupingLayoutFixture
        )
        scene = try CommitGraphGrouping.creatingGroup(
            id: groupID,
            title: "旧名称",
            memberHashes: ["feature-1", "feature-2"],
            source: .manual,
            layout: groupingLayoutFixture,
            scene: scene
        )

        let renamed = try CommitGraphGrouping.renamingGroup(
            id: groupID,
            title: "v2 修复",
            scene: scene
        )

        try expectEqual(
            renamed.groups.first?.title,
            "v2 修复",
            "应保存新的分组标题"
        )
        try expectEqual(
            renamed.groups.first?.memberHashes,
            scene.groups.first?.memberHashes,
            "重命名不得改变分组成员"
        )
        try expectEqual(
            renamed.boundaryPorts,
            scene.boundaryPorts,
            "重命名不得重新分配端口"
        )
    },
    TestCase("删除分组恢复成员绝对坐标且不删除提交") {
        let groupID = UUID(
            uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )!
        var scene = CommitGraphSceneState.defaultState(
            layout: groupingLayoutFixture
        )
        scene = try CommitGraphGrouping.creatingGroup(
            id: groupID,
            title: "功能分支",
            memberHashes: ["feature-1", "feature-2"],
            source: .manual,
            layout: groupingLayoutFixture,
            scene: scene
        )
        let firstPosition = scene.groups[0].absolutePosition(
            for: "feature-1"
        )

        let removed = try CommitGraphGrouping.removingGroup(
            id: groupID,
            layout: groupingLayoutFixture,
            scene: scene
        )

        try expectEqual(removed.groups, [], "分组应被解散")
        try expectEqual(
            removed.nodePositions["feature-1"],
            firstPosition,
            "成员应恢复删除分组前的绝对位置"
        )
        try expect(
            removed.nodePositions["feature-2"] != nil,
            "所有分组成员都必须恢复为普通提交节点"
        )
    }
]

private let groupingLayoutFixture = CommitGraphLayoutResult(
    nodes: [
        groupingNode(
            hash: "root",
            x: 300,
            y: 80,
            decorations: ["origin/shared"]
        ),
        groupingNode(
            hash: "main-1",
            x: 180,
            y: 220,
            decorations: ["main"]
        ),
        groupingNode(
            hash: "feature-1",
            x: 430,
            y: 220,
            decorations: ["feature/sync"]
        ),
        groupingNode(
            hash: "feature-2",
            x: 430,
            y: 360,
            decorations: ["feature/sync"]
        ),
        groupingNode(
            hash: "merge",
            x: 180,
            y: 500,
            decorations: []
        ),
        groupingNode(
            hash: "unrelated",
            x: 720,
            y: 500,
            decorations: []
        )
    ],
    edges: [
        groupingEdge(child: "main-1", parent: "root"),
        groupingEdge(child: "feature-1", parent: "root"),
        groupingEdge(child: "feature-2", parent: "feature-1"),
        groupingEdge(child: "merge", parent: "main-1"),
        groupingEdge(child: "merge", parent: "feature-2", kind: .merge)
    ]
)

private func groupingNode(
    hash: String,
    x: Double,
    y: Double,
    decorations: [String]
) -> CommitGraphNode {
    CommitGraphNode(
        hash: hash,
        shortHash: String(hash.prefix(7)),
        subject: "提交 \(hash)",
        authorName: "Lele",
        authorEmail: "lele@example.com",
        authoredAt: Date(timeIntervalSince1970: y),
        decorations: decorations,
        column: Int(x / 100),
        row: Int(y / 100),
        colorIndex: 0,
        x: x,
        y: y
    )
}

private func groupingEdge(
    child: String,
    parent: String,
    kind: CommitGraphEdgeKind = .parent
) -> CommitGraphEdge {
    CommitGraphEdge(
        id: "\(child)->\(parent)",
        childHash: child,
        parentHash: parent,
        kind: kind,
        colorIndex: 0
    )
}
