import Foundation
import GitMateCore

let commitGraphRenderIndexTests = [
    TestCase("空间索引使用投影后的真实场景位置") {
        let original = renderIndexNode(
            hash: "moved-visible",
            x: 8_000,
            y: 8_000
        )
        let projection = CommitGraphSceneProjection(
            nodes: [
                CommitGraphVisibleNode(
                    node: original,
                    position: GraphPoint(x: 320, y: 240)
                ),
                CommitGraphVisibleNode(
                    node: renderIndexNode(
                        hash: "projected-away",
                        x: 320,
                        y: 240
                    ),
                    position: GraphPoint(x: 8_000, y: 8_000)
                )
            ],
            groups: [],
            edges: []
        )
        let index = CommitGraphRenderIndex(projection: projection)

        let visible = index.query(
            viewport: GraphViewport(),
            screenSize: GraphSize(width: 800, height: 600),
            padding: 0
        )

        try expectEqual(
            visible.nodes.map(\.id),
            ["moved-visible"],
            "可见查询必须以投影后的手动位置为唯一真值"
        )
    },
    TestCase("可见查询包含缓冲区内节点和真实分组矩形") {
        let groupID = UUID(
            uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        )!
        let projection = CommitGraphSceneProjection(
            nodes: [
                CommitGraphVisibleNode(
                    node: renderIndexNode(
                        hash: "buffered",
                        x: 0,
                        y: 0
                    ),
                    position: GraphPoint(x: 920, y: 300)
                )
            ],
            groups: [
                CommitGraphVisibleGroup(
                    id: groupID,
                    title: "真实分组",
                    rect: GraphRect(
                        x: 120,
                        y: 160,
                        width: 280,
                        height: 180
                    ),
                    memberCount: 3,
                    isCollapsed: false
                )
            ],
            edges: []
        )
        let index = CommitGraphRenderIndex(projection: projection)

        let visible = index.query(
            viewport: GraphViewport(),
            screenSize: GraphSize(width: 800, height: 600),
            padding: 180
        )

        try expectEqual(
            visible.nodes.map(\.id),
            ["buffered"],
            "屏幕缓冲区内的节点必须提前进入可见集合"
        )
        try expectEqual(
            visible.groups.map(\.id),
            [groupID],
            "分组必须按投影后的真实矩形查询"
        )
    },
    TestCase("端点离屏但路径穿过视口的连线仍然可见") {
        let edge = renderIndexEdge(
            id: "left->right",
            source: "left",
            target: "right"
        )
        let farEdge = renderIndexEdge(
            id: "far-a->far-b",
            source: "far-a",
            target: "far-b"
        )
        let projection = CommitGraphSceneProjection(
            nodes: [
                renderVisibleNode(hash: "left", x: -10_000_000, y: 300),
                renderVisibleNode(hash: "right", x: 10_000_000, y: 300),
                renderVisibleNode(hash: "far-a", x: -10_000_000, y: 1_400),
                renderVisibleNode(hash: "far-b", x: 10_000_000, y: 1_400)
            ],
            groups: [],
            edges: [edge, farEdge]
        )
        let index = CommitGraphRenderIndex(projection: projection)

        let visible = index.query(
            viewport: GraphViewport(),
            screenSize: GraphSize(width: 800, height: 600),
            padding: 0
        )

        try expectEqual(
            visible.edges.map(\.id),
            ["left->right"],
            "多级索引必须保留超长且穿过视口的边，并排除完全离屏的边"
        )
    },
    TestCase("移动节点只更新目标节点和相邻边") {
        let ports = CommitGraphEdgePorts(
            source: PortAnchor(side: .bottom, offset: 0.37),
            target: PortAnchor(side: .top, offset: 0.63)
        )
        let projection = CommitGraphSceneProjection(
            nodes: [
                renderVisibleNode(hash: "center", x: 200, y: 200),
                renderVisibleNode(hash: "parent", x: 200, y: 40),
                renderVisibleNode(hash: "child", x: 200, y: 360),
                renderVisibleNode(hash: "other-a", x: 600, y: 40),
                renderVisibleNode(hash: "other-b", x: 600, y: 200)
            ],
            groups: [],
            edges: [
                renderIndexEdge(
                    id: "center->parent",
                    source: "center",
                    target: "parent",
                    ports: ports
                ),
                renderIndexEdge(
                    id: "child->center",
                    source: "child",
                    target: "center"
                ),
                renderIndexEdge(
                    id: "other-b->other-a",
                    source: "other-b",
                    target: "other-a"
                )
            ]
        )
        var index = CommitGraphRenderIndex(projection: projection)

        let update = index.moveNode(
            hash: "center",
            to: GraphPoint(x: 300, y: 400)
        )

        try expectEqual(
            update.updatedNodeHashes,
            ["center"],
            "局部更新只能报告目标节点"
        )
        try expectEqual(
            Set(update.updatedEdgeIDs),
            Set(["center->parent", "child->center"]),
            "局部更新只能报告目标节点的相邻边"
        )
        let visible = index.query(
            viewport: GraphViewport(),
            screenSize: GraphSize(width: 900, height: 700),
            padding: 0
        )
        try expectEqual(
            visible.nodes.first { $0.id == "center" }?.position,
            GraphPoint(x: 300, y: 400),
            "移动后查询必须立即使用新位置"
        )
        try expectEqual(
            visible.edges.first { $0.id == "center->parent" }?.ports,
            ports,
            "节点移动不得改变端口 side 和 offset"
        )
    },
    TestCase("查询结果始终保持投影顺序") {
        let projection = CommitGraphSceneProjection(
            nodes: [
                renderVisibleNode(hash: "z", x: 100, y: 100),
                renderVisibleNode(hash: "a", x: 200, y: 200),
                renderVisibleNode(hash: "m", x: 300, y: 300)
            ],
            groups: [],
            edges: []
        )
        let index = CommitGraphRenderIndex(projection: projection)

        let first = index.query(
            viewport: GraphViewport(),
            screenSize: GraphSize(width: 800, height: 600),
            padding: 0
        )
        let second = index.query(
            viewport: GraphViewport(),
            screenSize: GraphSize(width: 800, height: 600),
            padding: 0
        )

        try expectEqual(first.nodes.map(\.id), ["z", "a", "m"], "首次查询顺序错误")
        try expectEqual(second.nodes.map(\.id), first.nodes.map(\.id), "重复查询顺序必须稳定")
    }
]

