import Foundation

public struct CommitGraphRefreshResult: Equatable, Sendable {
    public let snapshot: CommitGraphSnapshot
    public let integrity: CommitGraphIntegrityReport
    public let didChange: Bool
    public let usedCache: Bool
    public let refreshedAt: Date

    public init(
        snapshot: CommitGraphSnapshot,
        integrity: CommitGraphIntegrityReport,
        didChange: Bool,
        usedCache: Bool,
        refreshedAt: Date
    ) {
        self.snapshot = snapshot
        self.integrity = integrity
        self.didChange = didChange
        self.usedCache = usedCache
        self.refreshedAt = refreshedAt
    }
}

public enum CommitGraphRefreshError: Error, Equatable, Sendable {
    case invalidSnapshot(CommitGraphIntegrityReport)
}

public actor CommitGraphRefreshCoordinator {
    private struct PreparedRefresh: Sendable {
        let result: CommitGraphRefreshResult
        let requiresSave: Bool
    }

    private struct ActiveRefresh {
        let requestID: UInt64
        let task: Task<PreparedRefresh, Error>
    }

    private struct ActiveSave {
        let requestID: UInt64
        let task: Task<Void, Error>
    }

    private let reader: any CommitGraphSnapshotReading
    private let store: any CommitGraphSnapshotStoring
    private var latestRequestIDByRepository: [Int64: UInt64] = [:]
    private var activeRefreshByRepository: [Int64: ActiveRefresh] = [:]
    private var activeSaveByRepository: [Int64: ActiveSave] = [:]

    public init(
        reader: any CommitGraphSnapshotReading,
        store: any CommitGraphSnapshotStoring
    ) {
        self.reader = reader
        self.store = store
    }

    public func cachedSnapshot(
        repositoryID: Int64
    ) async -> CommitGraphSnapshot? {
        try? await store.load(repositoryID: repositoryID)
    }

    public func refresh(
        repositoryID: Int64,
        repositoryURL: URL
    ) async throws -> CommitGraphRefreshResult {
        let requestID = (latestRequestIDByRepository[repositoryID] ?? 0) + 1
        latestRequestIDByRepository[repositoryID] = requestID
        activeRefreshByRepository[repositoryID]?.task.cancel()

        let reader = self.reader
        let store = self.store
        let task = Task<PreparedRefresh, Error> {
            try await Self.performRefresh(
                repositoryID: repositoryID,
                repositoryURL: repositoryURL,
                reader: reader,
                store: store
            )
        }
        activeRefreshByRepository[repositoryID] = ActiveRefresh(
            requestID: requestID,
            task: task
        )

        do {
            let prepared = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard isCurrentRequest(
                repositoryID: repositoryID,
                requestID: requestID
            ) else {
                throw CancellationError()
            }
            if prepared.requiresSave {
                try await commit(
                    prepared.result.snapshot,
                    repositoryID: repositoryID,
                    requestID: requestID
                )
            }
            guard isCurrentRequest(
                repositoryID: repositoryID,
                requestID: requestID
            ) else {
                throw CancellationError()
            }
            activeRefreshByRepository.removeValue(forKey: repositoryID)
            return prepared.result
        } catch {
            if isCurrentRequest(
                repositoryID: repositoryID,
                requestID: requestID
            ) {
                activeRefreshByRepository.removeValue(forKey: repositoryID)
            }
            throw error
        }
    }

    private func isCurrentRequest(
        repositoryID: Int64,
        requestID: UInt64
    ) -> Bool {
        latestRequestIDByRepository[repositoryID] == requestID
            && activeRefreshByRepository[repositoryID]?.requestID == requestID
    }

    private func commit(
        _ snapshot: CommitGraphSnapshot,
        repositoryID: Int64,
        requestID: UInt64
    ) async throws {
        try Task.checkCancellation()
        guard isCurrentRequest(
            repositoryID: repositoryID,
            requestID: requestID
        ) else {
            throw CancellationError()
        }

        while let previousSave = activeSaveByRepository[repositoryID] {
            // 保存一旦进入持久层就视为原子提交点，不取消进行中的保存。
            // 新代次可以并行扫描，但必须排在旧保存之后，避免 actor
            // 重入使旧快照最后落盘并覆盖新快照。
            _ = try? await previousSave.task.value
            if activeSaveByRepository[repositoryID]?.requestID
                == previousSave.requestID {
                activeSaveByRepository.removeValue(forKey: repositoryID)
            }
            try Task.checkCancellation()
            guard isCurrentRequest(
                repositoryID: repositoryID,
                requestID: requestID
            ) else {
                throw CancellationError()
            }
        }

        let store = self.store
        // 该任务故意不加入调用方取消处理；开始保存前已完成取消与
        // requestID 门禁，开始后由仓库级保存车道保证代次提交顺序。
        let saveTask = Task<Void, Error> {
            try await store.save(snapshot, repositoryID: repositoryID)
        }
        activeSaveByRepository[repositoryID] = ActiveSave(
            requestID: requestID,
            task: saveTask
        )

        do {
            try await saveTask.value
        } catch {
            if activeSaveByRepository[repositoryID]?.requestID == requestID {
                activeSaveByRepository.removeValue(forKey: repositoryID)
            }
            throw error
        }
        if activeSaveByRepository[repositoryID]?.requestID == requestID {
            activeSaveByRepository.removeValue(forKey: repositoryID)
        }
        guard isCurrentRequest(
            repositoryID: repositoryID,
            requestID: requestID
        ) else {
            throw CancellationError()
        }
    }

    private nonisolated static func performRefresh(
        repositoryID: Int64,
        repositoryURL: URL,
        reader: any CommitGraphSnapshotReading,
        store: any CommitGraphSnapshotStoring
    ) async throws -> PreparedRefresh {
        let cached = try await loadUsableCache(
            repositoryID: repositoryID,
            repositoryURL: repositoryURL,
            store: store
        )
        try Task.checkCancellation()
        let fingerprint = try await reader.fingerprint(
            repositoryURL: repositoryURL
        )
        try Task.checkCancellation()

        if let cached,
           cached.fingerprint == fingerprint {
            let report = CommitGraphIntegrityValidator.validate(cached)
            if report.status != .invalid {
                return PreparedRefresh(
                    result: CommitGraphRefreshResult(
                        snapshot: cached,
                        integrity: report,
                        didChange: false,
                        usedCache: true,
                        refreshedAt: Date()
                    ),
                    requiresSave: false
                )
            }
        }

        var candidate = try await reader.snapshot(
            repositoryURL: repositoryURL,
            fingerprint: fingerprint
        )
        try Task.checkCancellation()
        var report = CommitGraphIntegrityValidator.validate(candidate)
        if report.status == .invalid {
            candidate = try await reader.snapshot(
                repositoryURL: repositoryURL,
                fingerprint: fingerprint
            )
            try Task.checkCancellation()
            report = CommitGraphIntegrityValidator.validate(candidate)
        }
        guard report.status != .invalid else {
            throw CommitGraphRefreshError.invalidSnapshot(report)
        }

        try Task.checkCancellation()
        return PreparedRefresh(
            result: CommitGraphRefreshResult(
                snapshot: candidate,
                integrity: report,
                didChange: cached != candidate,
                usedCache: false,
                refreshedAt: Date()
            ),
            requiresSave: true
        )
    }

    private nonisolated static func loadUsableCache(
        repositoryID: Int64,
        repositoryURL: URL,
        store: any CommitGraphSnapshotStoring
    ) async throws -> CommitGraphSnapshot? {
        do {
            guard let snapshot = try await store.load(
                repositoryID: repositoryID
            ) else {
                return nil
            }
            guard snapshot.repositoryPath == repositoryURL.standardizedFileURL.path
            else {
                return nil
            }
            return snapshot
        } catch is CommitGraphSnapshotStoreError {
            return nil
        }
    }
}
