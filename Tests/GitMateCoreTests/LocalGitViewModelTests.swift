import Foundation
import GitMateCore

let localGitViewModelTests = [
    TestCase("页面三十至三十七路由编号稳定") {
        try expectEqual(
            LocalGitRoute.workingTree.pageNumber,
            30,
            "工作区应为 30"
        )
        try expectEqual(LocalGitRoute.commit.pageNumber, 31, "提交应为 31")
        try expectEqual(LocalGitRoute.diff.pageNumber, 32, "差异应为 32")
        try expectEqual(LocalGitRoute.stash.pageNumber, 33, "Stash 应为 33")
        try expectEqual(
            LocalGitRoute.historyOperation.pageNumber,
            34,
            "历史操作应为 34"
        )
        try expectEqual(
            LocalGitRoute.conflicts.pageNumber,
            35,
            "冲突应为 35"
        )
        try expectEqual(
            LocalGitRoute.remotes.pageNumber,
            36,
            "远程应为 36"
        )
        try expectEqual(
            LocalGitRoute.transfer.pageNumber,
            37,
            "传输应为 37"
        )
    },
    TestCase("真实仓库启动参数拒绝非 Git 目录") {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            _ = try LocalGitLaunchConfiguration(
                arguments: [
                    "GitMate",
                    "--local-repository",
                    directory.path
                ]
            )
            throw TestFailure(description: "非 Git 目录不应接受")
        } catch LocalGitError.notGitRepository {
        }
    },
    TestCase("本地 Git 启动参数解析仓库和预览页") {
        let repository = try TemporaryGitRepository.make()
        let configuration = try LocalGitLaunchConfiguration(
            arguments: [
                "GitMate",
                "--local-repository",
                repository.url.path,
                "--preview-page",
                "36"
            ]
        )

        try expectEqual(
            configuration.repositoryURL,
            repository.url.resolvingSymlinksInPath(),
            "应解析真实仓库"
        )
        try expectEqual(
            configuration.previewRoute,
            .remotes,
            "应解析页面 36"
        )
    }
]