private func renderVisibleNode(
    hash: String,
    x: Double,
    y: Double
) -> CommitGraphVisibleNode {
    CommitGraphVisibleNode(
        node: renderIndexNode(hash: hash, x: x, y: y),
        position: GraphPoint(x: x, y: y)
    )
}

private func renderIndexNode(
    hash: String,
    x: Double,
    y: Double
) -> CommitGraphNode {
    CommitGraphNode(
        hash: hash,
        shortHash: hash,
        subject: hash,
        authorName: "Lele",
        authorEmail: "lele@example.com",
        authoredAt: .distantPast,
        decorations: [],
        column: 0,
        row: 0,
        colorIndex: 0,
        x: x,
        y: y
    )
}

private func renderIndexEdge(
    id: String,
    source: String,
    target: String,
    ports: CommitGraphEdgePorts = CommitGraphEdgePorts(
        source: PortAnchor(side: .right, offset: 0.5),
        target: PortAnchor(side: .left, offset: 0.5)
    )
) -> CommitGraphVisibleEdge {
    CommitGraphVisibleEdge(
        id: id,
        source: .node(source),
        target: .node(target),
        kind: .parent,
        colorIndex: 0,
        ports: ports,
        aggregateKey: nil,
        aggregateCount: 1,
        originalEdgeIDs: [id]
    )
}
