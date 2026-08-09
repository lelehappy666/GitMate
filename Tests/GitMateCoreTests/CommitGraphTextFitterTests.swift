import GitMateCore

let commitGraphTextFitterTests = [
    TestCase("提交标题按真实测量宽度截断") {
        let fitted = CommitGraphTextFitter.truncated(
            "中文标题超过真实可用矩形",
            maximumWidth: 8,
            measure: { Double($0.count * 2) }
        )

        try expectEqual(
            fitted,
            "中文标…",
            "文字必须按测量结果截断，而不是使用固定字符数量"
        )
    },
    TestCase("提交标题可完整容纳时不增加省略号") {
        let fitted = CommitGraphTextFitter.truncated(
            "短标题",
            maximumWidth: 20,
            measure: { Double($0.count * 2) }
        )

        try expectEqual(
            fitted,
            "短标题",
            "完整可容纳的标题不得被修改"
        )
    },
    TestCase("可用宽度不足省略号时返回空字符串") {
        let fitted = CommitGraphTextFitter.truncated(
            "标题",
            maximumWidth: 1,
            measure: { Double($0.count * 2) }
        )

        try expectEqual(
            fitted,
            "",
            "连省略号都无法容纳时不得绘制越界文字"
        )
    }
]
