import Foundation
import GitMateCore

let commitGraphTraditionalContentViewportTests = [
    TestCase("传统提交内容为多泳道保留可横向移动宽度") {
        let width = CommitGraphTraditionalContentViewport.contentWidth(
            viewportWidth: 900,
            maximumLane: 12
        )

        try expectEqual(width, 972, "十二号泳道应保留 412 点图形区和 560 点信息区")
        try expectEqual(
            CommitGraphTraditionalContentViewport.maximumHorizontalOffset(
                contentWidth: width,
                viewportWidth: 900
            ),
            72,
            "最大偏移应等于虚拟内容宽度减视口宽度"
        )
    },
    TestCase("传统提交内容不足一屏时禁止横向露白") {
        let width = CommitGraphTraditionalContentViewport.contentWidth(
            viewportWidth: 1_200,
            maximumLane: 2
        )

        try expectEqual(width, 1_200, "内容较少时应铺满当前视口")
        try expectEqual(
            CommitGraphTraditionalContentViewport.clampedHorizontalOffset(
                300,
                contentWidth: width,
                viewportWidth: 1_200
            ),
            0,
            "无横向溢出时偏移必须保持为零"
        )
    },
    TestCase("传统提交横向偏移夹紧到两侧边界") {
        try expectEqual(
            CommitGraphTraditionalContentViewport.clampedHorizontalOffset(
                -20,
                contentWidth: 1_600,
                viewportWidth: 1_000
            ),
            0,
            "负偏移不得露出左侧空白"
        )
        try expectEqual(
            CommitGraphTraditionalContentViewport.clampedHorizontalOffset(
                10_000,
                contentWidth: 1_600,
                viewportWidth: 1_000
            ),
            600,
            "超大偏移不得露出右侧空白"
        )
    },
    TestCase("头像覆盖层只返回真实可见行") {
        let rows = CommitGraphTraditionalContentViewport.overlayRows(
            totalCount: 50_000,
            rowHeight: 56,
            verticalOffset: 28_000,
            viewportHeight: 800
        )

        try expectEqual(rows, 500..<515, "覆盖层不得创建视口外预加载头像")
    },
    TestCase("鼠标水平移动超过阈值后识别为拖动") {
        try expect(
            !CommitGraphTraditionalHorizontalDrag.isDragging(horizontalDistance: 3.99),
            "轻微手抖仍应保留点击语义"
        )
        try expect(
            CommitGraphTraditionalHorizontalDrag.isDragging(horizontalDistance: -4.01),
            "向任意方向超过四点都应进入拖动态"
        )
    }
]
