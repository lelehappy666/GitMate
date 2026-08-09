import Foundation
import GitMateCore

let commitGraphTraditionalSplitLayoutTests = [
    TestCase("传统分割线默认使用百分之三十八并限制在舒适区间") {
        try expectEqual(
            CommitGraphTraditionalSplitLayout.defaultDividerWidth(
                viewportWidth: 1_000
            ),
            380,
            "常规窗口默认分割线必须为宽度百分之三十八"
        )
        try expectEqual(
            CommitGraphTraditionalSplitLayout.defaultDividerWidth(
                viewportWidth: 2_000
            ),
            420,
            "宽窗口默认左栏不得无限扩张"
        )
    },
    TestCase("传统分割线同时保护左右最小宽度") {
        try expectEqual(
            CommitGraphTraditionalSplitLayout.clampedDividerWidth(
                10,
                viewportWidth: 1_000
            ),
            220,
            "左栏不得窄于二百二十点"
        )
        try expectEqual(
            CommitGraphTraditionalSplitLayout.clampedDividerWidth(
                900,
                viewportWidth: 1_000
            ),
            580,
            "右侧信息必须保留四百二十点"
        )
    },
    TestCase("传统分割线在超窄和无效输入下安全夹紧") {
        let narrow = CommitGraphTraditionalSplitLayout.clampedDividerWidth(
            .nan,
            viewportWidth: 300
        )
        let invalidViewport = CommitGraphTraditionalSplitLayout
            .clampedDividerWidth(.infinity, viewportWidth: .nan)

        try expect(narrow >= 0 && narrow <= 300, "超窄窗口不得产生负宽度或越界")
        try expectEqual(invalidViewport, 0, "无效视口必须安全退化为零宽度")
    },
    TestCase("左侧泳道偏移只在内容超过分栏时生效") {
        try expectEqual(
            CommitGraphTraditionalSplitLayout.clampedLaneOffset(
                100,
                laneContentWidth: 300,
                dividerWidth: 360
            ),
            0,
            "泳道内容不足左栏时不得露白"
        )
        try expectEqual(
            CommitGraphTraditionalSplitLayout.clampedLaneOffset(
                9_000,
                laneContentWidth: 1_200,
                dividerWidth: 360
            ),
            840,
            "横向偏移必须夹紧到最后一条泳道"
        )
        try expectEqual(
            CommitGraphTraditionalSplitLayout.clampedLaneOffset(
                -20,
                laneContentWidth: 1_200,
                dividerWidth: 360
            ),
            0,
            "负偏移不得露出左侧空白"
        )
    },
    TestCase("大量分支只返回左侧视口附近的泳道范围") {
        let range = CommitGraphTraditionalSplitLayout.visibleLaneRange(
            slotCount: 300,
            horizontalOffset: 2_800,
            dividerWidth: 380,
            preloadLanes: 2
        )

        try expect(range.lowerBound > 90, "远距离滚动必须跳过左侧不可见泳道")
        try expect(range.count < 24, "绘制候选不得随三百条总分支线性增长")
    }
]
