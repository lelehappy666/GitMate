import Foundation

public enum CommitGraphBranchSource:
    String,
    Codable,
    Equatable,
    Sendable
{
    case local
    case remote
    case detached
    case synthetic
}

public enum CommitGraphBranchSide:
    Int,
    Codable,
    Equatable,
    Sendable
{
    case left = -1
    case trunk = 0
    case right = 1
}

public struct CommitGraphBranchDescriptor:
    Identifiable,
    Equatable,
    Sendable
{
    public let id: String
    public let displayName: String
    public let source: CommitGraphBranchSource
    public let side: CommitGraphBranchSide
    public let lane: Int
    public let tipHash: String
    public let latestActivity: Date
    public let memberHashes: Set<String>
    public let isHead: Bool
    public let isMerged: Bool

    public init(
        id: String,
        displayName: String,
        source: CommitGraphBranchSource,
        side: CommitGraphBranchSide,
        lane: Int,
        tipHash: String,
        latestActivity: Date,
        memberHashes: Set<String>,
        isHead: Bool,
        isMerged: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.source = source
        self.side = side
        self.lane = max(lane, 0)
        self.tipHash = tipHash
        self.latestActivity = latestActivity
        self.memberHashes = memberHashes
        self.isHead = isHead
        self.isMerged = isMerged
    }
}

public struct CommitGraphBranchCatalog: Equatable, Sendable {
    public let branches: [CommitGraphBranchDescriptor]
    public let headBranchID: String?
    public let directReferenceCount: Int

    private let branchIndexByID: [String: Int]
    private let primaryBranchIDByHash: [String: String]
    private let relatedBranchIDsByBranchID: [String: Set<String>]

