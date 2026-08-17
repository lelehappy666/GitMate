import GitMateCore

let commitGraphOrganizationRouterTests = [
    TestCase("组织树路由绕开无关提交卡片与二十八像素净空") {
        let source = GraphRect(x: 0, y: 300, width: 224, height: 74)
        let target = GraphRect(x: 500, y: 0, width: 224, height: 74)
        let unrelated = GraphRect(x: 238, y: 120, width: 224, height: 74)
        let points = CommitGraphOrganizationRouter().route(
            sourceRect: source,
            targetRect: target,
            sourceAnchor: PortAnchor(side: .top, offset: 0.5),
            targetAnchor: PortAnchor(side: .bottom, offset: 0.5),
            obstacles: [unrelated],
            preferredChannel: 0
        )

        try expect(points.count >= 4, "避让路由必须保留端点、伸出点和通道")
        try expectEqual(points.first, GraphPoint(x: 112, y: 300), "起点必须固定")
        try expectEqual(points.last, GraphPoint(x: 612, y: 74), "终点必须固定")
        let clearance = expanded(unrelated, by: 28)
        for segment in zip(points, points.dropFirst()) {
            try expect(
                !segmentIntersectsRect(segment.0, segment.1, clearance),
                "连线不得穿过无关卡片的二十八像素净空"
            )
        }
    },
    TestCase("组织树路由对相同输入生成稳定通道") {
        let source = GraphRect(x: 500, y: 520, width: 224, height: 74)
        let target = GraphRect(x: 0, y: 0, width: 224, height: 74)
        let obstacles = [
            GraphRect(x: 238, y: 168, width: 224, height: 74),
            GraphRect(x: 238, y: 336, width: 224, height: 74)
        ]
        let router = CommitGraphOrganizationRouter()
        let first = router.route(
            sourceRect: source,
            targetRect: target,
            sourceAnchor: PortAnchor(side: .top, offset: 0.5),
            targetAnchor: PortAnchor(side: .bottom, offset: 0.5),
            obstacles: obstacles,
            preferredChannel: 3
        )
        let second = router.route(
            sourceRect: source,
            targetRect: target,
            sourceAnchor: PortAnchor(side: .top, offset: 0.5),
            targetAnchor: PortAnchor(side: .bottom, offset: 0.5),
            obstacles: obstacles,
            preferredChannel: 3
        )

        try expectEqual(first, second, "相同边必须复用完全一致的通道")
    },
    TestCase("路由提示保存固定端口与完整通道") {
        let ports = CommitGraphEdgePorts(
            source: PortAnchor(side: .top, offset: 0.5),
            target: PortAnchor(side: .bottom, offset: 0.5)
        )
        let hint = CommitGraphRouteHint(
            edgeID: "child->parent#0",
            ports: ports,
            waypoints: [
                GraphPoint(x: 100, y: 300),
                GraphPoint(x: 100, y: 200),
                GraphPoint(x: 500, y: 200),
                GraphPoint(x: 500, y: 100)
            ]
        )

        try expectEqual(hint.edgeID, "child->parent#0", "提示必须绑定真实边")
        try expectEqual(hint.ports, ports, "提示不得改变固定端点")
        try expectEqual(hint.waypoints.count, 4, "提示必须保存完整通道")
    }
]

private func expanded(_ rect: GraphRect, by padding: Double) -> GraphRect {
    GraphRect(
        x: rect.x - padding,
        y: rect.y - padding,
        width: rect.width + padding * 2,
        height: rect.height + padding * 2
    )
}

private func segmentIntersectsRect(
    _ start: GraphPoint,
    _ end: GraphPoint,
    _ rect: GraphRect
) -> Bool {
    if start.x == end.x {
        return start.x >= rect.minimumX
            && start.x <= rect.maximumX
            && max(start.y, end.y) >= rect.minimumY
            && min(start.y, end.y) <= rect.maximumY
    }
    if start.y == end.y {
        return start.y >= rect.minimumY
            && start.y <= rect.maximumY
            && max(start.x, end.x) >= rect.minimumX
            && min(start.x, end.x) <= rect.maximumX
    }
    return true
}
