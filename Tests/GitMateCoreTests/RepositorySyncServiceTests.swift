import Foundation
import GitMateCore

private let syncRepositoryOne = Repository(
    id: 1,
    name: "core",
    fullName: "GitMate/core",
    isPrivate: true,
    defaultBranch: "main",
    sizeInKilobytes: 2_048,
    cloneURL: URL(string: "https://github.com/GitMate/core.git")!,
    ownerAvatarURL: nil
)

private let syncRepositoryTwo = Repository(
    id: 2,
    name: "client",
    fullName: "GitMate/client",
    isPrivate: true,
    defaultBranch: "main",
    sizeInKilobytes: 4_096,
    cloneURL: URL(string: "https://github.com/GitMate/client.git")!,
    ownerAvatarURL: nil
)

private func collect(
    _ stream: AsyncThrowingStream<SyncEvent, Error>
) async throws -> [SyncEvent] {
    var events: [SyncEvent] = []
    for try await event in stream {
        events.append(event)
    }
    return events
}

private func temporarySyncDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "GitMateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
}

let repositorySyncServiceTests = [
    TestCase("标记为不同步的仓库不会执行 Git 命令") {
        let executor = FakeCommandExecutor()
        let service = GitRepositorySyncService(executor: executor)
        let destination = try temporarySyncDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }

        let events = try await collect(
            service.sync(
                repositories: [syncRepositoryOne, syncRepositoryTwo],
                preferences: [
                    RepositorySyncPreference(repositoryID: 1, mode: .automatic),
                    RepositorySyncPreference(repositoryID: 2, mode: .never)
                ],
                destination: destination,
                accessToken: "private-token"
            )
        )

        try expectEqual(executor.commands.count, 1, "只应同步一个仓库")
        try expect(executor.commands[0].contains("clone"), "首次同步应执行 clone")
        try expect(
            !executor.commands[0].contains(syncRepositoryTwo.cloneURL.absoluteString),
            "不同步仓库的地址不应进入命令"
        )
        try expect(
            !executor.commands[0].contains("private-token"),
            "访问令牌不得出现在 Git 命令参数"
        )
        try expectEqual(
            executor.environments[0]["GIT_CONFIG_VALUE_0"],
            "Authorization: Bearer private-token",
            "私有仓库令牌应通过临时 Git 环境传入"
        )
        try expectEqual(
            executor.environments[0]["GIT_TERMINAL_PROMPT"],
            "0",
            "同步不得等待终端凭据输入"
        )
        try expect(events.contains(.finished), "选中仓库完成后应结束同步")
    },
    TestCase("Git 进度输出会实时传到同步页面") {
        let executor = FakeCommandExecutor(results: [
            .success([
                .standardError("Receiving objects: 42%")
            ])
        ])
        let service = GitRepositorySyncService(executor: executor)
        let destination = try temporarySyncDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }

        let events = try await collect(
            service.sync(
                repositories: [syncRepositoryOne],
                preferences: [
                    RepositorySyncPreference(repositoryID: 1, mode: .manual)
                ],
                destination: destination,
                accessToken: "private-token"
            )
        )

        try expect(
            events.contains(
                .fileChanged(
                    repositoryID: 1,
                    path: "Receiving objects: 42%"
                )
            ),
            "同步页应收到 Git 的实时进度文本，实际事件：\(events)"
        )
    },
    TestCase("已存在仓库使用 fetch 并实时上报文件") {
        let executor = FakeCommandExecutor()
        let service = GitRepositorySyncService(executor: executor)
        let destination = try temporarySyncDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let repositoryDirectory = destination.appending(path: "core", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: repositoryDirectory.appending(path: ".git", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try Data("内容".utf8).write(
            to: repositoryDirectory.appending(path: "README.md")
        )

        let events = try await collect(
            service.sync(
                repositories: [syncRepositoryOne],
                preferences: [
                    RepositorySyncPreference(repositoryID: 1, mode: .manual)
                ],
                destination: destination,
                accessToken: nil
            )
        )

        try expect(executor.commands[0].contains("fetch"), "已有仓库应执行 fetch")
        try expect(
            events.contains(.fileChanged(repositoryID: 1, path: "README.md")),
            "同步页应收到当前文件路径，实际事件：\(events)"
        )
        try expect(
            events.contains(.progress(SyncProgress(completed: 1, total: 1))),
            "完成仓库后应更新长条进度"
        )
    },
    TestCase("单仓库失败后继续同步其他仓库") {
        let executor = FakeCommandExecutor(results: [
            .failure(.commandFailed("损坏的远端")),
            .success([])
        ])
        let service = GitRepositorySyncService(executor: executor)
        let destination = try temporarySyncDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }

        let events = try await collect(
            service.sync(
                repositories: [syncRepositoryOne, syncRepositoryTwo],
                preferences: [
                    RepositorySyncPreference(repositoryID: 1, mode: .automatic),
                    RepositorySyncPreference(repositoryID: 2, mode: .automatic)
                ],
                destination: destination,
                accessToken: nil
            )
        )

        try expectEqual(executor.commands.count, 2, "一个仓库失败不应阻止后续仓库")
        try expect(
            events.contains(
                .repositoryFailed(
                    repositoryID: 1,
                    failure: .commandFailed("损坏的远端")
                )
            ),
            "应上报失败仓库和原因"
        )
        try expect(events.contains(.finished), "处理所有仓库后应结束")
    },
    TestCase("Git 网络错误映射为可恢复的断网异常") {
        let failure = GitRepositorySyncService.mapFailure(
            message: "fatal: unable to access repository: Could not resolve host"
        )

        guard case .networkInterrupted = failure else {
            throw TestFailure(description: "无法解析主机应映射为网络中断")
        }
    },
    TestCase("Git 授权错误映射为令牌失效") {
        let failure = GitRepositorySyncService.mapFailure(
            message: "remote: HTTP 401 Bad credentials"
        )

        guard case .authorizationExpired = failure else {
            throw TestFailure(description: "HTTP 401 应映射为授权失效")
        }
    }
]
