import Foundation
import GitMateCore

let commitGraphRefreshCoordinatorTests = [
    TestCase("指纹未变化时复用缓存且仍执行完整性校验") {
        let snapshot = refreshSnapshot(hash: "a")
        let reader = CountingSnapshotReader(
            fingerprint: snapshot.fingerprint,
            snapshots: [snapshot]
        )
        let store = InMemorySnapshotStore(snapshot: snapshot)
        let coordinator = CommitGraphRefreshCoordinator(
            reader: reader,
            store: store
        )

        let result = try await coordinator.refresh(
            repositoryID: 1,
            repositoryURL: URL(filePath: "/repo")
        )
        let snapshotCalls = await reader.snapshotCallCount()
        let saveCount = await store.saveCount()

        try expectEqual(result.didChange, false, "相同指纹不得重建快照")
        try expectEqual(result.usedCache, true, "相同指纹必须使用缓存")
        try expectEqual(snapshotCalls, 0, "不得读取完整日志")
        try expectEqual(saveCount, 0, "缓存未变化时不得重复保存")
        try expectEqual(result.integrity.status, .valid, "仍需执行内存校验")
    },
    TestCase("指纹变化时读取完整快照并保存新结果") {
        let cached = refreshSnapshot(hash: "a")
        let fresh = refreshSnapshot(hash: "b")
        let reader = CountingSnapshotReader(
            fingerprint: fresh.fingerprint,
            snapshots: [fresh]
        )
        let store = InMemorySnapshotStore(snapshot: cached)
        let coordinator = CommitGraphRefreshCoordinator(
            reader: reader,
            store: store
        )

        let result = try await coordinator.refresh(
            repositoryID: 2,
            repositoryURL: URL(filePath: "/repo")
        )
        let saved = await store.currentSnapshot(repositoryID: 2)

        try expectEqual(result.snapshot, fresh, "必须返回当前 Git 快照")
        try expectEqual(result.didChange, true, "指纹变化必须标记拓扑变化")
        try expectEqual(result.usedCache, false, "重读结果不得标记为缓存")
        try expectEqual(saved, fresh, "有效候选快照必须保存")
    },
    TestCase("无效候选快照绕过缓存重读一次") {
        let invalid = refreshInvalidSnapshot(hash: "broken")
        let valid = refreshSnapshot(hash: "b")
        let reader = CountingSnapshotReader(
            fingerprint: valid.fingerprint,
            snapshots: [invalid, valid]
        )
        let store = InMemorySnapshotStore()
        let coordinator = CommitGraphRefreshCoordinator(
            reader: reader,
            store: store
        )

        let result = try await coordinator.refresh(
            repositoryID: 3,
            repositoryURL: URL(filePath: "/repo")
        )
        let snapshotCalls = await reader.snapshotCallCount()

        try expectEqual(snapshotCalls, 2, "无效候选必须且只能重读一次")
        try expectEqual(result.snapshot, valid, "必须采用第二次有效读取")
        try expectEqual(result.integrity.status, .valid, "最终快照必须有效")
    },
    TestCase("连续两次无效快照返回稳定完整性错误且不写缓存") {
        let first = refreshInvalidSnapshot(hash: "broken-a")
        let second = refreshInvalidSnapshot(hash: "broken-b")
        let reader = CountingSnapshotReader(
            fingerprint: first.fingerprint,
            snapshots: [first, second]
        )
        let store = InMemorySnapshotStore()
        let coordinator = CommitGraphRefreshCoordinator(
            reader: reader,
            store: store
        )

        do {
            _ = try await coordinator.refresh(
                repositoryID: 4,
                repositoryURL: URL(filePath: "/repo")
            )
            throw TestFailure(description: "第二次无效必须失败")
        } catch let error as CommitGraphRefreshError {
            switch error {
            case let .invalidSnapshot(report):
                try expectEqual(
                    report.status,
                    .invalid,
                    "错误必须携带第二次完整性报告"
                )
            case .referencesChangedDuringScan:
                throw TestFailure(description: "引用未变化时不得返回引用漂移错误")
            }
        }
        let snapshotCalls = await reader.snapshotCallCount()
        let saveCount = await store.saveCount()
        try expectEqual(snapshotCalls, 2, "只允许一次重试")
        try expectEqual(saveCount, 0, "无效快照不得写入缓存")
    },
    TestCase("较慢旧刷新不能覆盖较新刷新") {
        let reader = ControlledSnapshotReader()
        let store = InMemorySnapshotStore()
        let coordinator = CommitGraphRefreshCoordinator(
            reader: reader,
            store: store
        )
        let repositoryURL = URL(filePath: "/repo")
        let first = Task {
            try await coordinator.refresh(
                repositoryID: 5,
                repositoryURL: repositoryURL
            )
        }
        await reader.waitForRequest(1)
        let second = Task {
            try await coordinator.refresh(
                repositoryID: 5,
                repositoryURL: repositoryURL
            )
        }
        await reader.waitForRequest(2)
        let snapshotB = refreshSnapshot(hash: "b")
        await reader.completeRequest(2, snapshot: snapshotB)
        let secondResult = try await second.value
        await reader.completeRequest(1, snapshot: refreshSnapshot(hash: "a"))

        do {
            _ = try await first.value
            throw TestFailure(description: "旧刷新必须被取消")
        } catch is CancellationError {
            // 预期路径。
        }
        let saved = await store.currentSnapshot()
        try expectEqual(secondResult.snapshot, snapshotB, "较新刷新必须完成")
        try expectEqual(saved, snapshotB, "旧任务不得覆盖较新缓存")
    },
    TestCase("刷新仓库 A 不得取消仓库 B") {
        let reader = ControlledSnapshotReader()
        let store = InMemorySnapshotStore()
        let coordinator = CommitGraphRefreshCoordinator(
            reader: reader,
            store: store
        )
        let firstA = Task {
            try await coordinator.refresh(
                repositoryID: 10,
                repositoryURL: URL(filePath: "/repo-a")
            )
        }
        await reader.waitForRequest(1)
        let firstB = Task {
            try await coordinator.refresh(
                repositoryID: 20,
                repositoryURL: URL(filePath: "/repo-b")
            )
        }
        await reader.waitForRequest(2)
        let secondA = Task {
            try await coordinator.refresh(
                repositoryID: 10,
                repositoryURL: URL(filePath: "/repo-a")
            )
        }
        await reader.waitForRequest(3)

        let snapshotB = refreshSnapshot(hash: "b", path: "/repo-b")
        let snapshotA = refreshSnapshot(hash: "c", path: "/repo-a")
        await reader.completeRequest(2, snapshot: snapshotB)
        await reader.completeRequest(3, snapshot: snapshotA)
        let resultB = try await firstB.value
        let resultA = try await secondA.value
        await reader.completeRequest(1, snapshot: refreshSnapshot(hash: "a", path: "/repo-a"))

        do {
            _ = try await firstA.value
            throw TestFailure(description: "仓库 A 的旧刷新必须被取消")
        } catch is CancellationError {
            // 预期路径。
        }
        try expectEqual(resultB.snapshot, snapshotB, "仓库 B 刷新不得受影响")
        try expectEqual(resultA.snapshot, snapshotA, "仓库 A 新刷新必须完成")
    },
    TestCase("旧或已取消的挂起保存必须在新快照之前串行结束") {
        let snapshotA = refreshSnapshot(hash: "a")
        let snapshotB = refreshSnapshot(hash: "b")
        let reader = CountingSnapshotReader(
            fingerprint: refreshFingerprint(hash: "requested"),
            snapshots: [snapshotA, snapshotB]
        )
        let store = ControlledSaveSnapshotStore()
        let coordinator = CommitGraphRefreshCoordinator(
            reader: reader,
            store: store
        )
        let repositoryURL = URL(filePath: "/repo")
        let first = Task {
            try await coordinator.refresh(
                repositoryID: 30,
                repositoryURL: repositoryURL
            )
        }
        await store.waitForSave(1)
        first.cancel()
        let second = Task {
            try await coordinator.refresh(
                repositoryID: 30,
                repositoryURL: repositoryURL
            )
        }
        await reader.waitForSnapshotCalls(2)
        for _ in 0..<100 {
            await Task.yield()
        }

        let savesBeforeOldCompletion = await store.startedSaveCount()
        if savesBeforeOldCompletion != 1 {
            await store.completeSave(1)
            await store.completeSave(2)
            _ = try? await first.value
            _ = try? await second.value
        }
        try expectEqual(
            savesBeforeOldCompletion,
            1,
            "旧保存未完成时新保存不得进入持久层"
        )
        await store.completeSave(1)
        await store.waitForSave(2)
        await store.completeSave(2)
        let secondResult = try await second.value
        do {
            _ = try await first.value
            throw TestFailure(description: "旧刷新必须按代次失效")
        } catch is CancellationError {
            // 预期路径。
        }

        let saved = await store.currentSnapshot(repositoryID: 30)
        try expectEqual(secondResult.snapshot, snapshotB, "新刷新必须完成")
        try expectEqual(saved, snapshotB, "旧保存恢复后不得覆盖新快照")
    },
    TestCase("未来版本缓存不阻断有效内存快照安装") {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "GitMateFutureRefresh-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let futureSchema = CommitGraphSnapshot.currentSchemaVersion + 7
        let originalData = try PropertyListEncoder().encode(
            FutureSnapshotVersionEnvelope(schemaVersion: futureSchema)
        )
        let targetURL = directory.appending(path: "31.plist")
        try originalData.write(to: targetURL)
        let fresh = refreshSnapshot(hash: "fresh-memory")
        let coordinator = CommitGraphRefreshCoordinator(
            reader: CountingSnapshotReader(
                fingerprint: fresh.fingerprint,
                snapshots: [fresh]
            ),
            store: BinaryCommitGraphSnapshotStore(rootDirectory: directory)
        )

        let result = try await coordinator.refresh(
            repositoryID: 31,
            repositoryURL: URL(filePath: "/repo")
        )
        let preservedData = try Data(contentsOf: targetURL)

        try expectEqual(result.snapshot, fresh, "有效扫描结果必须供页面安装")
        try expectEqual(
            preservedData,
            originalData,
            "跳过保存时未来版本字节必须保持不变"
        )
    },
    TestCase("非版本冲突的快照保存错误必须传播") {
        let fresh = refreshSnapshot(hash: "save-failure")
        let coordinator = CommitGraphRefreshCoordinator(
            reader: CountingSnapshotReader(
                fingerprint: fresh.fingerprint,
                snapshots: [fresh]
            ),
            store: FailingSaveSnapshotStore()
        )

        do {
            _ = try await coordinator.refresh(
                repositoryID: 32,
                repositoryURL: URL(filePath: "/repo")
            )
            throw TestFailure(description: "普通保存错误不得被吞掉")
        } catch let error as RefreshSaveTestError {
            try expectEqual(error, .unavailable, "必须原样传播非 schema 错误")
        }
    },
    TestCase("首屏缓存拒绝同一仓库编号下的旧路径快照") {
        let stale = refreshSnapshot(hash: "old-path", path: "/old/repo")
        let coordinator = CommitGraphRefreshCoordinator(
            reader: CountingSnapshotReader(
                fingerprint: stale.fingerprint,
                snapshots: [stale]
            ),
            store: InMemorySnapshotStore(snapshot: stale)
        )

        let cached = try await coordinator.cachedSnapshot(
            repositoryID: 1,
            repositoryURL: URL(filePath: "/new/repo")
        )

        try expectEqual(cached, nil, "仓库编号重绑后不得展示旧路径快照")
    },
    TestCase("扫描期间引用变化会丢弃旧候选并有界重试") {
        let first = refreshSnapshot(hash: "ref-a")
        let second = refreshSnapshot(hash: "ref-b")
        let reader = ChangingFingerprintSnapshotReader(
            fingerprints: [
                first.fingerprint,
                second.fingerprint,
                second.fingerprint
            ],
            snapshots: [first, second]
        )
        let store = InMemorySnapshotStore()
        let coordinator = CommitGraphRefreshCoordinator(
            reader: reader,
            store: store
        )

        let result = try await coordinator.refresh(
            repositoryID: 33,
            repositoryURL: URL(filePath: "/repo")
        )
        let suppliedFingerprints = await reader.snapshotFingerprints()
        let saved = await store.currentSnapshot(repositoryID: 33)

        try expectEqual(result.snapshot, second, "最终结果必须对应稳定后的引用")
        try expectEqual(
            suppliedFingerprints,
            [first.fingerprint, second.fingerprint],
            "引用变化后只允许一次有界重试"
        )
        try expectEqual(saved, second, "旧引用候选不得落盘")
    },
    TestCase("扫描期间引用连续变化会停止重试且不保存候选") {
        let first = refreshSnapshot(hash: "ref-a")
        let second = refreshSnapshot(hash: "ref-b")
        let third = refreshSnapshot(hash: "ref-c")
        let reader = ChangingFingerprintSnapshotReader(
            fingerprints: [
                first.fingerprint,
                second.fingerprint,
                third.fingerprint
            ],
            snapshots: [first, second]
        )
        let store = InMemorySnapshotStore()
        let coordinator = CommitGraphRefreshCoordinator(
            reader: reader,
            store: store
        )

        do {
            _ = try await coordinator.refresh(
                repositoryID: 34,
                repositoryURL: URL(filePath: "/repo")
            )
            throw TestFailure(description: "连续漂移不得安装不稳定候选")
        } catch let error as CommitGraphRefreshError {
            try expectEqual(
                error,
                .referencesChangedDuringScan,
                "第二次漂移必须返回稳定错误"
            )
        }
        let saveCount = await store.saveCount()
        let supplied = await reader.snapshotFingerprints()
        try expectEqual(saveCount, 0, "不稳定候选不得落盘")
        try expectEqual(
            supplied,
            [first.fingerprint, second.fingerprint],
            "引用漂移最多只允许重扫一次"
        )
    }
]

