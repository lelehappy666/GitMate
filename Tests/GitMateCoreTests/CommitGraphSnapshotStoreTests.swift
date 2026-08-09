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
    TestCase("未来版本的提交图快照不会被刷新覆盖") {
        let directory = commitGraphSnapshotStoreTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let futureSchema = CommitGraphSnapshot.currentSchemaVersion + 1
        let futureSnapshot = CommitGraphSnapshot(
            schemaVersion: futureSchema,
            repositoryPath: "/repo",
            fingerprint: CommitGraphReferenceFingerprint(
                references: [],
                headName: "main",
                headHash: "future",
                isShallow: false
            ),
            commitsNewestFirst: [],
            expectedCommitCount: 0,
            shallowBoundaryParentHashes: [],
            generatedAt: Date(timeIntervalSince1970: 1)
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let targetURL = directory.appending(path: "9.plist")
        try encoder.encode(futureSnapshot).write(to: targetURL)
        let originalData = try Data(contentsOf: targetURL)
        let store = BinaryCommitGraphSnapshotStore(rootDirectory: directory)

        do {
            try await store.save(
                commitGraphSnapshotStoreFixture(repositoryPath: "/repo"),
                repositoryID: 9
            )
            throw TestFailure(description: "未来版本缓存不得被覆盖")
        } catch let error as CommitGraphSnapshotStoreError {
            try expectEqual(
                error,
                .unsupportedSchema(
                    repositoryID: 9,
                    schemaVersion: futureSchema
                ),
                "必须保留未来版本的原始缓存"
            )
        }
        let preservedData = try Data(contentsOf: targetURL)
        try expectEqual(
            preservedData,
            originalData,
            "拒绝保存后磁盘内容必须保持不变"
        )
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
    },
    TestCase("快照安装身份不遍历提交正文") {
        let generationID = UUID(
            uuidString: "11111111-2222-3333-4444-555555555555"
        )!
        let first = CommitGraphSnapshot(
            generationID: generationID,
            repositoryPath: "/repo",
            fingerprint: CommitGraphReferenceFingerprint(
                references: [],
                headName: "main",
                headHash: "head",
                isShallow: false
            ),
            commitsNewestFirst: [
                commitGraphSnapshotIdentityCommit(
                    hash: "head",
                    subject: "第一份正文"
                ),
                commitGraphSnapshotIdentityCommit(
                    hash: "root",
                    subject: "旧根提交"
                )
            ],
            expectedCommitCount: 2,
            shallowBoundaryParentHashes: [],
            generatedAt: Date(timeIntervalSince1970: 42)
        )
        let changedInterior = CommitGraphSnapshot(
            generationID: generationID,
            repositoryPath: first.repositoryPath,
            fingerprint: first.fingerprint,
            commitsNewestFirst: [
                commitGraphSnapshotIdentityCommit(
                    hash: "head",
                    subject: "完全不同但不参与身份比较的正文"
                ),
                commitGraphSnapshotIdentityCommit(
                    hash: "root",
                    subject: "另一份根提交正文"
                )
            ],
            expectedCommitCount: first.expectedCommitCount,
            shallowBoundaryParentHashes: [],
            generatedAt: first.generatedAt
        )
        let newerGeneration = CommitGraphSnapshot(
            generationID: UUID(
                uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
            )!,
            repositoryPath: first.repositoryPath,
            fingerprint: first.fingerprint,
            commitsNewestFirst: first.commitsNewestFirst,
            expectedCommitCount: first.expectedCommitCount,
            shallowBoundaryParentHashes: [],
            generatedAt: Date(timeIntervalSince1970: 43)
        )

        try expectEqual(
            CommitGraphSnapshotIdentity(first),
            CommitGraphSnapshotIdentity(changedInterior),
            "轻量身份不得通过 GitCommit Equatable 扫描提交正文"
        )
        try expect(
            CommitGraphSnapshotIdentity(first)
                != CommitGraphSnapshotIdentity(newerGeneration),
            "新生成的快照必须拥有不同安装身份"
        )
    },
    TestCase("快照代次标识编码解码和重复缓存读取保持不变") {
        let directory = commitGraphSnapshotStoreTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let generationID = UUID(
            uuidString: "12345678-1234-5678-9ABC-DEF012345678"
        )!
        let snapshot = CommitGraphSnapshot(
            generationID: generationID,
            repositoryPath: "/repo",
            fingerprint: CommitGraphReferenceFingerprint(
                references: [],
                headName: "main",
                headHash: "root",
                isShallow: false
            ),
            commitsNewestFirst: [
                commitGraphSnapshotIdentityCommit(
                    hash: "root",
                    subject: "初始提交"
                )
            ],
            expectedCommitCount: 1,
            shallowBoundaryParentHashes: [],
            generatedAt: Date(timeIntervalSince1970: 100)
        )
        let store = BinaryCommitGraphSnapshotStore(rootDirectory: directory)

        try await store.save(snapshot, repositoryID: 81)
        let firstLoad = try await store.load(repositoryID: 81)
        let secondLoad = try await store.load(repositoryID: 81)

        try expectEqual(firstLoad?.generationID, generationID, "编码解码必须保留代次标识")
        try expectEqual(secondLoad?.generationID, generationID, "重复命中同一缓存必须复用代次标识")
    },
    TestCase("相同时间边界和计数的新快照仍由代次标识区分") {
        let commonDate = Date(timeIntervalSince1970: 200)
        let commonFingerprint = CommitGraphReferenceFingerprint(
            references: [
                CommitGraphReference(
                    name: "refs/heads/main",
                    targetHash: "head",
                    kind: .localBranch
                )
            ],
            headName: "main",
            headHash: "head",
            isShallow: false
        )
        let first = CommitGraphSnapshot(
            repositoryPath: "/repo",
            fingerprint: commonFingerprint,
            commitsNewestFirst: [
                commitGraphSnapshotIdentityCommit(hash: "head", subject: "头"),
                commitGraphSnapshotIdentityCommit(hash: "middle-a", subject: "中间 A"),
                commitGraphSnapshotIdentityCommit(hash: "root", subject: "根")
            ],
            expectedCommitCount: 3,
            shallowBoundaryParentHashes: [],
            generatedAt: commonDate
        )
        let second = CommitGraphSnapshot(
            repositoryPath: "/repo",
            fingerprint: CommitGraphReferenceFingerprint(
                references: commonFingerprint.references + [
                    CommitGraphReference(
                        name: "refs/remotes/origin/feature",
                        targetHash: "middle-b",
                        kind: .remoteBranch
                    )
                ],
                headName: commonFingerprint.headName,
                headHash: commonFingerprint.headHash,
                isShallow: commonFingerprint.isShallow
            ),
            commitsNewestFirst: [
                commitGraphSnapshotIdentityCommit(hash: "head", subject: "头"),
                commitGraphSnapshotIdentityCommit(hash: "middle-b", subject: "中间 B"),
                commitGraphSnapshotIdentityCommit(hash: "root", subject: "根")
            ],
            expectedCommitCount: 3,
            shallowBoundaryParentHashes: [],
            generatedAt: commonDate
        )

        try expect(
            first.generationID != second.generationID,
            "每个新建的完整快照必须自动生成独立代次标识"
        )
        try expect(
            CommitGraphSnapshotIdentity(first) != CommitGraphSnapshotIdentity(second),
            "即使旧轻量字段全部相同，新读取也必须由 generationID 区分"
        )
    },
    TestCase("旧版快照迁移后获得稳定代次标识") {
        let directory = commitGraphSnapshotStoreTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let legacy = LegacyCommitGraphSnapshotV1(
            schemaVersion: 1,
            repositoryPath: "/legacy",
            fingerprint: CommitGraphReferenceFingerprint(
                references: [],
                headName: "main",
                headHash: "root",
                isShallow: false
            ),
            commitsNewestFirst: [
                commitGraphSnapshotIdentityCommit(hash: "root", subject: "旧提交")
            ],
            expectedCommitCount: 1,
            shallowBoundaryParentHashes: [],
            generatedAt: Date(timeIntervalSince1970: 300)
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(legacy).write(
            to: directory.appending(path: "82.plist")
        )
        let store = BinaryCommitGraphSnapshotStore(rootDirectory: directory)

        let firstLoad = try await store.load(repositoryID: 82)
        let secondLoad = try await store.load(repositoryID: 82)

        try expectEqual(
            firstLoad?.schemaVersion,
            CommitGraphSnapshot.currentSchemaVersion,
            "旧版缓存必须迁移到当前 schema"
        )
        try expectEqual(
            firstLoad?.generationID,
            secondLoad?.generationID,
            "未写 generationID 的旧缓存每次读取也必须得到稳定标识"
        )
    },
    TestCase("schema 2 快照迁移到 schema 3 并补全符号目标") {
        let directory = commitGraphSnapshotStoreTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let generationID = UUID(
            uuidString: "21212121-3434-5656-7878-909090909090"
        )!
        let legacy = LegacyCommitGraphSnapshotV2(
            schemaVersion: 2,
            generationID: generationID,
            repositoryPath: "/legacy-v2",
            fingerprint: LegacyCommitGraphReferenceFingerprintV2(
                references: [
                    LegacyCommitGraphReferenceV2(
                        name: "refs/remotes/origin/HEAD",
                        targetHash: "root",
                        kind: .remoteBranch
                    )
                ],
                headName: "main",
                headHash: "root",
                isShallow: false
            ),
            commitsNewestFirst: [
                commitGraphSnapshotIdentityCommit(hash: "root", subject: "v2 提交")
            ],
            expectedCommitCount: 1,
            shallowBoundaryParentHashes: [],
            generatedAt: Date(timeIntervalSince1970: 301)
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(legacy).write(
            to: directory.appending(path: "83.plist")
        )
        let store = BinaryCommitGraphSnapshotStore(rootDirectory: directory)

        let restored = try await store.load(repositoryID: 83)

        try expectEqual(
            restored?.schemaVersion,
            CommitGraphSnapshot.currentSchemaVersion,
            "schema 2 必须迁移到当前版本"
        )
        try expectEqual(restored?.generationID, generationID, "schema 2 代次标识必须保留")
        try expectEqual(
            restored?.fingerprint.references.first?.symbolicTarget,
            nil,
            "旧引用缺少 symref 时必须兼容为 nil"
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

private struct LegacyCommitGraphSnapshotV1: Codable {
    let schemaVersion: Int
    let repositoryPath: String
    let fingerprint: CommitGraphReferenceFingerprint
    let commitsNewestFirst: [GitCommit]
    let expectedCommitCount: Int
    let shallowBoundaryParentHashes: Set<String>
    let generatedAt: Date
}

private struct LegacyCommitGraphReferenceV2: Codable {
    let name: String
    let targetHash: String
    let kind: CommitGraphReferenceKind
}

private struct LegacyCommitGraphReferenceFingerprintV2: Codable {
    let references: [LegacyCommitGraphReferenceV2]
    let headName: String?
    let headHash: String?
    let isShallow: Bool
}

private struct LegacyCommitGraphSnapshotV2: Codable {
    let schemaVersion: Int
    let generationID: UUID
    let repositoryPath: String
    let fingerprint: LegacyCommitGraphReferenceFingerprintV2
    let commitsNewestFirst: [GitCommit]
    let expectedCommitCount: Int
    let shallowBoundaryParentHashes: Set<String>
    let generatedAt: Date
}

private func commitGraphSnapshotIdentityCommit(
    hash: String,
    subject: String
) -> GitCommit {
    GitCommit(
        shortHash: hash,
        fullHash: hash,
        subject: subject,
        authorName: "测试用户",
        authorEmail: "test@example.com",
        authoredAt: Date(timeIntervalSince1970: 1),
        parentHashes: [],
        decorations: []
    )
}
