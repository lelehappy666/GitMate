import Foundation
import GitMateCore

let commitGraphSnapshotStoreTests = [
    TestCase("提交图快照按仓库原子保存并恢复") {
        let directory = commitGraphSnapshotStoreTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = BinaryCommitGraphSnapshotStore(rootDirectory: directory)
        let snapshot = commitGraphSnapshotStoreFixture(repositoryPath: "/repo")

        try await store.save(snapshot, repositoryID: 42)
        let restored = try await store.load(repositoryID: 42)

        try expectEqual(
            restored,
            snapshot,
            "快照必须完整恢复"
        )
        let data = try Data(contentsOf: directory.appending(path: "42.plist"))
        try expect(
            data.starts(with: Data("bplist".utf8)),
            "快照必须使用二进制 Property List 保存"
        )
    },
    TestCase("不同仓库的提交图快照相互隔离") {
        let directory = commitGraphSnapshotStoreTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = BinaryCommitGraphSnapshotStore(rootDirectory: directory)
        let first = commitGraphSnapshotStoreFixture(repositoryPath: "/repo-one")
        let second = commitGraphSnapshotStoreFixture(repositoryPath: "/repo-two")

        try await store.save(first, repositoryID: 1)
        try await store.save(second, repositoryID: 2)
        let restoredFirst = try await store.load(repositoryID: 1)
        let restoredSecond = try await store.load(repositoryID: 2)
        let missing = try await store.load(repositoryID: 3)

        try expectEqual(
            restoredFirst,
            first,
            "仓库一不得读取仓库二的快照"
        )
        try expectEqual(
            restoredSecond,
            second,
            "仓库二不得读取仓库一的快照"
        )
        try expectEqual(
            missing,
            nil,
            "不存在的仓库应返回空快照"
        )
    },
    TestCase("损坏快照返回稳定错误") {
        let directory = commitGraphSnapshotStoreTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("broken".utf8).write(to: directory.appending(path: "7.plist"))
        let store = BinaryCommitGraphSnapshotStore(rootDirectory: directory)

        do {
            _ = try await store.load(repositoryID: 7)
            throw TestFailure(description: "损坏快照必须失败")
        } catch let error as CommitGraphSnapshotStoreError {
            try expectEqual(
                error,
                .corruptedSnapshot(repositoryID: 7),
                "损坏快照必须返回稳定错误"
            )
        }
    },
    TestCase("读取提交图快照的文件系统错误原样传播") {
        let directory = commitGraphSnapshotStoreTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("readable".utf8).write(to: directory.appending(path: "70.plist"))
        let store = BinaryCommitGraphSnapshotStore(
            rootDirectory: directory,
            dataReader: { _ in throw CommitGraphSnapshotStoreReadTestError.unavailable }
        )

        do {
            _ = try await store.load(repositoryID: 70)
            throw TestFailure(description: "文件系统错误必须原样传播")
        } catch let error as CommitGraphSnapshotStoreReadTestError {
            try expectEqual(
                error,
                .unavailable,
                "文件系统读取错误不得被误判为损坏快照"
            )
        }
    },
    TestCase("不支持的提交图快照版本返回稳定错误") {
        let directory = commitGraphSnapshotStoreTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let outdated = CommitGraphSnapshot(
            schemaVersion: CommitGraphSnapshot.currentSchemaVersion + 1,
            repositoryPath: "/repo",
            fingerprint: CommitGraphReferenceFingerprint(
                references: [],
                headName: "main",
                headHash: "root",
                isShallow: false
            ),
            commitsNewestFirst: [],
            expectedCommitCount: 0,
            shallowBoundaryParentHashes: [],
            generatedAt: Date(timeIntervalSince1970: 1)
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(outdated).write(to: directory.appending(path: "8.plist"))
        let store = BinaryCommitGraphSnapshotStore(rootDirectory: directory)

        do {
            _ = try await store.load(repositoryID: 8)
            throw TestFailure(description: "不支持的版本必须失败")
        } catch let error as CommitGraphSnapshotStoreError {
            try expectEqual(
                error,
                .unsupportedSchema(
                    repositoryID: 8,
                    schemaVersion: CommitGraphSnapshot.currentSchemaVersion + 1
                ),
                "版本错误必须返回稳定错误"
            )
        }
    },
    TestCase("临时文件不会被识别为提交图快照") {
        let directory = commitGraphSnapshotStoreTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(commitGraphSnapshotStoreFixture(repositoryPath: "/repo"))
            .write(to: directory.appending(path: ".9.pending-\(UUID()).plist"))
        let store = BinaryCommitGraphSnapshotStore(rootDirectory: directory)
        let restored = try await store.load(repositoryID: 9)

        try expectEqual(
            restored,
            nil,
            "仅有临时文件时不得恢复不完整快照"
        )
    }
]

private func commitGraphSnapshotStoreFixture(
    repositoryPath: String
) -> CommitGraphSnapshot {
    CommitGraphSnapshot(
        repositoryPath: repositoryPath,
        fingerprint: CommitGraphReferenceFingerprint(
            references: [
                CommitGraphReference(
                    name: "refs/heads/main",
                    targetHash: "root",
                    kind: .localBranch
                )
            ],
            headName: "main",
            headHash: "root",
            isShallow: false
        ),
        commitsNewestFirst: [
            GitCommit(
                shortHash: "root",
                fullHash: "root",
                subject: "初始提交",
                authorName: "测试用户",
                authorEmail: "test@example.com",
                authoredAt: Date(timeIntervalSince1970: 1),
                parentHashes: [],
                decorations: ["HEAD -> main"]
            )
        ],
        expectedCommitCount: 1,
        shallowBoundaryParentHashes: [],
        generatedAt: Date(timeIntervalSince1970: 2)
    )
}

private func commitGraphSnapshotStoreTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appending(
            path: "GitMateCommitGraphSnapshotStoreTests",
            directoryHint: .isDirectory
        )
        .appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
}

private enum CommitGraphSnapshotStoreReadTestError: Error, Equatable, Sendable {
    case unavailable
}
