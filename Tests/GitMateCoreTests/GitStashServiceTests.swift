import Foundation
import GitMateCore

let gitStashServiceTests = [
    TestCase("创建包含未跟踪文件的 Stash 并预览") {
        let repository = try TemporaryGitRepository.make()
        try repository.write(path: "tracked.txt", content: "base\n")
        try repository.commitAll(message: "初始")
        try repository.write(path: "tracked.txt", content: "changed\n")
        try repository.write(path: "未跟踪.txt", content: "new\n")
        let service = GitStashService()

        try await service.create(
            repositoryURL: repository.url,
            message: "保存现场",
            includeUntracked: true
        )

        let entries = try await service.list(
            repositoryURL: repository.url
        )
        try expectEqual(entries.count, 1, "应创建一个 Stash")
        try expect(
            entries[0].message.contains("保存现场"),
            "应保留说明"
        )
        let diff = try await service.diff(
            repositoryURL: repository.url,
            id: entries[0].id
        )
        try expect(
            diff.files.contains(where: { $0.path == "tracked.txt" }),
            "应预览文件"
        )
        try expect(
            !FileManager.default.fileExists(
                atPath: repository.url.appending(path: "未跟踪.txt").path
            ),
            "包含未跟踪文件时应清理工作区"
        )
    },
    TestCase("Apply 冲突保留原 Stash") {
        let fixture = try await StashConflictFixture.make()

        let result = try await fixture.service.apply(
            repositoryURL: fixture.repository.url,
            id: fixture.stashID
        )

        try expectEqual(result, .conflicted, "应报告冲突")
        let entries = try await fixture.service.list(
            repositoryURL: fixture.repository.url
        )
        try expect(
            entries.contains(where: { $0.id == fixture.stashID }),
            "Apply 冲突不得删除 Stash"
        )
        let hasUnmergedEntries = try fixture.repository.hasUnmergedEntries()
        try expect(hasUnmergedEntries, "真实仓库应保留待解决冲突")
    }
]

private struct StashConflictFixture: Sendable {
    let repository: TemporaryGitRepository
    let service: GitStashService
    let stashID: GitStashID

    static func make() async throws -> StashConflictFixture {
        let repository = try TemporaryGitRepository.make()
        try repository.write(path: "tracked.txt", content: "base\n")
        try repository.commitAll(message: "初始")
        try repository.run(["switch", "-c", "stash-source"])
        try repository.write(path: "tracked.txt", content: "stash\n")

        let service = GitStashService()
        try await service.create(
            repositoryURL: repository.url,
            message: "冲突现场",
            includeUntracked: false
        )
        let stashID = try await service.list(
            repositoryURL: repository.url
        )[0].id

        try repository.run(["switch", "main"])
        try repository.write(path: "tracked.txt", content: "main\n")
        try repository.commitAll(message: "主分支修改")
        return StashConflictFixture(
            repository: repository,
            service: service,
            stashID: stashID
        )
    }
}
