import Foundation
import GitMateCore

private let importerAccountFixture = GitHubAccount(
    id: "octo-cat",
    login: "octo-cat",
    name: "Octo Cat",
    avatarURL: nil,
    serverURL: URL(string: "https://github.com")!,
    kind: .githubDotCom,
    scopes: ["repo"]
)

private func importerOutput(_ value: String) -> FakeCommandExecutor.Result {
    .success([.standardOutput(value)])
}

private func importerInvocation(
    _ arguments: [String]
) -> FakeCommandExecutor.ExpectedInvocation {
    .init(arguments: arguments, environment: [:])
}

private func importerTestRepository() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "GitMateImporterTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
        at: directory.appending(path: ".git", directoryHint: .isDirectory),
        withIntermediateDirectories: true
    )
    try Data("README".utf8).write(
        to: directory.appending(path: "README.md")
    )
    return directory
}

let localRepositoryImporterTests = [
    TestCase("导入器只读识别 HTTPS GitHub 仓库") {
        let repositoryURL = try importerTestRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let selectedURL = repositoryURL.appending(path: "Sources")
        let executor = FakeCommandExecutor(
            results: [
                importerOutput("\(repositoryURL.path)\n"),
                importerOutput("https://github.com/gitmate/mac-client.git\n"),
                importerOutput("main\n")
            ],
            expectedInvocations: [
                importerInvocation([
                    "-C", selectedURL.standardizedFileURL.path,
                    "rev-parse", "--show-toplevel"
                ]),
                importerInvocation([
                    "-C", repositoryURL.standardizedFileURL.path,
                    "remote", "get-url", "origin"
                ]),
                importerInvocation([
                    "-C", repositoryURL.standardizedFileURL.path,
                    "symbolic-ref", "--short", "HEAD"
                ])
            ]
        )
        let importer = LocalRepositoryImporter(executor: executor)

        let result = try await importer.importRepository(
            at: selectedURL,
            account: importerAccountFixture
        )

        try expectEqual(result.repository.fullName, "gitmate/mac-client", "应识别仓库全名")
        try expectEqual(result.repository.defaultBranch, "main", "应读取当前分支")
        try expectEqual(
            result.repository.cloneURL,
            URL(string: "https://github.com/gitmate/mac-client.git"),
            "应生成无凭据的标准远端地址"
        )
        try expectEqual(
            result.localURL,
            repositoryURL.standardizedFileURL,
            "应登记真实仓库根目录"
        )
        try expect(result.repository.sizeInKilobytes > 0, "应统计本地仓库大小")
        try executor.verifyComplete()
    },
    TestCase("SSH 与 HTTPS 地址为同一仓库生成相同编号") {
        let firstURL = try importerTestRepository()
        let secondURL = try importerTestRepository()
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }
        let httpsExecutor = FakeCommandExecutor(results: [
            importerOutput("\(firstURL.path)\n"),
            importerOutput("https://github.com/GitMate/mac-client.git\n"),
            importerOutput("main\n")
        ])
        let sshExecutor = FakeCommandExecutor(results: [
            importerOutput("\(secondURL.path)\n"),
            importerOutput("git@github.com:gitmate/mac-client.git\n"),
            importerOutput("develop\n")
        ])

        let httpsRecord = try await LocalRepositoryImporter(
            executor: httpsExecutor
        ).importRepository(at: firstURL, account: importerAccountFixture)
        let sshRecord = try await LocalRepositoryImporter(
            executor: sshExecutor
        ).importRepository(at: secondURL, account: importerAccountFixture)

        try expectEqual(
            httpsRecord.repository.id,
            sshRecord.repository.id,
            "仓库编号只应由规范化远端决定"
        )
    },
    TestCase("拒绝导入其他 GitHub 主机的仓库") {
        let repositoryURL = try importerTestRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let executor = FakeCommandExecutor(results: [
            importerOutput("\(repositoryURL.path)\n"),
            importerOutput("git@gitlab.com:gitmate/mac-client.git\n"),
            importerOutput("main\n")
        ])
        let importer = LocalRepositoryImporter(executor: executor)
        var errorMessage = ""

        do {
            _ = try await importer.importRepository(
                at: repositoryURL,
                account: importerAccountFixture
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        try expect(
            errorMessage.contains("github.com"),
            "错误应说明当前账户允许的 GitHub 主机"
        )
        try expectEqual(executor.commands.count, 2, "主机不匹配后不应继续读取分支")
    },
    TestCase("导入器支持带协议的 SSH 远端地址") {
        let repositoryURL = try importerTestRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let executor = FakeCommandExecutor(results: [
            importerOutput("\(repositoryURL.path)\n"),
            importerOutput(
                "ssh://git@github.com:22/gitmate/mac-client.git\n"
            ),
            importerOutput("feature/import\n")
        ])

        let record = try await LocalRepositoryImporter(
            executor: executor
        ).importRepository(
            at: repositoryURL,
            account: importerAccountFixture
        )

        try expectEqual(
            record.repository.fullName,
            "gitmate/mac-client",
            "SSH URL 应解析所有者与仓库名"
        )
        try expectEqual(
            record.repository.defaultBranch,
            "feature/import",
            "应保留当前分支名称"
        )
    },
    TestCase("非 Git 目录返回稳定中文错误") {
        let selectedURL = URL(fileURLWithPath: "/tmp/not-a-repository")
        let executor = FakeCommandExecutor(results: [
            .failure(.commandFailed("fatal: not a git repository"))
        ])
        var errorMessage = ""

        do {
            _ = try await LocalRepositoryImporter(
                executor: executor
            ).importRepository(
                at: selectedURL,
                account: importerAccountFixture
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        try expectEqual(
            errorMessage,
            "所选文件夹不是有效的 Git 仓库。",
            "不应向界面透出底层 Git 错误"
        )
        try expectEqual(executor.commands.count, 1, "识别失败后不应继续读取远端")
    },
    TestCase("缺少 origin 时停止导入") {
        let repositoryURL = try importerTestRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let executor = FakeCommandExecutor(results: [
            importerOutput("\(repositoryURL.path)\n"),
            .failure(.commandFailed("No such remote 'origin'"))
        ])
        var errorMessage = ""

        do {
            _ = try await LocalRepositoryImporter(
                executor: executor
            ).importRepository(
                at: repositoryURL,
                account: importerAccountFixture
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        try expectEqual(
            errorMessage,
            "仓库没有名为 origin 的远端地址。",
            "应明确提示配置 origin"
        )
        try expectEqual(executor.commands.count, 2, "缺少远端后不应继续读取分支")
    },
    TestCase("仓库目录登记后覆盖默认同步路径") {
        let catalog = LocalRepositoryCatalog(
            rootDirectory: URL(fileURLWithPath: "/managed"),
            fileSystem: FakeImporterRepositoryFileSystem()
        )
        let record = ImportedLocalRepository(
            repository: Repository(
                id: 42,
                name: "mac-client",
                fullName: "gitmate/mac-client",
                isPrivate: false,
                defaultBranch: "main",
                sizeInKilobytes: 0,
                cloneURL: URL(string: "https://github.com/gitmate/mac-client.git")!,
                ownerAvatarURL: nil
            ),
            localURL: URL(fileURLWithPath: "/external/mac-client")
        )

        catalog.register(record)

        try expectEqual(
            catalog.localURL(for: record.repository).path,
            "/external/mac-client",
            "已登记仓库应直接使用原始位置"
        )
    }
]

private struct FakeImporterRepositoryFileSystem: RepositoryFileSystem {
    func itemExists(at url: URL) -> Bool { false }
    func recursiveByteCount(at url: URL) throws -> Int64 { 0 }
}