private struct FutureSnapshotVersionEnvelope: Codable {
    let schemaVersion: Int
}

private enum RefreshSaveTestError: Error, Equatable, Sendable {
    case unavailable
}

private actor FailingSaveSnapshotStore: CommitGraphSnapshotStoring {
    func load(repositoryID _: Int64) async throws -> CommitGraphSnapshot? {
        nil
    }

    func save(
        _ snapshot: CommitGraphSnapshot,
        repositoryID: Int64
    ) async throws {
        throw RefreshSaveTestError.unavailable
    }
}

private actor ChangingFingerprintSnapshotReader:
    CommitGraphSnapshotReading
{
    private var fingerprints: [CommitGraphReferenceFingerprint]
    private var snapshots: [CommitGraphSnapshot]
    private var supplied: [CommitGraphReferenceFingerprint] = []

    init(
        fingerprints: [CommitGraphReferenceFingerprint],
        snapshots: [CommitGraphSnapshot]
    ) {
        self.fingerprints = fingerprints
        self.snapshots = snapshots
    }

    func fingerprint(
        repositoryURL _: URL
    ) async throws -> CommitGraphReferenceFingerprint {
        guard !fingerprints.isEmpty else {
            throw TestFailure(description: "没有可返回的指纹")
        }
        return fingerprints.removeFirst()
    }

    func snapshot(
        repositoryURL _: URL,
        fingerprint: CommitGraphReferenceFingerprint
    ) async throws -> CommitGraphSnapshot {
        supplied.append(fingerprint)
        guard !snapshots.isEmpty else {
            throw TestFailure(description: "没有可返回的快照")
        }
        return snapshots.removeFirst()
    }

    func snapshotFingerprints() -> [CommitGraphReferenceFingerprint] {
        supplied
    }
}

