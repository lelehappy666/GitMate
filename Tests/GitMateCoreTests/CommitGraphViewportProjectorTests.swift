import GitMateCore

let commitGraphViewportProjectorTests = [
    TestCase("画布只返回视口与缓冲区内的提交节点") {
        let nodes = CommitGraphViewportProjector.visibleNodes(
            layout: largeLayoutFixture,
            viewport: GraphViewport(offsetX: 0, offsetY: 0, scale: 1),
            screenSize: GraphSize(width: 1_000, height: 700),
            padding: 180
        )

        try expectEqual(
            nodes.map(\.hash),
            visibleFixtureHashes,
            "不得绘制远离视口的节点"
        )
    },
    TestCase("滚轮缩放保持鼠标指向的画布坐标不变") {
        let anchor = GraphPoint(x: 420, y: 260)
        let updated = CommitGraphViewportProjector.zoomed(
            GraphViewport(),
            by: 1.25,
            anchor: anchor
        )

        try expectEqual(
            CommitGraphViewportProjector.canvasPoint(
                screenPoint: anchor,
                viewport: updated
            ),
            anchor,
            "缩放前后的指针画布坐标必须一致"
        )
    },
    TestCase("节点命中使用画布卡片矩形") {
        let viewport = GraphViewport(
            offsetX: 30,
            offsetY: -20,
            scale: 1.5
        )
        let center = CommitGraphViewportProjector.screenPoint(
            canvasPoint: GraphPoint(x: 260, y: 180),
            viewport: viewport
        )

        try expectEqual(
            CommitGraphViewportProjector.node(
                at: center,
                layout: largeLayoutFixture,
                viewport: viewport
            )?.hash,
            "near",
            "节点中心必须命中对应提交"
        )
        try expectEqual(
            CommitGraphViewportProjector.node(
                at: GraphPoint(x: 0, y: 0),
                layout: largeLayoutFixture,
                viewport: viewport
            ),
            nil,
            "卡片矩形外不得误命中提交"
        )
    },
    TestCase("画布只返回穿过视口的提交连线") {
        let layout = CommitGraphLayoutResult(
            nodes: [
                viewportNode(hash: "above", x: 260, y: -500),
                viewportNode(hash: "visible", x: 260, y: 220),
                viewportNode(hash: "below", x: 260, y: 1_200),
                viewportNode(hash: "far-left", x: -1_000, y: 220)
            ],
            edges: [
                CommitGraphEdge(
                    id: "above-visible",
                    childHash: "above",
                    parentHash: "visible",
                    kind: .parent,
                    colorIndex: 0
                ),
                CommitGraphEdge(
                    id: "visible-below",
                    childHash: "visible",
                    parentHash: "below",
                    kind: .parent,
                    colorIndex: 0
                ),
                CommitGraphEdge(
                    id: "far-left",
                    childHash: "far-left",
                    parentHash: "far-left",
                    kind: .parent,
                    colorIndex: 0
                )
            ]
        )

        try expectEqual(
            CommitGraphViewportProjector.visibleEdges(
                layout: layout,
                viewport: GraphViewport(),
                screenSize: GraphSize(width: 1_000, height: 700),
                padding: 0
            ).map(\.id),
            ["above-visible", "visible-below"],
            "只保留视口相交连线，离屏连线不得进入绘制集合"
        )
    },
    TestCase("提交连线区间索引可定位远离根中心的窄视口") {
        let layout = CommitGraphLayoutResult(
            nodes: [
                viewportNode(hash: "a0", x: 200, y: 0),
                viewportNode(hash: "a1", x: 200, y: 100),
                viewportNode(hash: "b0", x: 200, y: 500),
                viewportNode(hash: "b1", x: 200, y: 600),
                viewportNode(hash: "c0", x: 200, y: 1_000),
                viewportNode(hash: "c1", x: 200, y: 1_100)
            ],
            edges: [
                viewportEdge(id: "above", child: "a0", parent: "a1"),
                viewportEdge(id: "target", child: "b0", parent: "b1"),
                viewportEdge(id: "below", child: "c0", parent: "c1")
            ]
        )

        try expectEqual(
            CommitGraphViewportProjector.visibleEdges(
                layout: layout,
                viewport: GraphViewport(offsetY: -500),
                screenSize: GraphSize(width: 800, height: 100),
                padding: 0
            ).map(\.id),
            ["target"],
            "区间树左右分支必须只返回窄视口相交连线"
        )
    },
    TestCase("缩放限制在百分之三十五到百分之二百") {
        let enlarged = CommitGraphViewportProjector.zoomed(
            GraphViewport(),
            by: 20,
            anchor: .zero
        )
        let reduced = CommitGraphViewportProjector.zoomed(
            enlarged,
            by: 0.001,
            anchor: .zero
        )

        try expectEqual(enlarged.scale, 2, "最大缩放必须限制为 2")
        try expectEqual(reduced.scale, 0.35, "最小缩放必须限制为 0.35")
    },
    TestCase("同一帧多个缩放按各自锚点顺序折叠") {
        let initial = GraphViewport(
            offsetX: 36,
            offsetY: -24,
            scale: 0.9
        )
        let firstAnchor = GraphPoint(x: 140, y: 90)
        let secondAnchor = GraphPoint(x: 760, y: 410)
        let changes: [GraphViewportChange] = [
            .zoom(multiplier: 1.2, anchor: firstAnchor),
            .pan(GraphPoint(x: 18, y: -12)),
            .zoom(multiplier: 0.82, anchor: secondAnchor)
        ]
        let firstZoom = CommitGraphViewportProjector.zoomed(
            initial,
            by: 1.2,
            anchor: firstAnchor
        )
        var panned = firstZoom
        panned.offsetX += 18
        panned.offsetY -= 12
        let expected = CommitGraphViewportProjector.zoomed(
            panned,
            by: 0.82,
            anchor: secondAnchor
        )

        try expectEqual(
            CommitGraphViewportProjector.applying(
                changes,
                to: initial
            ),
            expected,
            "批量变换不得丢失较早缩放事件的锚点和事件顺序"
        )
    }
]

private let visibleFixtureHashes = ["near", "buffered"]

private let largeLayoutFixture = CommitGraphLayoutResult(
    nodes: [
        viewportNode(hash: "near", x: 260, y: 180),
        viewportNode(hash: "buffered", x: 1_250, y: 300),
        viewportNode(hash: "far", x: 1_600, y: 300)
    ],
    contentWidth: 1_800,
    contentHeight: 900
)

private func viewportNode(
    hash: String,
    x: Double,
    y: Double
) -> CommitGraphNode {
    CommitGraphNode(
        hash: hash,
        shortHash: hash,
        subject: "提交 \(hash)",
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

private func viewportEdge(
    id: String,
    child: String,
    parent: String
) -> CommitGraphEdge {
    CommitGraphEdge(
        id: id,
        childHash: child,
        parentHash: parent,
        kind: .parent,
        colorIndex: 0
    )
}
