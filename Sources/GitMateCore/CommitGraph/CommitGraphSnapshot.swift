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
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let generationID: UUID
    public let repositoryPath: String
    public let fingerprint: CommitGraphReferenceFingerprint
    public let commitsNewestFirst: [GitCommit]
    public let expectedCommitCount: Int
    public let shallowBoundaryParentHashes: Set<String>
    public let generatedAt: Date

    public init(
        schemaVersion: Int = currentSchemaVersion,
        generationID: UUID = UUID(),
        repositoryPath: String,
        fingerprint: CommitGraphReferenceFingerprint,
        commitsNewestFirst: [GitCommit],
        expectedCommitCount: Int,
        shallowBoundaryParentHashes: Set<String>,
        generatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.generationID = generationID
        self.repositoryPath = repositoryPath
        self.fingerprint = fingerprint
        self.commitsNewestFirst = commitsNewestFirst
        self.expectedCommitCount = expectedCommitCount
        self.shallowBoundaryParentHashes = shallowBoundaryParentHashes
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generationID
        case repositoryPath
        case fingerprint
        case commitsNewestFirst
        case expectedCommitCount
        case shallowBoundaryParentHashes
        case generatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedSchemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? 1
        repositoryPath = try container.decode(
            String.self,
            forKey: .repositoryPath
        )
        fingerprint = try container.decode(
            CommitGraphReferenceFingerprint.self,
            forKey: .fingerprint
        )
        commitsNewestFirst = try container.decode(
            [GitCommit].self,
            forKey: .commitsNewestFirst
        )
        expectedCommitCount = try container.decode(
            Int.self,
            forKey: .expectedCommitCount
        )
        shallowBoundaryParentHashes = try container.decode(
            Set<String>.self,
            forKey: .shallowBoundaryParentHashes
        )
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)

        if storedSchemaVersion <= 1 {
            schemaVersion = Self.currentSchemaVersion
            generationID = try container.decodeIfPresent(
                UUID.self,
                forKey: .generationID
            ) ?? Self.legacyGenerationID(
                repositoryPath: repositoryPath,
                fingerprint: fingerprint,
                commits: commitsNewestFirst,
                expectedCommitCount: expectedCommitCount,
                generatedAt: generatedAt
            )
        } else {
            schemaVersion = storedSchemaVersion
            generationID = try container.decode(
                UUID.self,
                forKey: .generationID
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(generationID, forKey: .generationID)
        try container.encode(repositoryPath, forKey: .repositoryPath)
        try container.encode(fingerprint, forKey: .fingerprint)
        try container.encode(commitsNewestFirst, forKey: .commitsNewestFirst)
        try container.encode(expectedCommitCount, forKey: .expectedCommitCount)
        try container.encode(
            shallowBoundaryParentHashes,
            forKey: .shallowBoundaryParentHashes
        )
        try container.encode(generatedAt, forKey: .generatedAt)
    }

    private static func legacyGenerationID(
        repositoryPath: String,
        fingerprint: CommitGraphReferenceFingerprint,
        commits: [GitCommit],
        expectedCommitCount: Int,
        generatedAt: Date
    ) -> UUID {
        var first = StableFNV64(seed: 0xcbf29ce484222325)
        var second = StableFNV64(seed: 0x84222325cbf29ce4)
        func add(_ value: String) {
            first.add(value)
            second.add(value)
        }
        add(repositoryPath)
        add(String(expectedCommitCount))
        add(String(generatedAt.timeIntervalSinceReferenceDate.bitPattern))
        add(fingerprint.headName ?? "")
        add(fingerprint.headHash ?? "")
        add(fingerprint.isShallow ? "1" : "0")
        for reference in fingerprint.references.sorted(by: {
            ($0.name, $0.targetHash, $0.kind.rawValue)
                < ($1.name, $1.targetHash, $1.kind.rawValue)
        }) {
            add(reference.name)
            add(reference.targetHash)
            add(reference.kind.rawValue)
        }
        for commit in commits {
            add(commit.fullHash)
            for parentHash in commit.parentHashes { add(parentHash) }
        }
        var bytes = first.bytes + second.bytes
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private struct StableFNV64 {
    private var value: UInt64

    init(seed: UInt64) {
        value = seed
    }

    mutating func add(_ string: String) {
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value &*= 0x100000001b3
        }
        value ^= 0xFF
        value &*= 0x100000001b3
    }

    var bytes: [UInt8] {
        (0..<8).map { shift in
            UInt8(truncatingIfNeeded: value >> UInt64(shift * 8))
        }
    }
}

/// ViewModel 用于判断某一代快照是否已经安装的轻量身份。
///
/// `generationID` 在一次完整快照生成后会随快照持久化，因此既能区分
/// 不同生成代次，也不会像 `CommitGraphSnapshot.==` 一样遍历全部提交。
/// 内容完整性仍由 `CommitGraphIntegrityValidator` 独立负责。
public struct CommitGraphSnapshotIdentity: Equatable, Sendable {
    public let schemaVersion: Int
    public let repositoryPath: String
    public let generationID: UUID

    public init(_ snapshot: CommitGraphSnapshot) {
        schemaVersion = snapshot.schemaVersion
        repositoryPath = snapshot.repositoryPath
        generationID = snapshot.generationID
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