private actor CountingSnapshotReader: CommitGraphSnapshotReading {
    private let currentFingerprint: CommitGraphReferenceFingerprint
    private var snapshots: [CommitGraphSnapshot]
    private var calls = 0
    private var callWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    init(
        fingerprint: CommitGraphReferenceFingerprint,
        snapshots: [CommitGraphSnapshot]
    ) {
        currentFingerprint = fingerprint
        self.snapshots = snapshots
    }

    func fingerprint(
        repositoryURL: URL
    ) async throws -> CommitGraphReferenceFingerprint {
        currentFingerprint
    }

    func snapshot(
        repositoryURL: URL,
        fingerprint: CommitGraphReferenceFingerprint
    ) async throws -> CommitGraphSnapshot {
        calls += 1
        if let waiters = callWaiters.removeValue(forKey: calls) {
            for waiter in waiters {
                waiter.resume()
            }
        }
        guard !snapshots.isEmpty else {
            throw TestFailure(description: "没有可返回的测试快照")
        }
        return snapshots.removeFirst()
    }

    func snapshotCallCount() -> Int {
        calls
    }

    func waitForSnapshotCalls(_ expectedCount: Int) async {
        guard calls < expectedCount else { return }
        await withCheckedContinuation { continuation in
            callWaiters[expectedCount, default: []].append(continuation)
        }
    }
}

