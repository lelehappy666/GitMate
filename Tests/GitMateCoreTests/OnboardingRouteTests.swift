import GitMateCore

let onboardingRouteTests = [
    TestCase("页面 01–09 路由编号保持稳定") {
        try expect(OnboardingRoute.welcome.pageNumber == 1, "欢迎页必须是第 1 页")
        try expect(OnboardingRoute.githubAuthorization.pageNumber == 2, "GitHub 授权页必须是第 2 页")
        try expect(OnboardingRoute.enterpriseConnection.pageNumber == 3, "企业连接页必须是第 3 页")
        try expect(OnboardingRoute.permissionReview.pageNumber == 4, "权限确认页必须是第 4 页")
        try expect(OnboardingRoute.repositorySync.pageNumber == 5, "同步设置页必须是第 5 页")
        try expect(OnboardingRoute.syncProgress.pageNumber == 6, "同步进度页必须是第 6 页")
        try expect(OnboardingRoute.syncError.pageNumber == 7, "同步错误页必须是第 7 页")
        try expect(OnboardingRoute.networkInterrupted.pageNumber == 8, "网络中断页必须是第 8 页")
        try expect(OnboardingRoute.authorizationExpired.pageNumber == 9, "授权失效页必须是第 9 页")
    }
]
