import Foundation

public enum CommitGraphReferenceKind: String, Codable, Sendable {
    case localBranch
    case remoteBranch
}

public struct CommitGraphReference: Codable, Equatable, Sendable {
    public let name: String
    public let targetHash: String
    public let kind: CommitGraphReferenceKind

    public init(name: String, targetHash: String, kind: CommitGraphReferenceKind) {
        self.name = name
        self.targetHash = targetHash
        self.kind = kind
    }
}

public struct CommitGraphReferenceFingerprint: Codable, Equatable, Sendable {
    public let references: [CommitGraphReference]
    public let headName: String?
    public let headHash: String?
    public let isShallow: Bool

    public init(
        references: [CommitGraphReference],
        headName: String?,
        headHash: String?,
        isShallow: Bool
    ) {
        self.references = references
        self.headName = headName
        self.headHash = headHash
        self.isShallow = isShallow
    }
}

public struct CommitGraphSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let repositoryPath: String
    public let fingerprint: CommitGraphReferenceFingerprint
    public let commitsNewestFirst: [GitCommit]
    public let expectedCommitCount: Int
    public let shallowBoundaryParentHashes: Set<String>
    public let generatedAt: Date

    public init(
        schemaVersion: Int = currentSchemaVersion,
        repositoryPath: String,
        fingerprint: CommitGraphReferenceFingerprint,
        commitsNewestFirst: [GitCommit],
        expectedCommitCount: Int,
        shallowBoundaryParentHashes: Set<String>,
        generatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.repositoryPath = repositoryPath
        self.fingerprint = fingerprint
        self.commitsNewestFirst = commitsNewestFirst
        self.expectedCommitCount = expectedCommitCount
        self.shallowBoundaryParentHashes = shallowBoundaryParentHashes
        self.generatedAt = generatedAt
    }
}

public enum CommitGraphIntegrityStatus: String, Codable, Sendable {
    case valid
    case warning
    case invalid
}

public struct CommitGraphIntegrityReport: Codable, Equatable, Sendable {
    public let status: CommitGraphIntegrityStatus
    public let expectedCommitCount: Int
    public let actualCommitCount: Int
    public let expectedRelationshipCount: Int
    public let actualRelationshipCount: Int
    public let duplicateCommitHashes: [String]
    public let duplicateEdgeIDs: [String]
    public let missingParentHashes: [String]
    public let missingReferenceTargets: [String]
    public let shallowBoundaryParentHashes: [String]
    public let checkedAt: Date

    public init(
        status: CommitGraphIntegrityStatus,
        expectedCommitCount: Int,
        actualCommitCount: Int,
        expectedRelationshipCount: Int,
        actualRelationshipCount: Int,
        duplicateCommitHashes: [String],
        duplicateEdgeIDs: [String],
        missingParentHashes: [String],
        missingReferenceTargets: [String],
        shallowBoundaryParentHashes: [String],
        checkedAt: Date
    ) {
        self.status = status
        self.expectedCommitCount = expectedCommitCount
        self.actualCommitCount = actualCommitCount
        self.expectedRelationshipCount = expectedRelationshipCount
        self.actualRelationshipCount = actualRelationshipCount
        self.duplicateCommitHashes = duplicateCommitHashes
        self.duplicateEdgeIDs = duplicateEdgeIDs
        self.missingParentHashes = missingParentHashes
        self.missingReferenceTargets = missingReferenceTargets
        self.shallowBoundaryParentHashes = shallowBoundaryParentHashes
        self.checkedAt = checkedAt
    }
}
