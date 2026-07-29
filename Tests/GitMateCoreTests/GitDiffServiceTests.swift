import Foundation
import GitMateCore

let gitDiffServiceTests = [
    TestCase("中文空格路径通过 NUL Pathspec 暂存且不进入参数") {
        let repository = try TemporaryGitRepository.make()
        let path = "目录/含 空格.swift"
        try repository.write(path: path, content: "let value = 1\n")
        let command = try GitCommandBuilder().stagePaths(
            repositoryURL: repository.url,
            paths: [path]
        )

        try expect(
            !command.arguments.contains(path),
            "文件路径不得展开为命令参数"
        )
        try expect(
            command.standardInput?.contains(0) == true,
            "Pathspec 必须使用 NUL 分隔"
        )

        let service = GitDiffService(
            executor: ProcessGitCommandExecutor()
        )
        try await service.stage(
            repositoryURL: repository.url,
            paths: [path]
        )

        let status = try repository.run(["status", "--porcelain=v1"])
        try expect(status.hasPrefix("A  "), "文件应进入暂存区")
    },
    TestCase("取消暂存保留工作区修改") {
        let repository = try TemporaryGitRepository.make()
        try repository.write(path: "A.swift", content: "let a = 1\n")
        try repository.commitAll(message: "初始")
        try repository.write(path: "A.swift", content: "let a = 2\n")
        let service = GitDiffService(
            executor: ProcessGitCommandExecutor()
        )
        try await service.stage(
            repositoryURL: repository.url,
            paths: ["A.swift"]
        )

        try await service.unstage(
            repositoryURL: repository.url,
            paths: ["A.swift"]
        )
        let stagedPaths = try repository.run([
            "diff",
            "--cached",
            "--name-only"
        ])
        let workingTreePaths = try repository.run([
            "diff",
            "--name-only"
        ])

        try expect(
            stagedPaths.isEmpty,
            "暂存区应清空"
        )
        try expect(
            workingTreePaths.contains("A.swift"),
            "工作区修改必须保留"
        )
    },
    TestCase("普通 Diff 解析代码块和增删行") {
        let data = Data(
            """
            diff --git a/A.swift b/A.swift
            index 1111111..2222222 100644
            --- a/A.swift
            +++ b/A.swift
            @@ -1,2 +1,2 @@
            -let value = 1
            +let value = 2
             print(value)

            """.utf8
        )

        let document = GitDiffParser.parse(path: "A.swift", data: data)

        try expectEqual(document.loadingMode, .full, "普通 Diff 应完整显示")
        try expectEqual(document.hunks.count, 1, "应解析一个代码块")
        try expectEqual(document.addedLineCount, 1, "应统计新增行")
        try expectEqual(document.deletedLineCount, 1, "应统计删除行")
    },
    TestCase("超过二万行的 Diff 只返回摘要") {
        let document = GitDiffParser.parse(
            path: "Large.swift",
            data: GitDiffFixture.make(lineCount: 20_001)
        )

        try expectEqual(
            document.loadingMode,
            .summary,
            "超过二万行必须摘要化"
        )
        try expect(document.hunks.isEmpty, "摘要不得缓存完整代码块")
    },
    TestCase("未来时间的危险操作确认必须拒绝") {
        let repository = try TemporaryGitRepository.make()
        try repository.write(path: "A.swift", content: "base\n")
        try repository.commitAll(message: "初始")
        try repository.write(path: "A.swift", content: "changed\n")
        let service = GitDiffService(
            executor: ProcessGitCommandExecutor()
        )
        let valid = service.discardFilesConfirmation(
            repositoryURL: repository.url,
            paths: ["A.swift"]
        )
        let futureConfirmation = RiskConfirmation(
            operationID: valid.operationID,
            repositoryID: valid.repositoryID,
            impactFingerprint: valid.impactFingerprint,
            createdAt: Date().addingTimeInterval(60)
        )

        do {
            try await service.discardFiles(
                repositoryURL: repository.url,
                paths: ["A.swift"],
                confirmation: futureConfirmation
            )
            throw TestFailure(description: "未来时间确认不应生效")
        } catch LocalGitError.confirmationExpired {
        }
        let contentAfterRejectedConfirmation = try repository.read(
            path: "A.swift"
        )
        try expectEqual(
            contentAfterRejectedConfirmation,
            "changed\n",
            "拒绝确认后不得修改文件"
        )
    },
    TestCase("匹配影响指纹的确认可以放弃文件修改") {
        let repository = try TemporaryGitRepository.make()
        try repository.write(path: "A.swift", content: "base\n")
        try repository.commitAll(message: "初始")
        try repository.write(path: "A.swift", content: "changed\n")
        let service = GitDiffService(
            executor: ProcessGitCommandExecutor()
        )
        let confirmation = service.discardFilesConfirmation(
            repositoryURL: repository.url,
            paths: ["A.swift"]
        )

        try await service.discardFiles(
            repositoryURL: repository.url,
            paths: ["A.swift"],
            confirmation: confirmation
        )
        let restoredContent = try repository.read(path: "A.swift")

        try expectEqual(
            restoredContent,
            "base\n",
            "确认后应恢复已跟踪文件"
        )
    },
    TestCase("切换文件后旧 Diff 不覆盖新文件") { @MainActor in
        let repository = try TemporaryGitRepository.make()
        let service = DelayedGitDiffService()
        let viewModel = FileDiffViewModel(
            repositoryURL: repository.url,
            service: service
        )

        async let first: Void = viewModel.select(
            path: "A.swift",
            source: .workingTree
        )
        try await Task.sleep(for: .milliseconds(10))
        await viewModel.select(
            path: "B.swift",
            source: .workingTree
        )
        _ = await first

        try expectEqual(
            viewModel.document?.path,
            "B.swift",
            "必须保留最新选择"
        )
    }
]

