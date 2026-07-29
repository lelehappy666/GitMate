import Foundation
import GitMateCore

let gitCommitServiceTests = [
    TestCase("提交说明通过标准输入并创建真实提交") {
        let repository = try TemporaryGitRepository.make()
        try repository.write(path: "A.swift", content: "let a = 1\n")
        try repository.run(["add", "A.swift"])
        let message = CommitMessage(title: "新增 A", body: "补充实现")
        let command = try GitCommandBuilder().commit(
            repositoryURL: repository.url,
            message: message
        )

        try expect(
            !command.arguments.joined().contains("新增 A"),
            "提交说明不得进入参数"
        )
        try expect(command.standardInput != nil, "提交说明必须走标准输入")

        let service = GitCommitService(
            executor: ProcessGitCommandExecutor()
        )
        let result = try await service.commit(
            repositoryURL: repository.url,
            message: message,
            signing: .followGitConfiguration
        )

        let committedMessage = try repository.run([
            "show",
            "-s",
            "--format=%B",
            "HEAD"
        ])
        try expectEqual(result.subject, "新增 A", "应返回提交标题")
        try expectEqual(result.oid.count, 40, "应返回完整提交哈希")
        try expect(
            committedMessage.contains("补充实现"),
            "提交正文应进入真实提交"
        )
    },
    TestCase("空暂存区不得创建提交") {
        let repository = try TemporaryGitRepository.make()
        let service = GitCommitService(
            executor: ProcessGitCommandExecutor()
        )

        do {
            _ = try await service.commit(
                repositoryURL: repository.url,
                message: CommitMessage(title: "空提交", body: ""),
                signing: .followGitConfiguration
            )
            throw TestFailure(description: "空暂存区不应提交")
        } catch LocalGitError.emptyIndex {
        }
    },
    TestCase("Hook 失败保留暂存区和提交编辑内容") { @MainActor in
        let repository = try TemporaryGitRepository.make()
        try repository.installFailingHook(
            name: "pre-commit",
            message: "格式检查失败"
        )
        try repository.write(path: "A.swift", content: "let a = 1\n")
        try repository.run(["add", "A.swift"])
        let viewModel = CommitComposerViewModel(
            repositoryURL: repository.url,
            service: GitCommitService(
                executor: ProcessGitCommandExecutor()
            )
        )
        viewModel.title = "保留这个标题"
        viewModel.body = "保留这个正文"

        await viewModel.commit()

        try expectEqual(
            viewModel.title,
            "保留这个标题",
            "失败后不得清空标题"
        )
        try expectEqual(
            viewModel.body,
            "保留这个正文",
            "失败后不得清空正文"
        )
        try expect(
            viewModel.error?.message.contains("格式检查失败") == true,
            "应显示脱敏 Hook 输出"
        )
        let stagedPaths = try repository.run([
            "diff",
            "--cached",
            "--name-only"
        ])
        try expect(
            stagedPaths.contains("A.swift"),
            "暂存区必须保留"
        )
    }
]