    public init(
        branches: [CommitGraphBranchDescriptor],
        headBranchID: String?,
        primaryBranchIDByHash: [String: String],
        directReferenceCount: Int? = nil,
        relatedBranchIDsByBranchID: [String: Set<String>] = [:]
    ) {
        self.branches = branches
        self.headBranchID = headBranchID
        self.directReferenceCount = max(
            directReferenceCount ?? branches.filter {
                $0.source == .local || $0.source == .remote
            }.count,
            0
        )
        self.primaryBranchIDByHash = primaryBranchIDByHash
        self.relatedBranchIDsByBranchID = relatedBranchIDsByBranchID
        branchIndexByID = Dictionary(
            branches.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func branch(id: String) -> CommitGraphBranchDescriptor? {
        guard let index = branchIndexByID[id] else { return nil }
        return branches[index]
    }

    public func branch(containing hash: String) -> CommitGraphBranchDescriptor? {
        guard let id = primaryBranchIDByHash[hash] else { return nil }
        return branch(id: id)
    }

    public func relatedBranchIDs(to branchID: String) -> Set<String> {
        relatedBranchIDsByBranchID[branchID] ?? []
    }

    public static func build(
        topology: CommitGraphLaneTopology,
        fingerprint: CommitGraphReferenceFingerprint
    ) -> CommitGraphBranchCatalog {
        let rows = topology.rowsNewestFirst
        guard !rows.isEmpty else {
            return CommitGraphBranchCatalog(
                branches: [],
                headBranchID: nil,
                primaryBranchIDByHash: [:],
                directReferenceCount: 0,
                relatedBranchIDsByBranchID: [:]
            )
        }

        let rowsByHash = Dictionary(
            rows.map { ($0.commit.fullHash, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let headReferenceName = normalizedHeadReferenceName(fingerprint.headName)
        let knownAncestors = ancestors(
            from: fingerprint.headHash,
            rowsByHash: rowsByHash
        )

        var drafts: [BranchDraft] = []
        var draftIDs = Set<String>()
        let directReferences = fingerprint.references.filter {
            $0.symbolicTarget == nil
        }
        for reference in directReferences.sorted(by: { $0.name < $1.name }) {
            guard let row = rowsByHash[reference.targetHash] else { continue }
            let source: CommitGraphBranchSource = reference.kind == .localBranch
                ? .local
                : .remote
            let name = readableReferenceName(reference.name)
            let id = "\(source.rawValue):\(name)"
            guard draftIDs.insert(id).inserted else { continue }
            let isHead = reference.name == headReferenceName
                || (reference.kind == .localBranch
                    && name == fingerprint.headName
                    && reference.targetHash == fingerprint.headHash)
            drafts.append(
                BranchDraft(
                    id: id,
                    displayName: name,
                    source: source,
                    tipHash: reference.targetHash,
                    latestActivity: row.commit.authoredAt,
                    isHead: isHead,
                    isMerged: !isHead
                        && knownAncestors.contains(reference.targetHash)
                )
            )
        }

        var headBranchID = drafts.first(where: \.isHead)?.id
        if headBranchID == nil,
           let headHash = fingerprint.headHash,
           let headRow = rowsByHash[headHash] {
            let id = "detached:HEAD"
            drafts.append(
                BranchDraft(
                    id: id,
                    displayName: "Detached HEAD",
                    source: .detached,
                    tipHash: headHash,
                    latestActivity: headRow.commit.authoredAt,
                    isHead: true,
                    isMerged: false
                )
            )
            draftIDs.insert(id)
            headBranchID = id
        }

        drafts.sort(by: draftOrdering)
        var primaryByHash: [String: String] = [:]
        for draft in drafts {
            var current: String? = draft.tipHash
            while let hash = current,
                  primaryByHash[hash] == nil,
                  let row = rowsByHash[hash] {
                primaryByHash[hash] = draft.id
                current = row.commit.parentHashes.first
            }
        }

        let unassignedHashes = Set(rows.map(\.commit.fullHash))
            .subtracting(primaryByHash.keys)
        for component in unassignedComponents(
            hashes: unassignedHashes,
            rows: rows
        ) {
            guard let tip = rows.first(where: {
                component.contains($0.commit.fullHash)
            }) else { continue }
            let id = "synthetic:\(tip.commit.fullHash)"
            drafts.append(
                BranchDraft(
                    id: id,
                    displayName: "未命名分支",
                    source: .synthetic,
                    tipHash: tip.commit.fullHash,
                    latestActivity: component.compactMap {
                        rowsByHash[$0]?.commit.authoredAt
                    }.max() ?? tip.commit.authoredAt,
                    isHead: headBranchID == nil,
                    isMerged: false
                )
            )
            if headBranchID == nil {
                headBranchID = id
            }
            for hash in component {
                primaryByHash[hash] = id
            }
        }

        drafts.sort(by: draftOrdering)
        var membersByBranchID: [String: Set<String>] = [:]
        for (hash, branchID) in primaryByHash {
            membersByBranchID[branchID, default: []].insert(hash)
        }
        var logicalLane = 1
        var descriptors: [CommitGraphBranchDescriptor] = []
        descriptors.reserveCapacity(drafts.count)
        for draft in drafts {
            let isHead = draft.id == headBranchID
            let lane = isHead ? 0 : logicalLane
            if !isHead { logicalLane += 1 }
            descriptors.append(
                CommitGraphBranchDescriptor(
                    id: draft.id,
                    displayName: draft.displayName,
                    source: draft.source,
                    side: isHead ? .trunk : stableSide(for: draft.id),
                    lane: lane,
                    tipHash: draft.tipHash,
                    latestActivity: draft.latestActivity,
                    memberHashes: membersByBranchID[draft.id] ?? [],
                    isHead: isHead,
                    isMerged: draft.isMerged
                )
            )
        }
        descriptors.sort(by: branchOrdering)

        var related: [String: Set<String>] = [:]
        for row in rows {
            guard let sourceID = primaryByHash[row.commit.fullHash] else {
                continue
            }
            for connection in row.connections {
                guard let targetID = primaryByHash[connection.parentHash],
                      targetID != sourceID
                else { continue }
                related[sourceID, default: []].insert(targetID)
                related[targetID, default: []].insert(sourceID)
            }
        }
        return CommitGraphBranchCatalog(
            branches: descriptors,
            headBranchID: headBranchID,
            primaryBranchIDByHash: primaryByHash,
            directReferenceCount: directReferences.count,
            relatedBranchIDsByBranchID: related
        )
    }

    private struct BranchDraft {
        let id: String
        let displayName: String
        let source: CommitGraphBranchSource
        let tipHash: String
        let latestActivity: Date
        let isHead: Bool
        let isMerged: Bool
    }

    private static func draftOrdering(
        _ first: BranchDraft,
        _ second: BranchDraft
    ) -> Bool {
        if first.isHead != second.isHead { return first.isHead }
        let sourceOrder: [CommitGraphBranchSource: Int] = [
            .local: 0,
            .remote: 1,
            .detached: 2,
            .synthetic: 3
        ]
        if sourceOrder[first.source] != sourceOrder[second.source] {
            return sourceOrder[first.source, default: 4]
                < sourceOrder[second.source, default: 4]
        }
        if first.latestActivity != second.latestActivity {
            return first.latestActivity > second.latestActivity
        }
        return first.id < second.id
    }

    private static func unassignedComponents(
        hashes: Set<String>,
        rows: [CommitGraphLaneRow]
    ) -> [Set<String>] {
        guard !hashes.isEmpty else { return [] }
        var adjacency: [String: Set<String>] = [:]
        for row in rows where hashes.contains(row.commit.fullHash) {
            for parent in row.commit.parentHashes where hashes.contains(parent) {
                adjacency[row.commit.fullHash, default: []].insert(parent)
                adjacency[parent, default: []].insert(row.commit.fullHash)
            }
        }
        var remaining = hashes
        var result: [Set<String>] = []
        for row in rows {
            let start = row.commit.fullHash
            guard remaining.contains(start) else { continue }
            var component = Set<String>()
            var stack = [start]
            while let hash = stack.popLast(),
                  component.insert(hash).inserted {
                remaining.remove(hash)
                stack.append(contentsOf: adjacency[hash] ?? [])
            }
            result.append(component)
        }
        return result.sorted {
            ($0.sorted().first ?? "") < ($1.sorted().first ?? "")
        }
    }

    private static func stableSide(
        for identity: String
    ) -> CommitGraphBranchSide {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in identity.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash.isMultiple(of: 2) ? .right : .left
    }

    private static func normalizedHeadReferenceName(_ headName: String?) -> String? {
        guard let headName, !headName.isEmpty else { return nil }
        return headName.hasPrefix("refs/") ? headName : "refs/heads/\(headName)"
    }

    private static func readableReferenceName(_ name: String) -> String {
        if name.hasPrefix("refs/heads/") {
            return String(name.dropFirst("refs/heads/".count))
        }
        if name.hasPrefix("refs/remotes/") {
            return String(name.dropFirst("refs/remotes/".count))
        }
        return name
    }

    private static func branchOrdering(
        _ first: CommitGraphBranchDescriptor,
        _ second: CommitGraphBranchDescriptor
    ) -> Bool {
        if first.isHead != second.isHead { return first.isHead }
        if first.side.rawValue != second.side.rawValue {
            return first.side.rawValue < second.side.rawValue
        }
        let sourceOrder: [CommitGraphBranchSource: Int] = [
            .local: 0,
            .remote: 1,
            .detached: 2,
            .synthetic: 3
        ]
        if sourceOrder[first.source] != sourceOrder[second.source] {
            return sourceOrder[first.source, default: 4]
                < sourceOrder[second.source, default: 4]
        }
        if first.latestActivity != second.latestActivity {
            return first.latestActivity > second.latestActivity
        }
        return first.id < second.id
    }

    private static func ancestors(
        from headHash: String?,
        rowsByHash: [String: CommitGraphLaneRow]
    ) -> Set<String> {
        guard let headHash else { return [] }
        var result = Set<String>()
        var stack = [headHash]
        while let hash = stack.popLast(), result.insert(hash).inserted {
            guard let row = rowsByHash[hash] else { continue }
            stack.append(contentsOf: row.commit.parentHashes)
        }
        return result
    }
}
