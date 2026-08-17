import GitMateCore

let commitGraphPathGeometryTests = [
    TestCase("固定端点按四个边和比例换算坐标") {
        let rect = GraphRect(
            x: 100,
            y: 200,
            width: 240,
            height: 80
        )

        try expectEqual(
            CommitGraphPathGeometry.anchorPoint(
                rect: rect,
                anchor: PortAnchor(side: .top, offset: 0.25)
            ),
            GraphPoint(x: 160, y: 200),
            "顶部端口必须使用宽度比例定位"
        )
        try expectEqual(
            CommitGraphPathGeometry.anchorPoint(
                rect: rect,
                anchor: PortAnchor(side: .right, offset: 0.75)
            ),
            GraphPoint(x: 340, y: 260),
            "右侧端口必须使用高度比例定位"
        )
        try expectEqual(
            CommitGraphPathGeometry.anchorPoint(
                rect: rect,
                anchor: PortAnchor(side: .bottom, offset: 0.5)
            ),
            GraphPoint(x: 220, y: 280),
            "底部端口必须使用宽度比例定位"
        )
        try expectEqual(
            CommitGraphPathGeometry.anchorPoint(
                rect: rect,
                anchor: PortAnchor(side: .left, offset: 0.125)
            ),
            GraphPoint(x: 100, y: 210),
            "左侧端口必须使用高度比例定位"
        )
    },
    TestCase("端口比例创建时限制在零到一") {
        try expectEqual(
            PortAnchor(side: .top, offset: -4).offset,
            0,
            "负数端口比例必须限制为零"
        )
        try expectEqual(
            PortAnchor(side: .bottom, offset: 8).offset,
            1,
            "超过一的端口比例必须限制为一"
        )
    },
    TestCase("端口伸出点保持二十八像素固定方向") {
        let rect = GraphRect(
            x: 100,
            y: 200,
            width: 240,
            height: 80
        )

        try expectEqual(
            CommitGraphPathGeometry.stubPoint(
                rect: rect,
                anchor: PortAnchor(side: .bottom, offset: 0.5),
                length: 28
            ),
            GraphPoint(x: 220, y: 308),
            "底部端点必须先向下伸出二十八像素"
        )
        try expectEqual(
            CommitGraphPathGeometry.stubPoint(
                rect: rect,
                anchor: PortAnchor(side: .left, offset: 0.5),
                length: 28
            ),
            GraphPoint(x: 72, y: 240),
            "左侧端点必须先向左伸出二十八像素"
        )
    },
    TestCase("曲线路径保持固定端点并沿端口方向生成控制点") {
        let startRect = GraphRect(
            x: 0,
            y: 0,
            width: 100,
            height: 60
        )
        let endRect = GraphRect(
            x: 200,
            y: 300,
            width: 100,
            height: 60
        )

        let path = CommitGraphPathGeometry.curve(
            startRect: startRect,
            startAnchor: PortAnchor(side: .bottom, offset: 0.5),
            endRect: endRect,
            endAnchor: PortAnchor(side: .top, offset: 0.5)
        )

        guard case let .curve(start, control1, control2, end) = path else {
            throw TestFailure(description: "曲线生成器必须返回三次贝塞尔路径")
        }
        try expectEqual(start, GraphPoint(x: 50, y: 60), "曲线起点错误")
        try expectEqual(end, GraphPoint(x: 250, y: 300), "曲线终点错误")
        try expect(
            control1.y > start.y && control1.x == start.x,
            "起始控制点必须沿底部端口方向"
        )
        try expect(
            control2.y < end.y && control2.x == end.x,
            "结束控制点必须沿顶部端口方向"
        )
    },
    TestCase("直角路径删除重复点和连续共线中间点") {
        let path = CommitGraphPathGeometry.orthogonal(
            startRect: GraphRect(
                x: 0,
                y: 0,
                width: 100,
                height: 60
            ),
            startAnchor: PortAnchor(side: .bottom, offset: 0.5),
            endRect: GraphRect(
                x: 260,
                y: 320,
                width: 100,
                height: 60
            ),
            endAnchor: PortAnchor(side: .right, offset: 0.5),
            stubLength: 28
        )

        guard case let .polyline(points) = path else {
            throw TestFailure(description: "直角生成器必须返回折线")
        }
        try expectEqual(
            points.first,
            GraphPoint(x: 50, y: 60),
            "折线起点必须保持固定端点"
        )
        try expectEqual(
            points.last,
            GraphPoint(x: 360, y: 350),
            "折线终点必须保持固定端点"
        )
        for index in 1..<points.count {
            try expect(
                points[index] != points[index - 1],
                "直角路径不得保留重复点"
            )
        }
        if points.count >= 3 {
            for index in 0..<(points.count - 2) {
                try expect(
                    !CommitGraphPathGeometry.areCollinear(
                        points[index],
                        points[index + 1],
                        points[index + 2]
                    ),
                    "直角路径不得保留连续共线中间点"
                )
            }
        }
    },
    TestCase("直角路径的每段只能水平或垂直") {
        let path = CommitGraphPathGeometry.orthogonal(
            startRect: GraphRect(
                x: 20,
                y: 40,
                width: 100,
                height: 60
            ),
            startAnchor: PortAnchor(side: .left, offset: 0.25),
            endRect: GraphRect(
                x: 360,
                y: 250,
                width: 120,
                height: 80
            ),
            endAnchor: PortAnchor(side: .top, offset: 0.75)
        )

        guard case let .polyline(points) = path else {
            throw TestFailure(description: "直角生成器必须返回折线")
        }
        for index in 1..<points.count {
            try expect(
                points[index].x == points[index - 1].x
                    || points[index].y == points[index - 1].y,
                "直角路径不得包含斜线"
            )
        }
    },
    TestCase("通道路径在曲线与直角样式间保持相同端点") {
        let points = [
            GraphPoint(x: 50, y: 300),
            GraphPoint(x: 50, y: 240),
            GraphPoint(x: 250, y: 240),
            GraphPoint(x: 250, y: 100)
        ]
        let orthogonal = CommitGraphPathGeometry.orthogonal(points: points)
        let rounded = CommitGraphPathGeometry.roundedCurve(
            points: points,
            radius: 18
        )

        guard case let .polyline(orthogonalPoints) = orthogonal else {
            throw TestFailure(description: "直角通道必须返回折线")
        }
        try expectEqual(orthogonalPoints.first, points.first, "直角起点不得变化")
        try expectEqual(orthogonalPoints.last, points.last, "直角终点不得变化")
        try expectEqual(
            CommitGraphPathGeometry.pathEndpoints(rounded),
            [points.first!, points.last!],
            "曲线切换只能改变路径生成方式"
        )
    }
]
