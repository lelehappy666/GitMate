import Foundation
import GitMateCore

let commitGraphTraditionalContentViewportTests = [
    TestCase("头像覆盖层只返回真实可见行") {
        let rows = CommitGraphTraditionalContentViewport.overlayRows(
            totalCount: 50_000,
            rowHeight: 56,
            verticalOffset: 28_000,
            viewportHeight: 800
        )

        try expectEqual(rows, 500..<515, "覆盖层不得创建视口外预加载头像")
    },
    TestCase("传统分支左侧横向偏移不会改变右侧信息起点") {
        let divider = 360.0
        let informationX = CommitGraphTraditionalContentViewport
            .informationOriginX(dividerWidth: divider)
        let scrolledInformationX = CommitGraphTraditionalContentViewport
            .informationOriginX(dividerWidth: divider)

        try expectEqual(informationX, 378, "提交信息必须从分割线右侧固定留白开始")
        try expectEqual(
            scrolledInformationX,
            informationX,
            "左侧泳道滚动不得平移右侧头像和提交信息"
        )
    }
]
