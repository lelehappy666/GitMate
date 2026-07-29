import GitMateCore

let syncProgressTests = [
    TestCase("同步进度始终限制在零到一之间") {
        try expectEqual(
            SyncProgress(completed: 12, total: 10).fraction,
            1,
            "超出总数时应显示完成"
        )
        try expectEqual(
            SyncProgress(completed: -1, total: 10).fraction,
            0,
            "负数进度应显示为零"
        )
        try expectEqual(
            SyncProgress(completed: 3, total: 10).fraction,
            0.3,
            "正常进度应按比例计算"
        )
        try expectEqual(
            SyncProgress(completed: 0, total: 0).fraction,
            0,
            "未知总数时不应除以零"
        )
    },
    TestCase("仓库数量进度与当前仓库进度相互独立") {
        let progress = SyncProgress(
            completed: 2,
            total: 4,
            currentRepositoryFraction: 0.75,
            currentRepositoryPhase: "正在接收对象"
        )

        try expectEqual(progress.fraction, 0.5, "仓库数量进度应为一半")
        try expectEqual(
            progress.currentRepositoryFraction,
            0.75,
            "当前仓库进度应独立保存"
        )
    }
]
