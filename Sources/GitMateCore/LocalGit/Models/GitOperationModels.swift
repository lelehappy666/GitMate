import Foundation

public enum GitOperationKind: String, Codable, Equatable, Sendable {
    case stage
    case unstage
    case commit
    case stash
    case historyRewrite
    case conflictResolution
    case remoteConfiguration
    case fetch
    case pull
    case push
}

public enum GitOperationResult: String, Codable, Equatable, Sendable {
    case running
    case succeeded
    case conflicted
    case failed
    case cancelled
}

public struct RiskConfirmation: Equatable, Sendable {
    public let operationID: UUID
    public let repositoryID: String
    public let impactFingerprint: String
    public let createdAt: Date

    public init(
        operationID: UUID = UUID(),
        repositoryID: String,
        impactFingerprint: String,
        createdAt: Date = Date()
    ) {
        self.operationID = operationID
        self.repositoryID = repositoryID
        self.impactFingerprint = impactFingerprint
        self.createdAt = createdAt
    }
}

public struct GitOperationJournalEntry: Codable, Equatable, Sendable {
    public let repositoryID: String
    public let kind: GitOperationKind
    public let startedAt: Date
    public let finishedAt: Date?
    public let phase: String
    public let result: GitOperationResult

    public init(
        repositoryID: String,
        kind: GitOperationKind,
        startedAt: Date,
        finishedAt: Date?,
        phase: String,
        result: GitOperationResult
    ) {
        self.repositoryID = repositoryID
        self.kind = kind
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.phase = phase
        self.result = result
    }

    func redacted() -> GitOperationJournalEntry {
        GitOperationJournalEntry(
            repositoryID: repositoryID,
            kind: kind,
            startedAt: startedAt,
            finishedAt: finishedAt,
            phase: GitOutputRedactor.redact(phase),
            result: result
        )
    }
}
