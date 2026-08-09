import Foundation
import GitMateCore

let commitGraphAuthorAvatarTests = [
    TestCase("noreply 邮件解析真实 GitHub 头像") {
        let identity = CommitGraphAuthorAvatarIdentity.resolve(
            authorName: "Octocat",
            authorEmail: "123+octocat@users.noreply.github.com",
            currentUserLogin: nil,
            currentUserName: nil,
            currentUserAvatarURL: nil
        )

        try expectEqual(
            identity.remoteURL?.absoluteString,
            "https://github.com/octocat.png",
            "必须从 GitHub noreply 邮件提取登录名"
        )
        try expectEqual(identity.fallbackInitials, "OC", "远程头像失败时必须保留作者首字母")
    },
    TestCase("作者匹配当前账户登录名时复用账户头像") {
        let avatarURL = URL(string: "https://avatars.example.test/lele.png")!
        let identity = CommitGraphAuthorAvatarIdentity.resolve(
            authorName: "LeLe",
            authorEmail: "personal@example.com",
            currentUserLogin: "lele",
            currentUserName: "乐乐",
            currentUserAvatarURL: avatarURL
        )

        try expectEqual(identity.remoteURL, avatarURL, "登录名匹配必须复用已加载账户头像")
    },
    TestCase("作者匹配当前账户显示名时复用账户头像") {
        let avatarURL = URL(string: "https://avatars.example.test/lele.png")!
        let identity = CommitGraphAuthorAvatarIdentity.resolve(
            authorName: "乐乐",
            authorEmail: "personal@example.com",
            currentUserLogin: "lele666",
            currentUserName: "乐乐",
            currentUserAvatarURL: avatarURL
        )

        try expectEqual(identity.remoteURL, avatarURL, "显示名匹配也必须复用账户头像")
    },
    TestCase("普通作者使用稳定首字母头像") {
        let first = CommitGraphAuthorAvatarIdentity.resolve(
            authorName: "Lin Chen",
            authorEmail: "lin@example.com",
            currentUserLogin: nil,
            currentUserName: nil,
            currentUserAvatarURL: nil
        )
        let second = CommitGraphAuthorAvatarIdentity.resolve(
            authorName: "Lin Chen",
            authorEmail: "lin@example.com",
            currentUserLogin: nil,
            currentUserName: nil,
            currentUserAvatarURL: nil
        )

        try expectEqual(first.remoteURL, nil, "普通邮箱不得猜测远程头像地址")
        try expectEqual(first.fallbackInitials, "LC", "多词作者名应使用词首字母")
        try expectEqual(first.fallbackColorIndex, second.fallbackColorIndex, "回退颜色必须跨调用稳定")
        try expect((0..<6).contains(first.fallbackColorIndex), "回退颜色必须落在界面色板范围")
    },
    TestCase("空作者名从邮箱本地部分生成首字母") {
        let identity = CommitGraphAuthorAvatarIdentity.resolve(
            authorName: "  ",
            authorEmail: "river.club@example.com",
            currentUserLogin: nil,
            currentUserName: nil,
            currentUserAvatarURL: nil
        )

        try expectEqual(identity.fallbackInitials, "RC", "空作者名必须退回邮箱本地部分")
    }
]
