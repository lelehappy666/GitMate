import Foundation
import GitMateCore

let localGitSecurityTests = [
    TestCase("HTTPS 令牌只进入临时 Git 环境") {
        let store = InMemoryCredentialStore()
        try store.save(
            token: "TEST_LOCAL_GIT_TOKEN_SHOULD_NOT_LEAK",
            accountID: "42"
        )
        let provider = GitCredentialEnvironment(credentialStore: store)

        let environment = try provider.environment(
            remoteURLString: "https://github.com/GitMate/mac-client.git",
            context: GitCredentialContext(accountID: "42")
        )

        try expectEqual(
            environment["GIT_TERMINAL_PROMPT"],
            "0",
            "必须禁用 Git 交互提示"
        )
        try expect(
            environment.values.contains(where: {
                $0.contains("Authorization: Basic")
            }),
            "HTTPS 环境必须包含临时认证头"
        )
        let repository = try TemporaryGitRepository.make()
        let command = try GitCommandBuilder().untrackedFiles(
            repositoryURL: repository.url,
            environment: environment
        )
        try expect(
            !command.arguments.joined()
                .contains("TEST_LOCAL_GIT_TOKEN_SHOULD_NOT_LEAK"),
            "命令参数不得包含令牌"
        )
    },
    TestCase("SSH 远程不读取 GitHub 令牌或覆盖 SSH Agent") {
        let provider = GitCredentialEnvironment(
            credentialStore: FailingOnReadCredentialStore()
        )

        let environment = try provider.environment(
            remoteURLString: "git@github.com:GitMate/mac-client.git",
            context: GitCredentialContext(accountID: "42")
        )

        try expectEqual(
            environment["GIT_TERMINAL_PROMPT"],
            "0",
            "SSH 同样必须禁用 Git 交互提示"
        )
        try expect(
            environment["GIT_SSH_COMMAND"] == nil,
            "不得覆盖系统 SSH Agent"
        )
    },
    TestCase("生产策略拒绝本地远程而测试策略限制在临时根目录") {
        let repository = try TemporaryGitRepository.make()
        do {
            _ = try GitRemoteTransportPolicy.production.validate(
                remoteURLString: repository.url.path
            )
            throw TestFailure(description: "生产策略不应允许本地路径")
        } catch LocalGitError.unsupportedRemoteProtocol {
        }

        let protocolValue = try GitRemoteTransportPolicy
            .localTest(allowedRoot: repository.temporaryRoot)
            .validate(remoteURLString: repository.url.path)
        try expectEqual(
            protocolValue,
            .localFileForTests,
            "临时根目录内的本地远程应仅供测试使用"
        )

        do {
            _ = try GitRemoteTransportPolicy
                .localTest(allowedRoot: repository.temporaryRoot)
                .validate(remoteURLString: "/tmp/outside.git")
            throw TestFailure(description: "测试策略不得越过临时根目录")
        } catch LocalGitError.unsupportedRemoteProtocol {
        }
    },
    TestCase("操作 Journal 落盘前移除敏感信息") {
        let repository = try TemporaryGitRepository.make()
        let directory = repository.temporaryRoot
            .appending(path: "journal", directoryHint: .isDirectory)
        let journal = GitOperationJournal(directoryURL: directory)
        let repositoryID = GitRepositoryIdentifier.make(
            repositoryURL: repository.url
        )
        let entry = GitOperationJournalEntry(
            repositoryID: repositoryID,
            kind: .fetch,
            startedAt: Date(timeIntervalSince1970: 1_000),
            finishedAt: Date(timeIntervalSince1970: 1_001),
            phase: "Authorization: Basic TEST_LOCAL_GIT_TOKEN_SHOULD_NOT_LEAK",
            result: .failed
        )

        try await journal.record(entry)

        let entries = try await journal.entries(repositoryID: repositoryID)
        try expectEqual(entries.count, 1, "应能读取已记录操作")
        try expect(
            !entries[0].phase.contains(
                "TEST_LOCAL_GIT_TOKEN_SHOULD_NOT_LEAK"
            ),
            "读取结果不得包含令牌"
        )
        let storedData = try Data(
            contentsOf: directory.appending(path: "\(repositoryID).json")
        )
        try expect(
            !String(decoding: storedData, as: UTF8.self)
                .contains("TEST_LOCAL_GIT_TOKEN_SHOULD_NOT_LEAK"),
            "Journal 文件不得包含令牌"
        )
    }
]

private struct FailingOnReadCredentialStore: CredentialStore {
    func save(token: String, accountID: String) throws {}

    func token(accountID: String) throws -> String? {
        throw FailingOnReadCredentialStoreError.unexpectedTokenRead
    }

    func deleteToken(accountID: String) throws {}
}

private enum FailingOnReadCredentialStoreError: Error {
    case unexpectedTokenRead
}
