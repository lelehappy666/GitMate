import Foundation
import GitMateCore

private let destinationRepository = Repository(
    id: 501,
    name: "mac-client",
    fullName: "GitMate/mac-client",
    isPrivate: true,
    defaultBranch: "main",
    sizeInKilobytes: 2_048,
    cloneURL: URL(string: "https://github.com/GitMate/mac-client.git")!,
    ownerAvatarURL: nil
)

private func destinationTestDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(
            path: "GitMateDestinationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
}

let syncDestinationTests = [
    TestCase("同步目录存储支持保存并恢复用户选择") {
        let store = InMemorySyncDestinationStore()
        let destination = try destinationTestDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }

        try expect(store.destination() == nil, "首次使用必须由用户选择目录")
        try store.save(destination: destination)
        try expectEqual(
            store.destination(),
            destination,
            "重新打开应用后应恢复用户选择的目录"
        )
    },
    TestCase("非 Git 的同名文件夹会阻止同步") {
        let destination = try destinationTestDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let repositoryDirectory = destination.appending(
            path: destinationRepository.name,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: repositoryDirectory,
            withIntermediateDirectories: true
        )
        try Data("用户文件".utf8).write(
            to: repositoryDirectory.appending(path: "README.md")
        )

        let conflicts = SyncDestinationInspector.conflicts(
            repositories: [destinationRepository],
            preferences: [
                RepositorySyncPreference(repositoryID: 501, mode: .manual)
            ],
            destination: destination
        )

        try expectEqual(conflicts.count, 1, "同名非 Git 文件夹必须报告冲突")
        try expectEqual(
            conflicts.first?.lastPathComponent,
            "mac-client",
            "冲突提示应包含目标文件夹"
        )
    },
    TestCase("相同远端的已有 Git 仓库允许继续同步") {
        let destination = try destinationTestDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let gitDirectory = destination
            .appending(path: destinationRepository.name, directoryHint: .isDirectory)
            .appending(path: ".git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: gitDirectory,
            withIntermediateDirectories: true
        )
        let config = """
        [remote "origin"]
            url = https://github.com/GitMate/mac-client.git
        """
        try Data(config.utf8).write(
            to: gitDirectory.appending(path: "config")
        )

        let conflicts = SyncDestinationInspector.conflicts(
            repositories: [destinationRepository],
            preferences: [
                RepositorySyncPreference(repositoryID: 501, mode: .automatic)
            ],
            destination: destination
        )

        try expect(conflicts.isEmpty, "相同远端的 Git 仓库应允许 fetch")
    },
    TestCase("不同远端的同名 Git 仓库会阻止同步") {
        let destination = try destinationTestDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let gitDirectory = destination
            .appending(path: destinationRepository.name, directoryHint: .isDirectory)
            .appending(path: ".git", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: gitDirectory,
            withIntermediateDirectories: true
        )
        let config = """
        [remote "origin"]
            url = https://github.com/OtherOwner/mac-client.git
        """
        try Data(config.utf8).write(
            to: gitDirectory.appending(path: "config")
        )

        let conflicts = SyncDestinationInspector.conflicts(
            repositories: [destinationRepository],
            preferences: [
                RepositorySyncPreference(repositoryID: 501, mode: .manual)
            ],
            destination: destination
        )

        try expectEqual(conflicts.count, 1, "不同远端的同名仓库必须报告冲突")
    }
]
