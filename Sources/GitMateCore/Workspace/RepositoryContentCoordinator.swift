import Foundation

public struct RepositoryContentCacheKey: Hashable, Sendable {
    public let accountID: String
    public let repositoryID: Int64

    public init(accountID: String, repositoryID: Int64) {
        self.accountID = accountID
        self.repositoryID = repositoryID
    }
}

public enum RepositoryContentFreshness: Equatable, Sendable {
    case cached
    case refreshed
}

public struct RepositoryContentUpdate: Equatable, Sendable {
    public let content: RepositoryContent
    public let freshness: RepositoryContentFreshness
    public let isFinal: Bool

    public init(
        content: RepositoryContent,
        freshness: RepositoryContentFreshness,
        isFinal: Bool
    ) {
        self.content = content
        self.freshness = freshness
        self.isFinal = isFinal
    }
}

public actor RepositoryContentCoordinator {
    private static let cacheTimeToLive: TimeInterval = 300
    private let now: @Sendable () -> Date
    private var entries: [
        RepositoryContentCacheKey: (
            content: RepositoryContent,
            storedAt: Date
        )
    ] = [:]
    private var inFlight: [
        RepositoryContentCacheKey: Task<RepositoryContent, Error>
    ] = [:]
    private var inFlightIDs: [RepositoryContentCacheKey: UUID] = [:]
    private var waiters: [
        RepositoryContentCacheKey: [
            UUID: CheckedContinuation<RepositoryContent, Error>
        ]
    ] = [:]

    public init(
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.now = now
    }

    public func cachedUpdate(
        for key: RepositoryContentCacheKey
    ) -> RepositoryContentUpdate? {
        guard let entry = entries[key] else {
            return nil
        }
        let age = now().timeIntervalSince(entry.storedAt)
        let isFresh = (0...Self.cacheTimeToLive).contains(age)
        return RepositoryContentUpdate(
            content: entry.content,
            freshness: .cached,
            isFinal: isFresh
        )
    }

    public func refresh(
        for key: RepositoryContentCacheKey,
        operation: @escaping @Sendable () async throws -> RepositoryContent
    ) async throws -> RepositoryContent {
        try Task.checkCancellation()
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(
                    continuation,
                    waiterID: waiterID,
                    key: key,
                    operation: operation
                )
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(waiterID, for: key)
            }
        }
    }

    private func register(
        _ continuation: CheckedContinuation<RepositoryContent, Error>,
        waiterID: UUID,
        key: RepositoryContentCacheKey,
        operation: @escaping @Sendable () async throws -> RepositoryContent
    ) {
        guard !Task.isCancelled else {
            continuation.resume(throwing: CancellationError())
            return
        }

        waiters[key, default: [:]][waiterID] = continuation
        guard inFlight[key] == nil else {
            return
        }

        let refreshID = UUID()
        let task = Task {
            try await operation()
        }
        inFlight[key] = task
        inFlightIDs[key] = refreshID

        Task {
            let result = await task.result
            complete(result, for: key, refreshID: refreshID)
        }
    }

    private func complete(
        _ result: Result<RepositoryContent, Error>,
        for key: RepositoryContentCacheKey,
        refreshID: UUID
    ) {
        guard inFlightIDs[key] == refreshID else {
            return
        }

        inFlight[key] = nil
        inFlightIDs[key] = nil
        let continuations = waiters.removeValue(forKey: key).map {
            Array($0.values)
        } ?? []

        switch result {
        case let .success(content):
            entries[key] = (content: content, storedAt: now())
            continuations.forEach { $0.resume(returning: content) }
        case let .failure(error):
            continuations.forEach { $0.resume(throwing: error) }
        }
    }

    private func cancelWaiter(
        _ waiterID: UUID,
        for key: RepositoryContentCacheKey
    ) {
        guard let continuation = waiters[key]?.removeValue(forKey: waiterID) else {
            return
        }
        continuation.resume(throwing: CancellationError())

        guard waiters[key]?.isEmpty == true else {
            return
        }
        waiters[key] = nil
        inFlight[key]?.cancel()
        inFlight[key] = nil
        inFlightIDs[key] = nil
    }
}
