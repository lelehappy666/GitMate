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
    }
]
