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
        guard case .curve? = visible.edges.first?.path else {
            throw TestFailure(description: "曲线查询必须携带已生成的穿屏路径")
        }

        var orthogonalIndex = index
        _ = orthogonalIndex.setLineStyle(.orthogonal)
        let orthogonalVisible = orthogonalIndex.query(
            viewport: GraphViewport(),
            screenSize: GraphSize(width: 800, height: 600),
            padding: 0
        )
        try expectEqual(
            orthogonalVisible.edges.map(\.id),
            ["left->right"],
            "直角连线的穿屏边也必须进入可见场景"
        )
        guard case .polyline? = orthogonalVisible.edges.first?.path else {
            throw TestFailure(description: "直角查询必须携带已生成的穿屏路径")
        }
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
    },
    TestCase("低于界面最小值的合法缩放仍按实际坐标查询") {
        let projection = CommitGraphSceneProjection(
            nodes: [
                renderVisibleNode(hash: "combined-visible", x: 760, y: 650),
                renderVisibleNode(hash: "outside", x: 1_050, y: 650)
            ],
            groups: [],
            edges: []
        )
        let index = CommitGraphRenderIndex(projection: projection)

        let visible = index.query(
            viewport: GraphViewport(
                offsetX: -40,
                offsetY: -20,
                scale: 0.2
            ),
            screenSize: GraphSize(width: 100, height: 100),
            padding: 20
        )

        try expectEqual(
            visible.nodes.map(\.id),
            ["combined-visible"],
            "scale、负平移和屏幕 padding 必须使用实际视口换算"
        )
    },
    TestCase("成员移动同步更新分组真实矩形和相关边") {
        let groupID = UUID(
            uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
        )!
        let member = renderVisibleNode(hash: "member", x: 150, y: 150)
        let external = renderVisibleNode(hash: "external", x: 800, y: 150)
        let group = renderVisibleGroup(
            id: groupID,
            title: "展开组",
            origin: GraphPoint(x: 100, y: 100),
            relativePositions: ["member": GraphPoint(x: 50, y: 50)],
            isCollapsed: false
        )
        let projection = CommitGraphSceneProjection(
            nodes: [member, external],
            groups: [group],
            edges: [
                renderIndexEdge(
                    id: "member->external",
                    source: "member",
                    target: "external"
                )
            ]
        )
        var index = CommitGraphRenderIndex(projection: projection)
        let before = index.query(
            viewport: GraphViewport(),
            screenSize: GraphSize(width: 1_200, height: 800),
            padding: 0
        ).groups[0].rect

        let update = index.moveNode(
            hash: "member",
            to: GraphPoint(x: 500, y: 420)
        )
        let after = index.query(
            viewport: GraphViewport(),
            screenSize: GraphSize(width: 1_200, height: 800),
            padding: 0
        ).groups[0]

        try expect(after.rect != before, "成员移动后 Group 矩形必须局部更新")
        try expectEqual(
            after.relativePositions["member"],
            GraphPoint(x: 400, y: 320),
            "成员位置只能保存为相对 Group origin 的坐标"
        )
        try expectEqual(
            update.updatedGroupIDs,
            [groupID],
            "成员改变 Group 几何时必须报告受影响分组"
        )
        try expectEqual(
            update.updatedEdgeIDs,
            ["member->external"],
            "成员移动只能更新其相邻边"
        )
    },
    TestCase("分组拖动更新成员和分组聚合边但保持端口") {
        let firstID = UUID(
            uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
        )!
        let secondID = UUID(
            uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD"
        )!
        let ports = CommitGraphEdgePorts(
            source: PortAnchor(side: .right, offset: 0.28),
            target: PortAnchor(side: .left, offset: 0.72)
        )
        let first = renderVisibleGroup(
            id: firstID,
            title: "第一组",
            origin: GraphPoint(x: 0, y: 0),
            relativePositions: [:],
            isCollapsed: true
        )
        let second = renderVisibleGroup(
            id: secondID,
            title: "第二组",
            origin: GraphPoint(x: 1_000, y: 0),
            relativePositions: [:],
            isCollapsed: true
        )
        let groupEdge = CommitGraphVisibleEdge(
            id: "group->group",
            source: .group(firstID),
            target: .group(secondID),
            kind: .parent,
            colorIndex: 0,
            ports: ports,
            aggregateKey: CollapsedEdgeKey(
                groupID: firstID,
                externalNodeID: "group:\(secondID.uuidString)",
                direction: .leavingGroup
            ),
            aggregateCount: 3,
            originalEdgeIDs: ["a", "b", "c"]
        )
        let groupNodeEdge = CommitGraphVisibleEdge(
            id: "group->node",
            source: .group(firstID),
            target: .node("external"),
            kind: .parent,
            colorIndex: 0,
            ports: ports,
            aggregateKey: CollapsedEdgeKey(
                groupID: firstID,
                externalNodeID: "external",
                direction: .leavingGroup
            ),
            aggregateCount: 2,
            originalEdgeIDs: ["d", "e"]
        )
        var index = CommitGraphRenderIndex(
            projection: CommitGraphSceneProjection(
                nodes: [
                    renderVisibleNode(hash: "external", x: 1_000, y: 500)
                ],
                groups: [first, second],
                edges: [groupEdge, groupNodeEdge]
            )
        )
        let oldPath = index.query(
            viewport: GraphViewport(offsetX: -350),
            screenSize: GraphSize(width: 100, height: 100),
            padding: 0
        )
        let update = index.moveGroup(
            id: firstID,
            to: GraphPoint(x: 1_000, y: 1_000)
        )
        let oldAreaAfterMove = index.query(
            viewport: GraphViewport(offsetX: -350),
            screenSize: GraphSize(width: 100, height: 100),
            padding: 0
        )
        let movedArea = index.query(
            viewport: GraphViewport(offsetX: -950, offsetY: -850),
            screenSize: GraphSize(width: 400, height: 400),
            padding: 0
        )

        try expectEqual(
            Set(oldPath.edges.map(\.id)),
            Set(["group->group", "group->node"]),
            "移动前两种聚合边都应穿过旧区域"
        )
        try expectEqual(oldAreaAfterMove.edges, [], "Group 移动后聚合边不得停留在旧路径")
        try expectEqual(
            Set(movedArea.edges.map(\.id)),
            Set(["group->group", "group->node"]),
            "Group 到 Group 和 Group 到节点的聚合边都必须更新到新路径"
        )
        try expect(
            movedArea.edges.allSatisfy { $0.ports == ports },
            "Group 移动不得重新分配任何聚合边端口"
        )
        try expectEqual(update.updatedGroupIDs, [firstID], "只能报告目标 Group")
        try expectEqual(
            update.updatedEdgeIDs,
            ["group->group", "group->node"],
            "只能更新 Group 相邻聚合边"
        )
    },
    TestCase("连线索引严格使用当前线型") {
        let edge = renderIndexEdge(
            id: "curved-only",
            source: "source",
            target: "target",
            ports: CommitGraphEdgePorts(
                source: PortAnchor(side: .bottom, offset: 0.5),
                target: PortAnchor(side: .bottom, offset: 0.5)
            )
        )
        let nodes = [
            renderVisibleNode(hash: "source", x: 200, y: -100),
            renderVisibleNode(hash: "target", x: 600, y: -100)
        ]
        let curve = CommitGraphRenderIndex(
            projection: CommitGraphSceneProjection(
                nodes: nodes,
                groups: [],
                edges: [edge],
                lineStyle: .curve
            )
        )
        let orthogonal = CommitGraphRenderIndex(
            projection: CommitGraphSceneProjection(
                nodes: nodes,
                groups: [],
                edges: [edge],
                lineStyle: .orthogonal
            )
        )

        let viewport = GraphViewport(offsetY: 0)
        let screen = GraphSize(width: 800, height: 100)
        try expectEqual(
            curve.query(viewport: viewport, screenSize: screen, padding: 0)
                .edges.map(\.id),
            ["curved-only"],
            "高曲率贝塞尔路径穿过视口时不得漏边"
        )
        try expectEqual(
            orthogonal.query(viewport: viewport, screenSize: screen, padding: 0)
                .edges,
            [],
            "直角线未穿过视口时不得因曲线几何误返回"
        )
    },
    TestCase("五万稀疏节点查询不扫描全部占用桶") {
        let startedAt = Date()
        let nodes = (0..<50_000).map { index in
            renderVisibleNode(
                hash: "sparse-\(index)",
                x: Double(index % 5) * 10_000,
                y: Double(index) * 10_000
            )
        }
        let index = CommitGraphRenderIndex(
            projection: CommitGraphSceneProjection(
                nodes: nodes,
                groups: [],
                edges: []
            )
        )
        let builtAt = Date()
        let targetY = Double(25_000) * 10_000

        let result = index.queryWithDiagnostics(
            viewport: GraphViewport(offsetY: -targetY),
            screenSize: GraphSize(width: 800, height: 600),
            padding: 180
        )
        let queriedAt = Date()

        try expect(
            result.diagnostics.visitedBuckets < 20,
            "稀疏视口访问桶数必须与局部范围相关，不能扫描五万占用桶"
        )
        try expect(
            result.diagnostics.nodeCandidates < 20,
            "稀疏视口候选节点必须保持局部规模"
        )
        try expect(
            result.scene.nodes.count < 20,
            "稀疏视口输出必须保持局部规模"
        )
        print(
            String(
                format: "  性能证据：50000 节点索引 %.3f 秒，查询 %.6f 秒，访问 %d 桶、%d 候选",
                builtAt.timeIntervalSince(startedAt),
                queriedAt.timeIntervalSince(builtAt),
                result.diagnostics.visitedBuckets,
                result.diagnostics.nodeCandidates
            )
        )
    },
    TestCase("五万条边切换线型不生成全边几何") {
        let nodes = (0..<50_000).map { index in
            renderVisibleNode(
                hash: "edge-node-\(index)",
                x: index % 2 == 0 ? 200 : 20_000,
                y: Double(index) * 140
            )
        }
        let parentEdges = (1..<50_000).map { index in
            renderIndexEdge(
                id: "parent-\(index)",
                source: "edge-node-\(index)",
                target: "edge-node-\(index - 1)",
                ports: CommitGraphEdgePorts(
                    source: PortAnchor(side: .right, offset: 0.31),
                    target: PortAnchor(side: .bottom, offset: 0.69)
                )
            )
        }
        let offscreenMergeEdges = (0..<1_000).map { index in
            renderIndexEdge(
                id: "wide-merge-\(index)",
                source: "edge-node-\(40_001 + index * 2)",
                target: "edge-node-\(8_000 + index * 2)",
                kind: .merge
            )
        }
        let crossingMerge = renderIndexEdge(
            id: "visible-long-merge",
            source: "edge-node-40000",
            target: "edge-node-10000",
            kind: .merge
        )
        let edges = parentEdges + offscreenMergeEdges + [crossingMerge]
        var index = CommitGraphRenderIndex(
            projection: CommitGraphSceneProjection(
                nodes: nodes,
                groups: [],
                edges: edges,
                lineStyle: .curve
            )
        )
        let targetY = Double(25_000) * 140
        let viewport = GraphViewport(offsetY: -targetY)
        let screen = GraphSize(width: 800, height: 600)
        let before = index.queryWithDiagnostics(
            viewport: viewport,
            screenSize: screen,
            padding: 180
        )

        let switched = index.setLineStyle(.orthogonal)
        let after = index.queryWithDiagnostics(
            viewport: viewport,
            screenSize: screen,
            padding: 180
        )

        try expectEqual(
            switched.processedEdgeCount,
            0,
            "切换线型本身不得遍历或生成五万条边的几何"
        )
        try expect(
            before.diagnostics.edgeCandidates < 100,
            "曲线候选必须沿真实路径形成窄带，不能让一千条宽 Merge 的 AABB 全部命中"
        )
        try expect(
            after.diagnostics.edgeCandidates < 100,
            "直角候选必须沿真实折线路径形成窄带，不能退化为二维面积"
        )
        try expect(
            after.diagnostics.generatedEdgeGeometries < 100,
            "切换后的首次查询只能生成局部候选边几何"
        )
        try expect(
            before.scene.edges.contains { $0.id == "visible-long-merge" }
                && after.scene.edges.contains {
                    $0.id == "visible-long-merge"
                },
            "两种线型都不得漏掉真实穿过视口的超长 Merge"
        )
        try expectEqual(
            after.scene.edges.first?.ports,
            before.scene.edges.first?.ports,
            "切换线型前后端口 side 和 offset 必须完全不变"
        )
        print(
            "  性能证据：50000 边切线型处理 \(switched.processedEdgeCount) 边，局部查询生成 \(after.diagnostics.generatedEdgeGeometries) 条几何"
        )
    },
    TestCase("指针命中仅查询空间网格候选") {
        let groupID = UUID(
            uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
        )!
        let projection = CommitGraphSceneProjection(
            nodes: [renderVisibleNode(hash: "node", x: 240, y: 220)],
            groups: [
                CommitGraphVisibleGroup(
                    id: groupID,
                    title: "分组",
                    rect: GraphRect(x: 500, y: 120, width: 280, height: 220),
                    memberCount: 2,
                    isCollapsed: false
                )
            ],
            edges: []
        )
        let index = CommitGraphRenderIndex(projection: projection)

        try expectEqual(
            index.hitTest(canvasPoint: GraphPoint(x: 240, y: 220)),
            .node("node"),
            "节点应通过局部网格命中"
        )
        try expectEqual(
            index.hitTest(canvasPoint: GraphPoint(x: 520, y: 140)),
            .group(id: groupID, isCollapsed: false),
            "分组标题应通过局部网格命中"
        )
        try expectEqual(
            index.hitTest(canvasPoint: GraphPoint(x: 520, y: 260)),
            nil,
            "展开分组内容区不得误命中拖动标题"
        )
    },
    TestCase("选中关系通过预索引只返回相邻边") {
        let projection = CommitGraphSceneProjection(
            nodes: [
                renderVisibleNode(hash: "selected", x: 200, y: 200),
                renderVisibleNode(hash: "parent", x: 200, y: 80),
                renderVisibleNode(hash: "child", x: 200, y: 320),
                renderVisibleNode(hash: "other", x: 600, y: 200)
            ],
            groups: [],
            edges: [
                renderIndexEdge(
                    id: "selected->parent#0",
                    source: "selected",
                    target: "parent"
                ),
                renderIndexEdge(
                    id: "child->selected#0",
                    source: "child",
                    target: "selected"
                ),
                renderIndexEdge(
                    id: "other->parent#0",
                    source: "other",
                    target: "parent"
                )
            ]
        )
        let index = CommitGraphRenderIndex(projection: projection)
        try expectEqual(
            index.highlightedEdgeIDs(for: "selected"),
            Set(["selected->parent#0", "child->selected#0"]),
            "只能强化选中提交的直接父子和 Merge 边"
        )
        try expectEqual(
            index.highlightedNodeHashes(for: "selected"),
            Set(["selected", "parent", "child"]),
            "只能强化直接相邻节点"
        )
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
    kind: CommitGraphEdgeKind = .parent,
    ports: CommitGraphEdgePorts = CommitGraphEdgePorts(
        source: PortAnchor(side: .right, offset: 0.5),
        target: PortAnchor(side: .left, offset: 0.5)
    )
) -> CommitGraphVisibleEdge {
    CommitGraphVisibleEdge(
        id: id,
        source: .node(source),
        target: .node(target),
        kind: kind,
        colorIndex: 0,
        ports: ports,
        aggregateKey: nil,
        aggregateCount: 1,
        originalEdgeIDs: [id]
    )
}

private func renderVisibleGroup(
    id: UUID,
    title: String,
    origin: GraphPoint,
    relativePositions: [String: GraphPoint],
    isCollapsed: Bool
) -> CommitGraphVisibleGroup {
    let rect: GraphRect
    if isCollapsed || relativePositions.isEmpty {
        rect = GraphRect(
            x: origin.x,
            y: origin.y,
            width: 224,
            height: 92
        )
    } else {
        let xs = relativePositions.values.map(\.x)
        let ys = relativePositions.values.map(\.y)
        rect = GraphRect(
            x: origin.x + (xs.min() ?? 0) - 142,
            y: origin.y + (ys.min() ?? 0) - 75,
            width: (xs.max() ?? 0) - (xs.min() ?? 0) + 284,
            height: (ys.max() ?? 0) - (ys.min() ?? 0) + 142
        )
    }
    return CommitGraphVisibleGroup(
        id: id,
        title: title,
        rect: rect,
        memberCount: relativePositions.count,
        isCollapsed: isCollapsed,
        origin: origin,
        relativePositions: relativePositions
    )
}
