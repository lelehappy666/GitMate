import Foundation
import GitMateCore

private let fixtureAccount = GitHubAccount(
    id: "github.com:1",
    login: "lele",
    name: "Lele",
    avatarURL: URL(string: "https://avatars.githubusercontent.com/u/1"),
    serverURL: URL(string: "https://github.com")!,
    kind: .githubDotCom,
    scopes: ["repo", "read:user"]
)

private let fixtureRepository = Repository(
    id: 101,
    name: "mac-client",
    fullName: "GitMate/mac-client",
    isPrivate: true,
    defaultBranch: "main",
    sizeInKilobytes: 2_457_600,
    cloneURL: URL(string: "https://github.com/GitMate/mac-client.git")!,
    ownerAvatarURL: URL(string: "https://avatars.githubusercontent.com/u/1")
)

let onboardingStateTests = [
    TestCase("登录成功后进入权限确认页") {
        var state = OnboardingState()
        state.transition(.loginRequested)
        try expectEqual(state.route, .githubAuthorization, "请求登录后应进入 GitHub 授权页")

        state.transition(.accountVerified(fixtureAccount))
        try expectEqual(state.route, .permissionReview, "账户验证后应进入权限确认页")
        try expectEqual(state.account?.login, "lele", "应保存验证后的账户")
    },
    TestCase("企业连接使用独立页面") {
        var state = OnboardingState()
        state.transition(.enterpriseRequested)
        try expectEqual(state.route, .enterpriseConnection, "企业登录应进入企业连接页")
    },
    TestCase("权限确认后加载仓库并保存同步偏好") {
        var state = OnboardingState(route: .permissionReview, account: fixtureAccount)
        state.transition(.permissionsConfirmed)
        try expectEqual(state.route, .repositorySync, "权限确认后应进入仓库同步设置")

        state.transition(.repositoriesLoaded([fixtureRepository]))
        try expectEqual(state.repositories.count, 1, "应保存加载到的仓库")

        let preference = RepositorySyncPreference(repositoryID: 101, mode: .automatic)
        state.transition(.syncConfigured([preference]))
        try expectEqual(state.route, .syncProgress, "确认同步设置后应进入同步进度页")
        try expectEqual(state.preferences, [preference], "应保存仓库同步偏好")
    },
    TestCase("同步时断网进入可恢复页面") {
        var state = OnboardingState(route: .syncProgress)
        state.transition(.networkLost)
        try expectEqual(state.route, .networkInterrupted, "网络断开时应进入网络异常页")
        try expect(state.canResumeSync, "网络异常必须允许恢复同步")

        state.transition(.networkRestored)
        try expectEqual(state.route, .syncProgress, "网络恢复后应返回同步进度页")
    },
    TestCase("单仓库失败进入错误页且保留失败仓库") {
        var state = OnboardingState(route: .syncProgress)
        state.transition(.repositoryFailed(id: 101, message: "连接超时"))
        try expectEqual(state.route, .syncError, "仓库失败后应进入同步错误页")
        try expectEqual(state.failedRepositoryIDs, [101], "应记录失败仓库")
        try expectEqual(state.errorMessage, "连接超时", "应保存可读错误原因")
    },
    TestCase("授权失效后重新验证可继续同步") {
        var state = OnboardingState(route: .syncProgress, account: fixtureAccount)
        state.transition(.authorizationExpired(message: "令牌已失效"))
        try expectEqual(state.route, .authorizationExpired, "授权失效时应进入第 9 页")

        state.transition(.reauthorized(fixtureAccount))
        try expectEqual(state.route, .syncProgress, "重新授权后应继续原同步流程")
        try expectEqual(state.errorMessage, nil, "重新授权后应清除错误")
    },
    TestCase("同步完成后退出引导流程") {
        var state = OnboardingState(route: .syncProgress)
        state.transition(.syncFinished)
        try expectEqual(state.route, .complete, "全部同步完成后应结束引导")
    }
]
