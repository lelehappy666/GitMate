import GitMateCore

let workspaceRouteTests = [
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
    }
]