private actor ControlledSnapshotReader: CommitGraphSnapshotReading {
    private var requestCount = 0
    private var requests: [Int: CheckedContinuation<CommitGraphSnapshot, Error>] = [:]
    private var requestWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func fingerprint(
        repositoryURL: URL
    ) async throws -> CommitGraphReferenceFingerprint {
        refreshFingerprint(hash: "requested")
    }

    func snapshot(
        repositoryURL: URL,
        fingerprint: CommitGraphReferenceFingerprint
    ) async throws -> CommitGraphSnapshot {
        requestCount += 1
        let requestID = requestCount
        if let waiters = requestWaiters.removeValue(forKey: requestID) {
            for waiter in waiters {
                waiter.resume()
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            requests[requestID] = continuation
        }
    }

    func waitForRequest(_ requestID: Int) async {
        guard requestCount < requestID else { return }
        await withCheckedContinuation { continuation in
            requestWaiters[requestID, default: []].append(continuation)
        }
    }

    func completeRequest(_ requestID: Int, snapshot: CommitGraphSnapshot) {
        requests.removeValue(forKey: requestID)?.resume(returning: snapshot)
    }
}

private actor InMemorySnapshotStore: CommitGraphSnapshotStoring {
    private var snapshotsByRepositoryID: [Int64: CommitGraphSnapshot] = [:]
    private var saves = 0

    init(snapshot: CommitGraphSnapshot? = nil) {
        if let snapshot {
            snapshotsByRepositoryID[1] = snapshot
            snapshotsByRepositoryID[2] = snapshot
        }
    }

    func load(repositoryID: Int64) async throws -> CommitGraphSnapshot? {
        snapshotsByRepositoryID[repositoryID]
    }

    func save(
        _ snapshot: CommitGraphSnapshot,
        repositoryID: Int64
    ) async throws {
        saves += 1
        snapshotsByRepositoryID[repositoryID] = snapshot
    }

    func currentSnapshot(repositoryID: Int64? = nil) -> CommitGraphSnapshot? {
        if let repositoryID {
            return snapshotsByRepositoryID[repositoryID]
        }
        return snapshotsByRepositoryID.values.first
    }

    func saveCount() -> Int {
        saves
    }
}

private actor ControlledSaveSnapshotStore: CommitGraphSnapshotStoring {
    private var snapshotsByRepositoryID: [Int64: CommitGraphSnapshot] = [:]
    private var startedSaves = 0
    private var saveContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var saveWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func load(repositoryID: Int64) async throws -> CommitGraphSnapshot? {
        snapshotsByRepositoryID[repositoryID]
    }

    func save(
        _ snapshot: CommitGraphSnapshot,
        repositoryID: Int64
    ) async throws {
        startedSaves += 1
        let saveID = startedSaves
        if let waiters = saveWaiters.removeValue(forKey: saveID) {
            for waiter in waiters {
                waiter.resume()
            }
        }
        await withCheckedContinuation { continuation in
            saveContinuations[saveID] = continuation
        }
        snapshotsByRepositoryID[repositoryID] = snapshot
    }

    func waitForSave(_ saveID: Int) async {
        guard startedSaves < saveID else { return }
        await withCheckedContinuation { continuation in
            saveWaiters[saveID, default: []].append(continuation)
        }
    }

    func completeSave(_ saveID: Int) {
        saveContinuations.removeValue(forKey: saveID)?.resume()
    }

    func startedSaveCount() -> Int {
        startedSaves
    }

    func currentSnapshot(repositoryID: Int64) -> CommitGraphSnapshot? {
        snapshotsByRepositoryID[repositoryID]
    }
}

private func refreshFingerprint(
    hash: String
) -> CommitGraphReferenceFingerprint {
    CommitGraphReferenceFingerprint(
        references: [
            CommitGraphReference(
                name: "refs/heads/main",
                targetHash: hash,
                kind: .localBranch
            )
        ],
        headName: "main",
        headHash: hash,
        isShallow: false
    )
}

private func refreshSnapshot(
    hash: String,
    path: String = "/repo"
) -> CommitGraphSnapshot {
    CommitGraphSnapshot(
        repositoryPath: path,
        fingerprint: refreshFingerprint(hash: hash),
        commitsNewestFirst: [
            refreshCommit(hash: hash, parents: [])
        ],
        expectedCommitCount: 1,
        shallowBoundaryParentHashes: [],
        generatedAt: Date(timeIntervalSince1970: 10)
    )
}

private func refreshInvalidSnapshot(hash: String) -> CommitGraphSnapshot {
    CommitGraphSnapshot(
        repositoryPath: "/repo",
        fingerprint: refreshFingerprint(hash: hash),
        commitsNewestFirst: [
            refreshCommit(hash: hash, parents: ["missing"])
        ],
        expectedCommitCount: 1,
        shallowBoundaryParentHashes: [],
        generatedAt: Date(timeIntervalSince1970: 10)
    )
}

private func refreshCommit(hash: String, parents: [String]) -> GitCommit {
    GitCommit(
        shortHash: hash,
        fullHash: hash,
        subject: "提交 \(hash)",
        authorName: "测试用户",
        authorEmail: "test@example.com",
        authoredAt: Date(timeIntervalSince1970: 1),
        parentHashes: parents,
        decorations: []
    )
}
