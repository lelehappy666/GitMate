import Foundation
import GitMateCore

let gitTransferServiceTests = [
    TestCase("Fetch 从本地 Bare Remote 更新远程引用") {
        let fixture = try LocalRemoteFixture.make(behindBy: 2)
        var events: [GitTransferEvent] = []

        for try await event in fixture.service.fetch(
            repositoryURL: fixture.clone.url,
            remote: "origin",
            context: fixture.credentialContext
        ) {
            events.append(event)
        }

        try expect(
            events.contains(where: { $0.phase == .completed }),
            "应完成 Fetch"
        )
        let behindCount = try fixture.clone.behindCount()
        try expectEqual(behindCount, 2, "应更新远程引用")
    },
    TestCase("Pull 策略遵循 Git 配置") {
        let repository = try TemporaryGitRepository.make()
        try repository.run(["config", "pull.rebase", "true"])

        let strategy = try await PullStrategyResolver().resolve(
            repositoryURL: repository.url
        )

        try expectEqual(strategy, .rebase, "应遵循 pull.rebase")
    },
    TestCase("强制推送只生成 force-with-lease") {
        let repository = try TemporaryGitRepository.make()
        let plan = GitTransferPlan.forcePush(
            remote: "origin",
            branch: "main",
            expectedRemoteOID: "a81c32ff"
        )

        let command = try GitCommandBuilder().push(
            repositoryURL: repository.url,
            plan: plan,
            environment: [:]
        )

        try expect(
            command.arguments.contains(
                "--force-with-lease=refs/heads/main:a81c32ff"
            ),
            "必须携带精确 lease"
        )
        try expect(
            !command.arguments.contains("--force"),
            "不得使用裸 force"
        )
    },
    TestCase("网络错误日志不包含认证信息") {
        let error = GitOutputRedactor.redact(
            "fatal: unable to access https://TEST_LOCAL_GIT_TOKEN_SHOULD_NOT_LEAK@github.com/x/y Authorization: Basic abc"
        )
        try expect(
            !error.contains("TEST_LOCAL_GIT_TOKEN_SHOULD_NOT_LEAK"),
            "不得保留 URL 凭据"
        )
        try expect(!error.contains("abc"), "不得保留认证头")
    },
    TestCase("Pull 先 Fetch 再按策略完成快进整合") {
        let fixture = try LocalRemoteFixture.make(behindBy: 2)
        for try await _ in fixture.service.fetch(
            repositoryURL: fixture.clone.url,
            remote: "origin",
            context: fixture.credentialContext
        ) {}
        let plan = try await fixture.service.planPull(
            repositoryURL: fixture.clone.url,
            remote: "origin",
            branch: "main"
        )
        guard let confirmation = plan.confirmation else {
            throw TestFailure(description: "Pull 预检应返回确认")
        }
        var events: [GitTransferEvent] = []

        for try await event in fixture.service.pull(
            repositoryURL: fixture.clone.url,
            plan: plan,
            context: fixture.credentialContext,
            confirmation: confirmation
        ) {
            events.append(event)
        }

        try expect(
            events.contains(where: { $0.phase == .integrating }),
            "Pull 应进入本地整合阶段"
        )
        try expect(
            events.contains(where: { $0.phase == .completed }),
            "Pull 应完成"
        )
        let behind = try fixture.clone.behindCount()
        try expectEqual(behind, 0, "Pull 后不应继续落后")
    },
    TestCase("普通 Push 更新本地 Bare Remote") {
        let fixture = try LocalRemoteFixture.make(behindBy: 0)
        try fixture.clone.write(path: "local.txt", content: "local\n")
        try fixture.clone.commitAll(message: "本地提交")
        let localOID = try fixture.clone.headOID()
        let plan = try await fixture.service.planPush(
            repositoryURL: fixture.clone.url,
            remote: "origin",
            branch: "main",
            mode: .normal
        )
        guard let confirmation = plan.confirmation else {
            throw TestFailure(description: "Push 预检应返回确认")
        }

        for try await _ in fixture.service.push(
            repositoryURL: fixture.clone.url,
            plan: plan,
            context: fixture.credentialContext,
            confirmation: confirmation
        ) {}

        let remoteOID = try LocalClone.runGit([
            "--git-dir",
            fixture.remoteURL.path,
            "rev-parse",
            "refs/heads/main"
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try expectEqual(remoteOID, localOID, "远程应更新到本地提交")
    },
    TestCase("过期 lease 拒绝强制推送") {
        let fixture = try LocalRemoteFixture.make(behindBy: 0)
        try fixture.clone.write(path: "local.txt", content: "local\n")
        try fixture.clone.commitAll(message: "本地提交")
        let plan = try await fixture.service.planPush(
            repositoryURL: fixture.clone.url,
            remote: "origin",
            branch: "main",
            mode: .forceWithLease
        )
        guard let confirmation = plan.confirmation else {
            throw TestFailure(description: "强制 Push 预检应返回确认")
        }
        try fixture.upstream.write(path: "remote.txt", content: "remote\n")
        try fixture.upstream.commitAll(message: "远程抢先提交")
        try fixture.upstream.run(["push", "origin", "main"])

        do {
            for try await _ in fixture.service.push(
                repositoryURL: fixture.clone.url,
                plan: plan,
                context: fixture.credentialContext,
                confirmation: confirmation
            ) {}
            throw TestFailure(description: "过期 lease 不应成功")
        } catch LocalGitError.nonFastForward {
        }
    }
]

private struct LocalRemoteFixture: Sendable {
    let upstream: TemporaryGitRepository
    let clone: LocalClone
    let remoteURL: URL
    let service: GitTransferService
    let credentialContext: GitCredentialContext

    static func make(behindBy: Int) throws -> LocalRemoteFixture {
        let upstream = try TemporaryGitRepository.make()
        try upstream.write(path: "README.md", content: "# Base\n")
        try upstream.commitAll(message: "初始")
        let remoteURL = try upstream.makeBareRemote()
        try upstream.run(["remote", "add", "origin", remoteURL.path])
        try upstream.run(["push", "-u", "origin", "main"])

        let cloneURL = upstream.temporaryRoot
            .appending(path: "clone", directoryHint: .isDirectory)
        try LocalClone.runGit(["clone", remoteURL.path, cloneURL.path])
        let clone = LocalClone(url: cloneURL)
        try clone.run(["config", "user.name", "GitMate Clone"])
        try clone.run([
            "config",
            "user.email",
            "clone@example.invalid"
        ])

        for index in 0..<behindBy {
            try upstream.write(
                path: "upstream-\(index).txt",
                content: "\(index)\n"
            )
            try upstream.commitAll(message: "上游 \(index)")
        }
        try upstream.run(["push", "origin", "main"])

        let policy = GitRemoteTransportPolicy.localTest(
            allowedRoot: upstream.temporaryRoot
        )
        let credentialEnvironment = GitCredentialEnvironment(
            credentialStore: InMemoryCredentialStore(),
            transportPolicy: policy
        )
        return LocalRemoteFixture(
            upstream: upstream,
            clone: clone,
            remoteURL: remoteURL,
            service: GitTransferService(
                transportPolicy: policy,
                credentialEnvironment: credentialEnvironment
            ),
            credentialContext: GitCredentialContext(accountID: "local")
        )
    }
}

private struct LocalClone: Sendable {
    let url: URL

    @discardableResult
    func run(_ arguments: [String]) throws -> String {
        try Self.runGit(["-C", url.path] + arguments)
    }

    func behindCount() throws -> Int {
        let output = try run([
            "rev-list",
            "--count",
            "HEAD..@{upstream}"
        ])
        return Int(
            output.trimmingCharacters(in: .whitespacesAndNewlines)
        ) ?? 0
    }

    func write(path: String, content: String) throws {
        let target = url.appending(path: path)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(content.utf8).write(to: target, options: .atomic)
    }

    func commitAll(message: String) throws {
        try run(["add", "--all"])
        try run(["commit", "-m", message])
    }

    func headOID() throws -> String {
        try run(["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    static func runGit(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw TestFailure(
                description: String(decoding: errorData, as: UTF8.self)
            )
        }
        return String(decoding: outputData, as: UTF8.self)
    }
}
