import GitMateCore

let workspaceRouteTests = [
    TestCase("重复选择同一提交图仍递增刷新版本") {
        var trigger = CommitGraphRefreshTrigger()
        let first = trigger.request(repositoryID: 42)
        let second = trigger.request(repositoryID: 42)
        try expectEqual(first, 1, "首次请求版本为一")
        try expectEqual(second, 2, "重复请求必须递增")
    },
    TestCase("不同仓库的提交图刷新版本互不串扰") {
        var trigger = CommitGraphRefreshTrigger()
        _ = trigger.request(repositoryID: 42)
        let other = trigger.request(repositoryID: 43)
        let original = trigger.request(repositoryID: 42)
        try expectEqual(other, 1, "另一仓库应从首个版本开始")
        try expectEqual(original, 2, "原仓库必须保留自己的版本序列")
    },
    TestCase("页面十至十五路由编号稳定") {
        try expectEqual(WorkspaceRoute.dashboard.pageNumber, 10, "工作台应为第 10 页")
        try expectEqual(WorkspaceRoute.repositories.pageNumber, 11, "仓库墙应为第 11 页")
        try expectEqual(WorkspaceRoute.repositoryOverview(repositoryID: 1).pageNumber, 12, "仓库总览应为第 12 页")
        try expectEqual(WorkspaceRoute.readme(repositoryID: 1).pageNumber, 13, "README 应为第 13 页")
        try expectEqual(WorkspaceRoute.filesAndCommits(repositoryID: 1).pageNumber, 14, "文件提交应为第 14 页")
        try expectEqual(WorkspaceRoute.commitGraph(repositoryID: 1).pageNumber, 15, "提交图应为第 15 页")
    },
    TestCase("仓库路由保留当前仓库编号") {
        let route = WorkspaceRoute.commitGraph(repositoryID: 101)
        try expectEqual(route.repositoryID, 101, "应保留当前仓库")
    },
    TestCase("切换仓库保持README子页面") {
        try expectEqual(
            WorkspaceRoute.readme(repositoryID: 1)
                .replacingRepositoryID(2),
            .readme(repositoryID: 2),
            "仓库切换必须保持 README 页面"
        )
    },
    TestCase("切换仓库保持文件与提交子页面") {
        try expectEqual(
            WorkspaceRoute.filesAndCommits(repositoryID: 1)
                .replacingRepositoryID(2),
            .filesAndCommits(repositoryID: 2),
            "仓库切换必须保持文件与提交页面"
        )
    },
    TestCase("全局页面不因仓库选择自动跳转") {
        try expectEqual(
            WorkspaceRoute.dashboard.replacingRepositoryID(2),
            .dashboard,
            "全局工作台不应因仓库选择跳转"
        )
        try expectEqual(
            WorkspaceRoute.repositories.replacingRepositoryID(2),
            .repositories,
            "全部仓库页不应因仓库选择跳转"
        )
    },
    TestCase("浮层打开期间仓库被移除时回退全部仓库") {
        try expectEqual(
            WorkspaceRoute.readme(repositoryID: 1)
                .fallbackAfterCurrentRepositoryRemoval(),
            .repositories,
            "当前仓库不可用时应回退全部仓库页"
        )
    }
]
