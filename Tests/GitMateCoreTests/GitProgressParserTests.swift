import GitMateCore

let gitProgressParserTests = [
    TestCase("解析 Git 当前仓库下载百分比和阶段") {
        let progress = GitProgressParser.parse(
            "Receiving objects: 42% (420/1000), 2.00 MiB | 1.00 MiB/s"
        )

        try expectEqual(
            progress?.fraction,
            0.42,
            "应解析当前仓库百分比"
        )
        try expectEqual(
            progress?.phase,
            "正在接收对象",
            "应显示中文阶段"
        )
    },
    TestCase("无百分比的 Git 文本不会伪造进度") {
        try expect(
            GitProgressParser.parse("remote: Enumerating objects") == nil,
            "没有百分比时应保持不确定进度"
        )
    },
    TestCase("Git 百分比始终限制在零到一") {
        let progress = GitProgressParser.parse("Receiving objects: 120%")
        try expectEqual(progress?.fraction, 1, "异常百分比必须限制为 100%")
    }
]
