import Foundation
import GitMateCore

let gitRemoteServiceTests = [
    TestCase("添加 HTTPS 与 SCP 风格 SSH 远程") {
        let repository = try TemporaryGitRepository.make()
        let service = GitRemoteService()

        try await service.add(
            repositoryURL: repository.url,
            name: "origin",
            fetchURL: "https://github.com/GitMate/mac-client.git",
            pushURL: "git@github.com:GitMate/mac-client.git"
        )

        let remotes = try await service.list(
            repositoryURL: repository.url
        )
        try expectEqual(remotes[0].name, "origin", "应添加远程")
        try expectEqual(
            remotes[0].fetchProtocol,
            .https,
            "应识别 HTTPS"
        )
        try expectEqual(
            remotes[0].pushProtocol,
            .ssh,
            "应识别 SSH"
        )
    },
    TestCase("远程名称拒绝参数注入") {
        try expect(
            !GitInputValidator.isSafeRemoteName("--upload-pack"),
            "不得允许参数式名称"
        )
        try expect(
            GitInputValidator.isSafeRemoteName("upstream-2"),
            "应允许安全名称"
        )
    },
    TestCase("删除远程前返回受影响跟踪分支") {
        let fixture = try RemoteTrackingFixture.make()

        let impact = try await fixture.service.removalImpact(
            repositoryURL: fixture.repository.url,
            remote: "origin"
        )

        try expect(
            impact.trackingBranches.contains("main"),
            "应列出 main"
        )
    },
    TestCase("本地远程可测试连接编辑并确认删除") {
        let fixture = try RemoteTrackingFixture.make()
        let result = try await fixture.service.testConnection(
            repositoryURL: fixture.repository.url,
            remote: "origin",
            context: GitCredentialContext(accountID: "local")
        )
        try expectEqual(
            result,
            .connected(referenceCount: 1),
            "应读取本地远程分支"
        )
        let current = try await fixture.service.list(
            repositoryURL: fixture.repository.url
        )[0]
        try await fixture.service.update(
            repositoryURL: fixture.repository.url,
            originalName: "origin",
            change: GitRemoteChange(
                name: "upstream",
                fetchURL: current.fetchURL,
                pushURL: nil
            )
        )
        let updated = try await fixture.service.list(
            repositoryURL: fixture.repository.url
        )
        try expectEqual(updated[0].name, "upstream", "应重命名远程")

        let impact = try await fixture.service.removalImpact(
            repositoryURL: fixture.repository.url,
            remote: "upstream"
        )
        try await fixture.service.remove(
            repositoryURL: fixture.repository.url,
            remote: "upstream",
            confirmation: impact.confirmation
        )
        let remaining = try await fixture.service.list(
            repositoryURL: fixture.repository.url
        )
        try expect(remaining.isEmpty, "确认后应删除远程")
    }
]

private struct RemoteTrackingFixture: Sendable {
    let repository: TemporaryGitRepository
    let service: GitRemoteService

    static func make() throws -> RemoteTrackingFixture {
        let repository = try TemporaryGitRepository.make()
        try repository.write(path: "README.md", content: "# Test\n")
        try repository.commitAll(message: "初始")
        let remoteURL = try repository.makeBareRemote()
        try repository.run(["remote", "add", "origin", remoteURL.path])
        try repository.run(["push", "-u", "origin", "main"])
        let policy = GitRemoteTransportPolicy.localTest(
            allowedRoot: repository.temporaryRoot
        )
        let environment = GitCredentialEnvironment(
            credentialStore: InMemoryCredentialStore(),
            transportPolicy: policy
        )
        return RemoteTrackingFixture(
            repository: repository,
            service: GitRemoteService(
                transportPolicy: policy,
                credentialEnvironment: environment
            )
        )
    }
}
