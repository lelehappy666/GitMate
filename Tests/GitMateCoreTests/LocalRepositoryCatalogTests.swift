import Foundation
import GitMateCore

private let repositoryFixture = Repository(
    id: 42,
    name: "mac-client",
    fullName: "gitmate/mac-client",
    isPrivate: true,
    defaultBranch: "main",
    sizeInKilobytes: 0,
    cloneURL: URL(string: "https://github.com/gitmate/mac-client.git")!,
    ownerAvatarURL: nil
)

private struct FakeRepositoryFileSystem: RepositoryFileSystem {
    let directories: Set<String>
    let byteCounts: [String: Int64]

    init(directories: [String], byteCounts: [String: Int64]) {
        self.directories = Set(directories)
        self.byteCounts = byteCounts
    }

    func itemExists(at url: URL) -> Bool {
        directories.contains(url.path)
    }

    func recursiveByteCount(at url: URL) throws -> Int64 {
        byteCounts[url.path] ?? 0
    }
}

private func temporaryWorkspaceCacheDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "GitMateWorkspaceCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

let localRepositoryCatalogTests = [
    TestCase("仓库映射到首次同步目录") {
        let fileSystem = FakeRepositoryFileSystem(
            directories: ["/sync/mac-client/.git"],
            byteCounts: ["/sync/mac-client": 2_048]
        )
        let catalog = LocalRepositoryCatalog(
            rootDirectory: URL(fileURLWithPath: "/sync"),
            fileSystem: fileSystem
        )

        let record = try catalog.record(for: repositoryFixture)

        try expectEqual(record.localURL.path, "/sync/mac-client", "应使用同步目录")
        try expectEqual(record.availability, .available, "存在 .git 时应可用")
        try expectEqual(record.localSizeInBytes, 2_048, "应返回本地大小")
    },
    TestCase("缺少 Git 元数据时标记损坏") {
        let fileSystem = FakeRepositoryFileSystem(
            directories: ["/sync/mac-client"],
            byteCounts: [:]
        )
        let catalog = LocalRepositoryCatalog(
            rootDirectory: URL(fileURLWithPath: "/sync"),
            fileSystem: fileSystem
        )

        let record = try catalog.record(for: repositoryFixture)

        try expectEqual(record.availability, .damaged, "目录存在但无 .git 应标记损坏")
    },
    TestCase("不存在的仓库目录标记缺失") {
        let catalog = LocalRepositoryCatalog(
            rootDirectory: URL(fileURLWithPath: "/sync"),
            fileSystem: FakeRepositoryFileSystem(directories: [], byteCounts: [:])
        )

        let record = try catalog.record(for: repositoryFixture)

        try expectEqual(record.availability, .missing, "目录不存在应标记缺失")
        try expectEqual(record.localSizeInBytes, 0, "缺失目录大小应为零")
    },
    TestCase("目录名沿用首次同步的安全规则") {
        let unsafeRepository = Repository(
            id: 43,
            name: "../client:windows\\build",
            fullName: "gitmate/client",
            isPrivate: true,
            defaultBranch: "main",
            sizeInKilobytes: 0,
            cloneURL: URL(string: "https://github.com/gitmate/client.git")!,
            ownerAvatarURL: nil
        )
        let catalog = LocalRepositoryCatalog(
            rootDirectory: URL(fileURLWithPath: "/sync"),
            fileSystem: FakeRepositoryFileSystem(directories: [], byteCounts: [:])
        )

        let record = try catalog.record(for: unsafeRepository)

        try expectEqual(record.localURL.path, "/sync/..-client-windows-build", "不安全字符应替换为连字符")
    },
    TestCase("精确点号仓库名不会逃出同步根目录") {
        let dotRepository = Repository(
            id: 44,
            name: ".",
            fullName: "gitmate/dot",
            isPrivate: true,
            defaultBranch: "main",
            sizeInKilobytes: 0,
            cloneURL: URL(string: "https://github.com/gitmate/dot.git")!,
            ownerAvatarURL: nil
        )
        let dotDotRepository = Repository(
            id: 45,
            name: "..",
            fullName: "gitmate/dot-dot",
            isPrivate: true,
            defaultBranch: "main",
            sizeInKilobytes: 0,
            cloneURL: URL(string: "https://github.com/gitmate/dot-dot.git")!,
            ownerAvatarURL: nil
        )

        try expectEqual(dotRepository.safeLocalDirectoryName, "repository-.", "单点目录名必须安全化")
        try expectEqual(dotDotRepository.safeLocalDirectoryName, "repository-..", "双点目录名必须安全化")
    },
    TestCase("默认文件系统统计真实仓库目录") {
        let directory = try temporaryWorkspaceCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repositoryDirectory = directory.appending(path: "mac-client", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: repositoryDirectory.appending(path: ".git", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let fileURL = repositoryDirectory.appending(path: "README.md")
        try Data("1234".utf8).write(to: fileURL)
        let catalog = LocalRepositoryCatalog(rootDirectory: directory)

        let record = try catalog.record(for: repositoryFixture)

        try expectEqual(record.availability, .available, "真实 Git 目录应可用")
        try expect(record.localSizeInBytes >= 4, "本地大小应包含仓库文件")
    },
    TestCase("默认文件系统无法枚举时抛出错误") {
        let directory = try temporaryWorkspaceCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not-a-directory".utf8).write(
            to: directory.appending(path: "mac-client")
        )
        let catalog = LocalRepositoryCatalog(rootDirectory: directory)
        var didThrow = false

        do {
            _ = try catalog.record(for: repositoryFixture)
        } catch {
            didThrow = true
        }

        try expect(didThrow, "无法枚举仓库目录时不应伪装为零字节成功")
    },
    TestCase("缓存按账户保存读取并可清理") {
        let directory = try temporaryWorkspaceCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JSONWorkspaceCache(rootDirectory: directory)
        let summary = RepositoryOnlineSummary(
            repositoryID: 42,
            primaryLanguage: "Swift",
            openIssueCount: 3,
            openPullRequestCount: 2,
            failedWorkflowCount: 1,
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
        let snapshot = WorkspaceCacheSnapshot(
            accountID: "octo-cat",
            repositoryRecords: [
                LocalRepositoryRecord(
                    repository: repositoryFixture,
                    localURL: URL(fileURLWithPath: "/sync/mac-client"),
                    availability: .available,
                    localSizeInBytes: 2_048,
                    lastInspectedAt: Date(timeIntervalSince1970: 1_710_000_100)
                )
            ],
            onlineSummaries: [42: summary],
            savedAt: Date(timeIntervalSince1970: 1_710_000_200)
        )

        try cache.save(snapshot)
        let loadedSnapshot = try cache.load(accountID: "octo-cat")
        try expectEqual(loadedSnapshot, snapshot, "读取的缓存应与保存内容一致")
        try cache.clear(accountID: "octo-cat")
        let clearedSnapshot = try cache.load(accountID: "octo-cat")
        try expectEqual(clearedSnapshot, nil, "清理后不应读取到缓存")
    },
    TestCase("缓存迁移仓库身份并移除同名旧记录与摘要") {
        let directory = try temporaryWorkspaceCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JSONWorkspaceCache(rootDirectory: directory)
        let syntheticRepository = Repository(
            id: -900,
            name: "mac-client",
            fullName: "GitMate/mac-client",
            isPrivate: true,
            defaultBranch: "develop",
            sizeInKilobytes: 1,
            cloneURL: URL(
                string: "https://github.com/GitMate/mac-client.git"
            )!,
            ownerAvatarURL: nil,
            primaryLanguage: nil
        )
        let remoteRepository = Repository(
            id: 101,
            name: "mac-client",
            fullName: "gitmate/MAC-client",
            isPrivate: true,
            defaultBranch: "main",
            sizeInKilobytes: 2_400,
            cloneURL: URL(
                string: "https://github.com/gitmate/mac-client.git"
            )!,
            ownerAvatarURL: URL(
                string: "https://avatars.githubusercontent.com/u/1"
            ),
            primaryLanguage: "Swift"
        )
        let localURL = URL(
            filePath: "/仓库/mac-client",
            directoryHint: .isDirectory
        )
        let oldSummary = RepositoryOnlineSummary(
            repositoryID: syntheticRepository.id,
            primaryLanguage: "Swift",
            openIssueCount: 3,
            openPullRequestCount: 2,
            failedWorkflowCount: 1,
            remoteUpdatedAt: Date(timeIntervalSince1970: 1_000)
        )
        try cache.save(
            WorkspaceCacheSnapshot(
                accountID: "octo-cat",
                repositoryRecords: [
                    LocalRepositoryRecord(
                        repository: syntheticRepository,
                        localURL: localURL,
                        availability: .available,
                        localSizeInBytes: 4_096,
                        lastInspectedAt: Date(timeIntervalSince1970: 2_000)
                    ),
                    LocalRepositoryRecord(
                        repository: remoteRepository,
                        localURL: URL(
                            filePath: "/旧路径/mac-client",
                            directoryHint: .isDirectory
                        ),
                        availability: .missing,
                        localSizeInBytes: 0,
                        lastInspectedAt: Date(timeIntervalSince1970: 1_500)
                    )
                ],
                onlineSummaries: [
                    syntheticRepository.id: oldSummary
                ],
                savedAt: Date(timeIntervalSince1970: 2_000)
            )
        )

        try cache.migrateRepositoryIdentity(
            accountID: "octo-cat",
            from: syntheticRepository,
            to: remoteRepository,
            localURL: localURL,
            migratedAt: Date(timeIntervalSince1970: 3_000)
        )

        let snapshot = try cache.load(accountID: "octo-cat")
        try expectEqual(
            snapshot?.repositoryRecords.map(\.repository),
            [remoteRepository],
            "身份迁移后只应保留真实 GitHub 仓库"
        )
        try expectEqual(
            snapshot?.repositoryRecords.first?.localURL,
            localURL,
            "身份迁移必须保留用户选择的本地路径"
        )
        try expectEqual(
            snapshot?.repositoryRecords.first?.localSizeInBytes,
            4_096,
            "身份迁移必须保留已统计的本地大小"
        )
        try expectEqual(
            snapshot?.onlineSummaries.keys.sorted(),
            [remoteRepository.id],
            "身份迁移必须删除合成编号摘要"
        )
        try expectEqual(
            snapshot?.onlineSummaries[remoteRepository.id]?.repositoryID,
            remoteRepository.id,
            "迁移后的摘要必须引用真实 GitHub 编号"
        )
        try expectEqual(
            snapshot?.savedAt,
            Date(timeIntervalSince1970: 3_000),
            "迁移时间应成为新的缓存保存时间"
        )

        try cache.update(accountID: "octo-cat") { latestSnapshot in
            var records = latestSnapshot?.repositoryRecords ?? []
            records.append(
                LocalRepositoryRecord(
                    repository: syntheticRepository,
                    localURL: localURL,
                    availability: .available,
                    localSizeInBytes: 4_096,
                    lastInspectedAt: Date(timeIntervalSince1970: 2_500)
                )
            )
            var summaries = latestSnapshot?.onlineSummaries ?? [:]
            summaries[syntheticRepository.id] = oldSummary
            return WorkspaceCacheSnapshot(
                accountID: "octo-cat",
                repositoryRecords: records,
                onlineSummaries: summaries,
                savedAt: Date(timeIntervalSince1970: 4_000)
            )
        }

        let snapshotAfterStaleWrite = try cache.load(
            accountID: "octo-cat"
        )
        try expectEqual(
            snapshotAfterStaleWrite?.repositoryRecords.map(\.repository.id),
            [remoteRepository.id],
            "迁移完成后的旧任务不得写回合成仓库身份"
        )
        try expectEqual(
            snapshotAfterStaleWrite?.onlineSummaries.keys.sorted(),
            [remoteRepository.id],
            "迁移完成后的旧摘要必须继续归并到真实编号"
        )
    },
    TestCase("缓存写入时移除仓库地址中的凭据") {
        let directory = try temporaryWorkspaceCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = Repository(
            id: 99,
            name: "private-client",
            fullName: "gitmate/private-client",
            isPrivate: true,
            defaultBranch: "main",
            sizeInKilobytes: 0,
            cloneURL: URL(string: "https://reader:should-not-be-written@github.com/gitmate/private-client.git?secret=should-not-be-written")!,
            ownerAvatarURL: nil
        )
        let snapshot = WorkspaceCacheSnapshot(
            accountID: "octo-cat",
            repositoryRecords: [
                LocalRepositoryRecord(
                    repository: repository,
                    localURL: URL(fileURLWithPath: "/sync/private-client"),
                    availability: .available,
                    localSizeInBytes: 0,
                    lastInspectedAt: Date(timeIntervalSince1970: 1_710_000_100)
                )
            ],
            onlineSummaries: [:],
            savedAt: Date(timeIntervalSince1970: 1_710_000_200)
        )
        let cache = JSONWorkspaceCache(rootDirectory: directory)

        try cache.save(snapshot)

        let cacheURL = directory
            .appending(path: "octo-cat", directoryHint: .isDirectory)
            .appending(path: "workspace.json")
        let content = try String(decoding: Data(contentsOf: cacheURL), as: UTF8.self)
        try expect(!content.contains("should-not-be-written"), "缓存文件不应包含仓库地址中的凭据")
    },
    TestCase("缓存清洗所有可编码 URL 后仍可读取") {
        let directory = try temporaryWorkspaceCacheDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sensitiveValue = "should-not-be-written"
        let repository = Repository(
            id: 100,
            name: "private-client",
            fullName: "gitmate/private-client",
            isPrivate: true,
            defaultBranch: "main",
            sizeInKilobytes: 0,
            cloneURL: URL(string: "https://github.com/gitmate/private-client.git")!,
            ownerAvatarURL: URL(string: "https://reader:\(sensitiveValue)@avatars.example.com/avatar.png?secret=\(sensitiveValue)#fragment")
        )
        let snapshot = WorkspaceCacheSnapshot(
            accountID: "octo-cat",
            repositoryRecords: [
                LocalRepositoryRecord(
                    repository: repository,
                    localURL: URL(string: "https://reader:\(sensitiveValue)@local.example.com/private-client?secret=\(sensitiveValue)#fragment")!,
                    availability: .available,
                    localSizeInBytes: 0,
                    lastInspectedAt: Date(timeIntervalSince1970: 1_710_000_100)
                )
            ],
            onlineSummaries: [:],
            savedAt: Date(timeIntervalSince1970: 1_710_000_200)
        )
        let cache = JSONWorkspaceCache(rootDirectory: directory)

        try cache.save(snapshot)

        let cacheURL = directory
            .appending(path: "octo-cat", directoryHint: .isDirectory)
            .appending(path: "workspace.json")
        let content = try String(decoding: Data(contentsOf: cacheURL), as: UTF8.self)
        let loadedSnapshot = try cache.load(accountID: "octo-cat")
        let loadedRecord = loadedSnapshot?.repositoryRecords.first
        try expect(!content.contains(sensitiveValue), "缓存文件不应包含任意 URL 中的凭据")
        try expectEqual(
            loadedRecord?.repository.ownerAvatarURL,
            URL(string: "https://avatars.example.com/avatar.png"),
            "读取的头像地址应保持可解码且无凭据"
        )
        try expectEqual(
            loadedRecord?.localURL,
            URL(string: "https://local.example.com/private-client"),
            "读取的本地地址应保持可解码且无凭据"
        )
    }
]
