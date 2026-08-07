import Foundation
import GitMateCore

let commitGraphTraditionalViewportTests = [
    TestCase("传统视口只返回当前行和预加载行") {
        let range = CommitGraphTraditionalViewport.visibleRows(
            totalCount: 50_000,
            rowHeight: 56,
            verticalOffset: 28_000,
            viewportHeight: 800,
            preloadScreens: 1.5
        )

        try expect(range.count < 80, "不得构建全部传统行")
        try expect(range.contains(500), "必须覆盖当前屏幕附近行")
    },
    TestCase("传统视口将负偏移夹紧到首行") {
        let range = CommitGraphTraditionalViewport.visibleRows(
            totalCount: 100,
            rowHeight: 50,
            verticalOffset: -900,
            viewportHeight: 500,
            preloadScreens: 1
        )

        try expectEqual(range.lowerBound, 0, "负偏移不得产生负行号")
        try expectEqual(range.upperBound, 20, "应包含一屏可见行和一屏预加载")
    },
    TestCase("传统视口对零行高返回空范围") {
        let range = CommitGraphTraditionalViewport.visibleRows(
            totalCount: 100,
            rowHeight: 0,
            verticalOffset: 100,
            viewportHeight: 500,
            preloadScreens: 1
        )

        try expectEqual(range, 0..<0, "无效行高不得执行除法")
    },
    TestCase("传统视口对非有限输入安全退化") {
        let range = CommitGraphTraditionalViewport.visibleRows(
            totalCount: 100,
            rowHeight: 50,
            verticalOffset: .infinity,
            viewportHeight: 500,
            preloadScreens: .nan
        )

        try expectEqual(range, 0..<10, "非有限偏移应从首屏开始且禁用无效预加载")
    },
    TestCase("传统视口将超大偏移夹紧到尾部") {
        let range = CommitGraphTraditionalViewport.visibleRows(
            totalCount: 50_000,
            rowHeight: 56,
            verticalOffset: Double.greatestFiniteMagnitude,
            viewportHeight: 800,
            preloadScreens: 1
        )

        try expectEqual(range.upperBound, 50_000, "超大偏移不得越过数据尾部")
        try expect(range.count < 40, "尾部仍只能返回可见与预加载行")
    }
]
