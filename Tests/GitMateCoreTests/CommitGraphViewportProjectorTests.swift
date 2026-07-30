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
