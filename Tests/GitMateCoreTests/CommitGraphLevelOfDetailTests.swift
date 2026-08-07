import GitMateCore

let commitGraphLevelOfDetailTests = [
    TestCase("语义缩放使用三个稳定档位") {
        try expectEqual(
            CommitGraphLevelOfDetail.forScale(1),
            .full,
            "高缩放必须显示完整卡片"
        )
        try expectEqual(
            CommitGraphLevelOfDetail.forScale(0.65),
            .compact,
            "中缩放必须显示精简卡片"
        )
        try expectEqual(
            CommitGraphLevelOfDetail.forScale(0.4),
            .overview,
            "低缩放必须显示节点圆点"
        )
    },
    TestCase("语义缩放边界和异常值具有确定结果") {
        try expectEqual(
            CommitGraphLevelOfDetail.forScale(0.8),
            .full,
            "完整卡片边界必须稳定"
        )
        try expectEqual(
            CommitGraphLevelOfDetail.forScale(0.5),
            .compact,
            "精简卡片边界必须稳定"
        )
        try expectEqual(
            CommitGraphLevelOfDetail.forScale(0),
            .overview,
            "零缩放必须安全降级"
        )
        try expectEqual(
            CommitGraphLevelOfDetail.forScale(.nan),
            .overview,
            "NaN 必须安全降级"
        )
        try expectEqual(
            CommitGraphLevelOfDetail.forScale(.infinity),
            .full,
            "正无穷必须归入最高细节档"
        )
    }
]
