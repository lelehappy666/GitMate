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
    private struct ActiveRefresh {
        let requestID: UInt64
        let task: Task<CommitGraphRefreshResult, Error>
    }

    private let reader: any CommitGraphSnapshotReading
    private let store: any CommitGraphSnapshotStoring
    private var latestRequestIDByRepository: [Int64: UInt64] = [:]
    private var activeRefreshByRepository: [Int64: ActiveRefresh] = [:]

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
        let task = Task<CommitGraphRefreshResult, Error> {
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
            let result = try await withTaskCancellationHandler {
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
            activeRefreshByRepository.removeValue(forKey: repositoryID)
            return result
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

    private nonisolated static func performRefresh(
        repositoryID: Int64,
        repositoryURL: URL,
        reader: any CommitGraphSnapshotReading,
        store: any CommitGraphSnapshotStoring
    ) async throws -> CommitGraphRefreshResult {
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
                return CommitGraphRefreshResult(
                    snapshot: cached,
                    integrity: report,
                    didChange: false,
                    usedCache: true,
                    refreshedAt: Date()
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
        try await store.save(candidate, repositoryID: repositoryID)
        try Task.checkCancellation()
        return CommitGraphRefreshResult(
            snapshot: candidate,
            integrity: report,
            didChange: cached != candidate,
            usedCache: false,
            refreshedAt: Date()
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
