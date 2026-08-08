import Foundation
import GitMateCore

let commitGraphSceneProjectorTests = [
    TestCase("折叠分组隐藏成员和组内连线") {
        let fixture = collapsedProjectionFixture()
        let projection = CommitGraphSceneProjector.project(
            layout: fixture.layout,
            scene: fixture.scene
        )

        try expectEqual(
            Set(projection.nodes.map(\.id)),
            Set(["outside-parent", "outside-child"]),
            "折叠后不得显示 Group 成员"
        )
        try expect(
            !projection.edges.contains {
                $0.originalEdgeIDs.contains("member-b->member-a")
            },
            "折叠后不得显示组内连线"
        )
        try expect(
            projection.groups.contains {
                $0.id == fixture.groupID && $0.isCollapsed
            },
            "折叠 Group 必须投影为可见卡片"
        )
    },
    TestCase("跨组边按外部节点与方向聚合并显示数量") {
        let fixture = collapsedProjectionFixture()
        let projection = CommitGraphSceneProjector.project(
            layout: fixture.layout,
            scene: fixture.scene
        )
        let leavingKey = CollapsedEdgeKey(
            groupID: fixture.groupID,
            externalNodeID: "outside-parent",
            direction: .leavingGroup
        )
        let enteringKey = CollapsedEdgeKey(
            groupID: fixture.groupID,
            externalNodeID: "outside-child",
            direction: .enteringGroup
        )

        try expectEqual(
            projection.edges.first { $0.aggregateKey == leavingKey }?
                .aggregateCount,
            2,
            "同一外部节点同方向的两条边必须聚合为 ×2"
        )
        try expectEqual(
            projection.edges.first { $0.aggregateKey == enteringKey }?
                .aggregateCount,
            1,
            "相反方向必须使用独立聚合键"
        )
    },
    TestCase("两个折叠分组之间只生成一条聚合边") {
        let firstID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let secondID = UUID(
            uuidString: "22222222-2222-2222-2222-222222222222"
        )!
        let layout = CommitGraphLayoutResult(
            nodes: [
                projectionNode(hash: "source", x: 100, y: 200),
                projectionNode(hash: "target", x: 400, y: 100)
            ],
            edges: [
                projectionEdge(child: "source", parent: "target")
            ]
        )
        var scene = CommitGraphSceneState.defaultState(layout: layout)
        scene.groups = [
            projectionGroup(
                id: firstID,
                members: ["source"],
                origin: GraphPoint(x: 40, y: 160),
                collapsed: true,
                layout: layout
            ),
            projectionGroup(
                id: secondID,
                members: ["target"],
                origin: GraphPoint(x: 340, y: 60),
                collapsed: true,
                layout: layout
            )
        ]
        scene = CommitGraphGrouping.rebuildingBoundaryPorts(
            layout: layout,
            scene: scene
        )

        let projection = CommitGraphSceneProjector.project(
            layout: layout,
            scene: scene
        )

        try expectEqual(
            projection.edges.count,
            1,
            "Group 到 Group 的原始边只能投影一次"
        )
        try expectEqual(
            projection.edges.first?.aggregateKey,
            CollapsedEdgeKey(
                groupID: firstID,
                externalNodeID: "group:\(secondID.uuidString)",
                direction: .leavingGroup
            ),
            "Group 到 Group 必须由 child 所在 Group 持有聚合键"
        )
    },
    TestCase("移动分组只改变原点且端口保持不变") {
        let fixture = collapsedProjectionFixture()
        let ports = fixture.scene.boundaryPorts

        let moved = CommitGraphGrouping.movingGroup(
            id: fixture.groupID,
            translation: GraphPoint(x: 80, y: -30),
            scene: fixture.scene
        )

        try expectEqual(
            moved.groups.first?.origin,
            GraphPoint(x: 100, y: -10),
            "Group 拖动必须只平移 origin"
        )
        try expectEqual(
            moved.groups.first?.relativePositions,
            fixture.scene.groups.first?.relativePositions,
            "Group 拖动不得改写成员相对坐标"
        )
        try expectEqual(
            moved.boundaryPorts,
            ports,
            "Group 拖动不得重新分配端口"
        )
    },
    TestCase("画布投影将浅克隆边界作为虚拟端点而非提交节点") {
        let relation = CommitGraphShallowBoundaryRelation(
            childHash: "boundary",
            missingParentHash: "missing-parent",
            parentIndex: 0,
            sourceLane: 0,
            targetLane: 0,
            colorIndex: 0
        )
        let layout = CommitGraphLayoutResult(
            nodes: [projectionNode(hash: "boundary", x: 150, y: 82)],
            shallowBoundaryEndpoints: [
                CommitGraphShallowBoundaryEndpoint(
                    relation: relation,
                    x: 150,
                    y: 0
                )
            ]
        )

        let projection = CommitGraphSceneProjector.project(
            layout: layout,
            scene: .defaultState(layout: layout)
        )

        try expectEqual(
            projection.nodes.map(\.id),
            ["boundary"],
            "缺失父提交不得进入普通节点列表"
        )
        try expectEqual(
            projection.shallowBoundaryEndpoints.map {
                $0.endpoint.missingParentHash
            },
            ["missing-parent"],
            "画布必须将缺失父哈希投影为独立端点"
        )
        try expect(
            projection.edges.contains {
                $0.kind == .shallowBoundary
                    && $0.source == .node("boundary")
                    && $0.target == .shallowBoundary(relation.id)
            },
            "画布必须使用独立虚拟关系连接真实子提交和边界端点"
        )
    },
    TestCase("折叠分组中的浅克隆子提交仍投影稳定边界关系") {
        let groupID = UUID(
            uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
        )!
        let relation = CommitGraphShallowBoundaryRelation(
            childHash: "boundary-child",
            missingParentHash: "missing-parent",
            parentIndex: 0,
            sourceLane: 0,
            targetLane: 0,
            colorIndex: 0
        )
        let layout = CommitGraphLayoutResult(
            nodes: [
                projectionNode(hash: "boundary-child", x: 180, y: 220),
                projectionNode(hash: "group-sibling", x: 430, y: 220)
            ],
            shallowBoundaryEndpoints: [
                CommitGraphShallowBoundaryEndpoint(
                    relation: relation,
                    x: 180,
                    y: 138
                )
            ]
        )
        var scene = CommitGraphSceneState.defaultState(layout: layout)
        scene.groups = [
            projectionGroup(
                id: groupID,
                members: ["boundary-child", "group-sibling"],
                origin: GraphPoint(x: 100, y: 160),
                collapsed: true,
                layout: layout
            )
        ]
        scene = CommitGraphGrouping.rebuildingBoundaryPorts(
            layout: layout,
            scene: scene
        )
        let key = CollapsedEdgeKey(
            groupID: groupID,
            externalNodeID: relation.collapsedExternalNodeID,
            direction: .leavingGroup
        )

        let collapsed = CommitGraphSceneProjector.project(
            layout: layout,
            scene: scene
        )

        try expectEqual(
            collapsed.nodes,
            [],
            "折叠后组内真实提交仍必须隐藏"
        )
        try expectEqual(
            collapsed.shallowBoundaryEndpoints.map(\.id),
            [relation.id],
            "边界端点不能依赖真实子节点是否可见"
        )
        guard let collapsedEdge = collapsed.edges.first(where: {
            $0.kind == .shallowBoundary
        }) else {
            throw TestFailure(description: "折叠 Group 必须保留浅克隆边界边")
        }
        try expectEqual(collapsedEdge.source, .group(groupID), "边必须从折叠 Group 发出")
        try expectEqual(
            collapsedEdge.target,
            .shallowBoundary(relation.id),
            "边必须连到独立边界端点"
        )
        try expectEqual(collapsedEdge.aggregateKey, key, "聚合键必须按 Group 与边界哈希稳定")
        try expectEqual(
            collapsedEdge.ports,
            scene.boundaryPorts[key],
            "折叠端口必须复用场景中的固定 side 与 offset"
        )

        scene.groups[0].isCollapsed = false
        let expanded = CommitGraphSceneProjector.project(
            layout: layout,
            scene: scene
        )
        try expect(
            expanded.edges.contains {
                $0.kind == .shallowBoundary
                    && $0.source == .node("boundary-child")
            },
            "展开后必须恢复真实子提交到边界的关系"
        )
    }
]