private actor DelayedGitDiffService: GitDiffServicing {
    func diff(
        repositoryURL: URL,
        path: String,
        source: GitDiffSource,
        options: GitDiffOptions
    ) async throws -> GitDiffDocument {
        try await Task.sleep(
            for: path == "A.swift"
                ? .milliseconds(80)
                : .milliseconds(1)
        )
        return GitDiffDocument(
            path: path,
            files: [],
            hunks: [],
            byteCount: 0,
            lineCount: 0,
            addedLineCount: 0,
            deletedLineCount: 0,
            loadingMode: .full
        )
    }

    func stage(repositoryURL: URL, paths: [String]) async throws {
        throw TestOnlyGitDiffError.unexpectedCall
    }

    func unstage(repositoryURL: URL, paths: [String]) async throws {
        throw TestOnlyGitDiffError.unexpectedCall
    }

    func stageHunk(
        repositoryURL: URL,
        hunk: GitDiffHunk
    ) async throws {
        throw TestOnlyGitDiffError.unexpectedCall
    }

    func unstageHunk(
        repositoryURL: URL,
        hunk: GitDiffHunk
    ) async throws {
        throw TestOnlyGitDiffError.unexpectedCall
    }

    func discardHunk(
        repositoryURL: URL,
        hunk: GitDiffHunk,
        confirmation: RiskConfirmation
    ) async throws {
        throw TestOnlyGitDiffError.unexpectedCall
    }

    func discardFiles(
        repositoryURL: URL,
        paths: [String],
        confirmation: RiskConfirmation
    ) async throws {
        throw TestOnlyGitDiffError.unexpectedCall
    }
}

private enum TestOnlyGitDiffError: Error {
    case unexpectedCall
}

private enum GitDiffFixture {
    static func make(lineCount: Int) -> Data {
        var value = """
        diff --git a/Large.swift b/Large.swift
        --- a/Large.swift
        +++ b/Large.swift
        @@ -1,1 +1,\(lineCount) @@

        """
        for index in 0..<lineCount {
            value += "+line \(index)\n"
        }
        return Data(value.utf8)
    }
}
