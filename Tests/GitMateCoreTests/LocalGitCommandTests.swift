import Foundation
import GitMateCore

let localGitCommandTests = [
    TestCase("本地 Git 版本命令固定使用白名单参数") {
        let command = GitCommandBuilder().version()

        try expectEqual(
            command.arguments,
            ["--version"],
            "版本命令不得追加任意参数"
        )
        try expectEqual(
            command.executableURL.path,
            "/usr/bin/git",
            "必须使用系统 Git"
        )
    },
    TestCase("本地 Git 引用校验拒绝参数注入") {
        try expect(
            !GitInputValidator.isSafeReference("--upload-pack=evil"),
            "前导短横线引用必须拒绝"
        )
        try expect(
            !GitInputValidator.isSafeReference("main\0evil"),
            "NUL 必须拒绝"
        )
        try expect(
            GitInputValidator.isSafeReference("feature/中文-修复"),
            "合法分支名必须允许"
        )
    },
    TestCase("本地 Git 哈希与远程名称使用独立校验") {
        try expect(
            GitInputValidator.isSafeHash("a81c32ff"),
            "合法十六进制哈希必须允许"
        )
        try expect(
            !GitInputValidator.isSafeHash("HEAD"),
            "符号引用不得当作哈希"
        )
        try expect(
            GitInputValidator.isSafeRemoteName("upstream-2"),
            "合法远程名称必须允许"
        )
        try expect(
            !GitInputValidator.isSafeRemoteName("--upload-pack"),
            "参数式远程名称必须拒绝"
        )
    },
    TestCase("本地 Git 路径校验允许特殊文件名但阻止越界") {
        let repository = try TemporaryGitRepository.make()
        let specialPath = "-中文 文件\t名称.swift"

        let validated = try GitInputValidator.validatedRelativePath(
            specialPath,
            repositoryURL: repository.url
        )

        try expectEqual(validated, specialPath, "合法特殊文件名应原样保留")
        do {
            _ = try GitInputValidator.validatedRelativePath(
                "../越界.txt",
                repositoryURL: repository.url
            )
            throw TestFailure(description: "越界路径不应通过")
        } catch LocalGitError.invalidPath {
        }
    },
    TestCase("本地 Git 日志脱敏移除认证信息") {
        let value = """
        Authorization: Basic abc123 \
        https://token@example.com/repo.git \
        ghp_1234567890abcdefghijklmnopqrstuv
        """

        let redacted = GitOutputRedactor.redact(value)

        try expect(!redacted.contains("abc123"), "不得保留认证头")
        try expect(!redacted.contains("token@"), "不得保留 URL 用户信息")
        try expect(!redacted.contains("ghp_"), "不得保留 GitHub Token")
    },
    TestCase("本地 Git 流式执行器保留 NUL 字节") {
        let repository = try TemporaryGitRepository.make()
        try repository.write(
            path: "含 空格.swift",
            content: "let value = 1\n"
        )
        let command = try GitCommandBuilder().untrackedFiles(
            repositoryURL: repository.url
        )

        let output = try await ProcessGitCommandExecutor().collect(command)

        try expect(
            output.stdoutData.contains(0),
            "NUL 分隔输出不得被按行拆坏"
        )
        try expect(
            String(decoding: output.stdoutData, as: UTF8.self)
                .contains("含 空格.swift"),
            "应保留中文路径"
        )
    }
]