private struct CollapsedProjectionFixture {
    let groupID: UUID
    let layout: CommitGraphLayoutResult
    let scene: CommitGraphSceneState
}

private func collapsedProjectionFixture() -> CollapsedProjectionFixture {
    let groupID = UUID(
        uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    )!
    let layout = CommitGraphLayoutResult(
        nodes: [
            projectionNode(hash: "member-a", x: 180, y: 180),
            projectionNode(hash: "member-b", x: 180, y: 320),
            projectionNode(hash: "outside-parent", x: 180, y: 40),
            projectionNode(hash: "outside-child", x: 180, y: 480)
        ],
        edges: [
            projectionEdge(child: "member-a", parent: "outside-parent"),
            projectionEdge(child: "member-b", parent: "outside-parent"),
            projectionEdge(child: "member-b", parent: "member-a"),
            projectionEdge(child: "outside-child", parent: "member-b")
        ]
    )
    var scene = CommitGraphSceneState.defaultState(layout: layout)
    scene.groups = [
        projectionGroup(
            id: groupID,
            members: ["member-a", "member-b"],
            origin: GraphPoint(x: 20, y: 20),
            collapsed: true,
            layout: layout
        )
    ]
    scene = CommitGraphGrouping.rebuildingBoundaryPorts(
        layout: layout,
        scene: scene
    )
    return CollapsedProjectionFixture(
        groupID: groupID,
        layout: layout,
        scene: scene
    )
}

private func projectionGroup(
    id: UUID,
    members: Set<String>,
    origin: GraphPoint,
    collapsed: Bool,
    layout: CommitGraphLayoutResult
) -> CommitGraphGroup {
    CommitGraphGroup(
        id: id,
        title: "分组",
        memberHashes: members,
        source: .manual,
        origin: origin,
        relativePositions: Dictionary(
            uniqueKeysWithValues: members.compactMap { hash in
                guard let node = layout.node(hash: hash) else { return nil }
                return (
                    hash,
                    GraphPoint(
                        x: node.x - origin.x,
                        y: node.y - origin.y
                    )
                )
            }
        ),
        isCollapsed: collapsed
    )
}

private func projectionNode(
    hash: String,
    x: Double,
    y: Double
) -> CommitGraphNode {
    CommitGraphNode(
        hash: hash,
        shortHash: String(hash.prefix(7)),
        subject: hash,
        authorName: "Lele",
        authorEmail: "lele@example.com",
        authoredAt: Date(timeIntervalSince1970: y),
        decorations: [],
        column: Int(x / 100),
        row: Int(y / 100),
        colorIndex: 0,
        x: x,
        y: y
    )
}

private func projectionEdge(
    child: String,
    parent: String
) -> CommitGraphEdge {
    CommitGraphEdge(
        id: "\(child)->\(parent)",
        childHash: child,
        parentHash: parent,
        kind: .parent,
        colorIndex: 0
    )
}
