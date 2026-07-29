import Foundation
import GitMateCore

private let localGitFixtureDirectory = URL(
    fileURLWithPath: "/tmp/GitMate-LocalRepositoryGitServiceTests",
    isDirectory: true
)

let localRepositoryGitServiceTests = [
    TestCase("本地 Git 服务合并本地与远端分支引用") {
        let separator = "\u{1f}"
        let end = "\u{1e}"
        let output = [
            "refs/heads/main\(separator)abc\(separator)refs/remotes/origin/main\(separator)origin/main\(separator)lele\(end)",
            "refs/remotes/origin/main\(separator)abc\(separator)\(separator)\(separator)lele\(end)",
            "refs/remotes/origin/release\(separator)def\(separator)\(separator)\(separator)yuhan\(end)"
        ].joined()
        let executor = FakeCommandExecutor(results: [
            .success([.standardOutput(output)])
        ])
        let service = ProcessLocalRepositoryGitService(executor: executor)

        let branches = try await service.branches(at: localGitFixtureDirectory)

        try expectEqual(branches.count, 2, "相同逻辑分支的本地和远端引用应合并")
        let main = try branches.first(where: { $0.name == "main" }) ?? {
            throw TestFailure(description: "应解析 main 分支")
        }()
        let release = try branches.first(where: { $0.name == "release" }) ?? {
            throw TestFailure(description: "应解析仅远端 release 分支")
        }()
        try expectEqual(main.localSHA, "abc", "应保留本地提交")
        try expectEqual(main.remoteSHA, "abc", "应保留远端提交")
        try expectEqual(main.remoteName, "origin/main", "应保留完整远端名称")
        try expectEqual(main.trackingStatus, .synchronized, "相同提交应视为已同步")
        try expectEqual(release.trackingStatus, .remoteOnly, "仅远端引用应正确标记")
        try expect(
            executor.commands[0].contains("refs/remotes"),
            "分支查询必须同时读取远端引用"
        )
    },
    TestCase("本地 Git 服务区分轻量与附注标签") {
        let separator = "\u{1f}"
        let end = "\u{1e}"
        let output = [
            "v1.0.0\(separator)abc\(separator)commit\(separator)\(separator)2026-07-01 10:00:00 +0800\(end)",
            "v2.0.0\(separator)def\(separator)tag\(separator)lele\(separator)2026-07-28 10:00:00 +0800\(end)"
        ].joined()
        let executor = FakeCommandExecutor(results: [
            .success([.standardOutput(output)])
        ])
        let service = ProcessLocalRepositoryGitService(executor: executor)

        let tags = try await service.tags(at: localGitFixtureDirectory)

        try expectEqual(tags.map(\.name), ["v1.0.0", "v2.0.0"], "标签应按名称稳定排序")
        try expectEqual(tags[0].kind, .lightweight, "提交对象应映射为轻量标签")
        try expectEqual(tags[1].kind, .annotated, "标签对象应映射为附注标签")
        try expectEqual(tags[1].taggerName, "lele", "应解析附注标签作者")
    },
    TestCase("本地 Git 服务解析分支领先与落后数量") {
        let executor = FakeCommandExecutor(results: [
            .success([.standardOutput("3\t2")])
        ])
        let service = ProcessLocalRepositoryGitService(executor: executor)

        let comparison = try await service.comparison(
            local: "main",
            remote: "origin/main",
            at: localGitFixtureDirectory
        )

        try expectEqual(comparison.aheadBy, 2, "右侧本地提交数应映射为领先")
        try expectEqual(comparison.behindBy, 3, "左侧远端提交数应映射为落后")
        try expectEqual(
            executor.commands[0],
            [
                "-C",
                localGitFixtureDirectory.path,
                "rev-list",
                "--left-right",
                "--count",
                "origin/main...main"
            ],
            "比较必须明确指定远端和本地引用"
        )
    },
    TestCase("脏工作区阻止签出分支") {
        let executor = FakeCommandExecutor(results: [
            .success([.standardOutput(" M Sources/App.swift")])
        ])
        let service = ProcessLocalRepositoryGitService(executor: executor)

        do {
            try await service.checkoutBranch(
                "develop",
                at: localGitFixtureDirectory
            )
            throw TestFailure(description: "脏工作区不应签出分支")
        } catch let BranchOperationError.workingTreeNotClean(files) {
            try expect(
                files.contains(where: { $0.contains("Sources/App.swift") }),
                "错误应保留变更文件"
            )
        }
        try expectEqual(executor.commands.count, 1, "被安全检查阻止后不得执行 switch")
        try expect(
            executor.commands[0].contains("status"),
            "签出前应检查工作区状态"
        )
    },
    TestCase("干净工作区使用结构化参数签出分支") {
        let executor = FakeCommandExecutor(results: [
            .success([]),
            .success([])
        ])
        let service = ProcessLocalRepositoryGitService(executor: executor)

        try await service.checkoutBranch(
            "develop",
            at: localGitFixtureDirectory
        )

        try expectEqual(
            executor.commands[1],
            ["-C", localGitFixtureDirectory.path, "switch", "develop"],
            "签出命令必须使用独立参数"
        )
        try expectEqual(
            executor.environments[1]["LC_ALL"],
            "C",
            "Git 输出必须固定语言环境"
        )
    },
    TestCase("远端分支删除只发送精确完整引用") {
        let executor = FakeCommandExecutor(results: [
            .success([]),
            .success([])
        ])
        let service = ProcessLocalRepositoryGitService(executor: executor)

        try await service.deleteBranch(
            "feature/network-recovery",
            remote: "origin",
            force: false,
            at: localGitFixtureDirectory
        )

        try expectEqual(
            executor.commands[1],
            [
                "-C",
                localGitFixtureDirectory.path,
                "push",
                "origin",
                ":refs/heads/feature/network-recovery"
            ],
            "远端删除必须限定 refs/heads 下的精确分支"
        )
        try expect(
            !executor.commands.flatMap({ $0 }).contains(where: { $0.contains("secret") }),
            "Git 参数不得包含访问令牌"
        )
    },
    TestCase("附注标签使用独立消息参数创建") {
        let executor = FakeCommandExecutor(results: [
            .success([]),
            .success([])
        ])
        let service = ProcessLocalRepositoryGitService(executor: executor)

        try await service.createTag(
            "v2.5.0",
            target: "main",
            message: "稳定版本",
            at: localGitFixtureDirectory
        )

        try expectEqual(
            executor.commands[1],
            [
                "-C",
                localGitFixtureDirectory.path,
                "tag",
                "-a",
                "v2.5.0",
                "main",
                "-m",
                "稳定版本"
            ],
            "附注标签名称、目标和消息必须分开传递"
        )
    },
    TestCase("分支与标签写操作限制在指定引用") {
        let executor = FakeCommandExecutor()
        let service = ProcessLocalRepositoryGitService(executor: executor)

        try await service.setUpstream(
            branch: "develop",
            upstream: "origin/develop",
            at: localGitFixtureDirectory
        )
        try await service.pushBranch(
            "develop",
            remote: "origin",
            at: localGitFixtureDirectory
        )
        try await service.deleteBranch(
            "old",
            remote: nil,
            force: true,
            at: localGitFixtureDirectory
        )
        try await service.pushTag(
            "v2.5.0",
            remote: "origin",
            at: localGitFixtureDirectory
        )
        try await service.fetchTags(
            remote: "origin",
            at: localGitFixtureDirectory
        )
        try await service.deleteTag(
            "v1.0.0",
            remote: "origin",
            at: localGitFixtureDirectory
        )

        let commands = executor.commands
        try expect(
            commands.contains([
                "-C",
                localGitFixtureDirectory.path,
                "branch",
                "--set-upstream-to",
                "origin/develop",
                "develop"
            ]),
            "上游设置必须绑定指定分支"
        )
        try expect(
            commands.contains([
                "-C",
                localGitFixtureDirectory.path,
                "push",
                "--set-upstream",
                "origin",
                "develop"
            ]),
            "推送分支必须显式指定远端"
        )
        try expect(
            commands.contains([
                "-C",
                localGitFixtureDirectory.path,
                "branch",
                "-D",
                "old"
            ]),
            "强制删除只应作用于指定本地分支"
        )
        try expect(
            commands.contains([
                "-C",
                localGitFixtureDirectory.path,
                "push",
                "origin",
                "refs/tags/v2.5.0"
            ]),
            "标签推送必须使用完整标签引用"
        )
        try expect(
            commands.contains([
                "-C",
                localGitFixtureDirectory.path,
                "fetch",
                "origin",
                "--tags",
                "--prune"
            ]),
            "标签刷新必须清理失效远端引用"
        )
        try expect(
            commands.contains([
                "-C",
                localGitFixtureDirectory.path,
                "push",
                "origin",
                ":refs/tags/v1.0.0"
            ]),
            "标签删除必须使用完整标签引用"
        )
    },
    TestCase("非法引用在执行危险操作前被拒绝") {
        let executor = FakeCommandExecutor(results: [
            .commandFailure(.exitStatus(1, "不是有效引用"))
        ])
        let service = ProcessLocalRepositoryGitService(executor: executor)

        do {
            try await service.deleteBranch(
                "bad branch",
                remote: "origin",
                force: false,
                at: localGitFixtureDirectory
            )
            throw TestFailure(description: "非法分支名不应进入删除命令")
        } catch let BranchOperationError.invalidReference(name) {
            try expectEqual(name, "bad branch", "应指出被拒绝的引用")
        }
        try expectEqual(executor.commands.count, 1, "校验失败后不得执行删除")
        try expect(
            executor.commands[0].contains("check-ref-format"),
            "危险操作前应由 Git 校验引用格式"
        )
    },
    TestCase("Git 取消和失败错误保持可恢复且脱敏") {
        let cancelled = ProcessLocalRepositoryGitService(
            executor: FakeCommandExecutor(results: [.cancelled])
        )
        do {
            _ = try await cancelled.branches(at: localGitFixtureDirectory)
            throw TestFailure(description: "取消不应被视为成功")
        } catch BranchOperationError.cancelled {}

        let failed = ProcessLocalRepositoryGitService(
            executor: FakeCommandExecutor(results: [
                .commandFailure(
                    .exitStatus(
                        128,
                        "fatal: https://github_pat_private@github.com/GitMate/mac-client"
                    )
                )
            ])
        )
        do {
            _ = try await failed.branches(at: localGitFixtureDirectory)
            throw TestFailure(description: "Git 失败不应被视为成功")
        } catch let BranchOperationError.commandFailed(code, message) {
            try expectEqual(code, 128, "应保留 Git 退出码")
            try expect(!message.contains("github_pat_private"), "错误摘要不得泄露令牌")
            try expect(message.contains("***"), "错误摘要应明确显示已脱敏")
        }
    }
]
