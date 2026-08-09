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

    private let branchIndexByID: [String: Int]
    private let primaryBranchIDByHash: [String: String]

    public init(
        branches: [CommitGraphBranchDescriptor],
        headBranchID: String?,
        primaryBranchIDByHash: [String: String]
    ) {
        self.branches = branches
        self.headBranchID = headBranchID
        self.primaryBranchIDByHash = primaryBranchIDByHash
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

    public static func build(
        topology: CommitGraphLaneTopology,
        fingerprint: CommitGraphReferenceFingerprint
    ) -> CommitGraphBranchCatalog {
        let rows = topology.rowsNewestFirst
        guard !rows.isEmpty else {
            return CommitGraphBranchCatalog(
                branches: [],
                headBranchID: nil,
                primaryBranchIDByHash: [:]
            )
        }

        let rowsByHash = Dictionary(
            rows.map { ($0.commit.fullHash, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let hashesByLane = Dictionary(grouping: rows, by: \.lane).mapValues {
            Set($0.map(\.commit.fullHash))
        }
        let latestActivityByLane = Dictionary(grouping: rows, by: \.lane)
            .mapValues { values in
                values.map(\.commit.authoredAt).max()
                    ?? Date(timeIntervalSince1970: 0)
            }
        let headReferenceName = normalizedHeadReferenceName(fingerprint.headName)
        let knownAncestors = ancestors(
            from: fingerprint.headHash,
            rowsByHash: rowsByHash
        )

        var descriptors: [CommitGraphBranchDescriptor] = []
        var descriptorIDs = Set<String>()
        for reference in fingerprint.references.sorted(by: { $0.name < $1.name }) {
            guard let row = rowsByHash[reference.targetHash] else { continue }
            let source: CommitGraphBranchSource = reference.kind == .localBranch
                ? .local
                : .remote
            let name = readableReferenceName(reference.name)
            let id = "\(source.rawValue):\(name)"
            guard descriptorIDs.insert(id).inserted else { continue }
            let isHead = reference.name == headReferenceName
                || (reference.kind == .localBranch
                    && name == fingerprint.headName
                    && reference.targetHash == fingerprint.headHash)
            descriptors.append(
                CommitGraphBranchDescriptor(
                    id: id,
                    displayName: name,
                    source: source,
                    side: side(for: row.lane),
                    lane: row.lane,
                    tipHash: reference.targetHash,
                    latestActivity: latestActivityByLane[row.lane]
                        ?? row.commit.authoredAt,
                    memberHashes: hashesByLane[row.lane] ?? [],
                    isHead: isHead,
                    isMerged: !isHead
                        && knownAncestors.contains(reference.targetHash)
                )
            )
        }

        var headBranchID = descriptors.first(where: \.isHead)?.id
        if headBranchID == nil,
           let headHash = fingerprint.headHash,
           let headRow = rowsByHash[headHash] {
            let id = "detached:HEAD"
            descriptors.append(
                CommitGraphBranchDescriptor(
                    id: id,
                    displayName: "Detached HEAD",
                    source: .detached,
                    side: .trunk,
                    lane: headRow.lane,
                    tipHash: headHash,
                    latestActivity: latestActivityByLane[headRow.lane]
                        ?? headRow.commit.authoredAt,
                    memberHashes: hashesByLane[headRow.lane] ?? [],
                    isHead: true,
                    isMerged: false
                )
            )
            descriptorIDs.insert(id)
            headBranchID = id
        }

        let representedLanes = Set(descriptors.map(\.lane))
        for lane in Set(rows.map(\.lane)).subtracting(representedLanes).sorted() {
            guard let tip = rows.first(where: { $0.lane == lane }) else { continue }
            let id = "synthetic:lane-\(lane):\(tip.commit.fullHash)"
            descriptors.append(
                CommitGraphBranchDescriptor(
                    id: id,
                    displayName: lane == 0 ? "主干" : "分支 \(lane)",
                    source: .synthetic,
                    side: side(for: lane),
                    lane: lane,
                    tipHash: tip.commit.fullHash,
                    latestActivity: latestActivityByLane[lane]
                        ?? tip.commit.authoredAt,
                    memberHashes: hashesByLane[lane] ?? [],
                    isHead: lane == 0 && headBranchID == nil,
                    isMerged: false
                )
            )
            if lane == 0 && headBranchID == nil {
                headBranchID = id
            }
        }

        descriptors.sort(by: branchOrdering)
        let descriptorsByLane = Dictionary(grouping: descriptors, by: \.lane)
        var primaryByHash: [String: String] = [:]
        for row in rows {
            let candidates = descriptorsByLane[row.lane] ?? []
            if row.lane == 0,
               let headBranchID,
               candidates.contains(where: { $0.id == headBranchID }) {
                primaryByHash[row.commit.fullHash] = headBranchID
            } else if let primary = candidates.sorted(by: branchOrdering).first {
                primaryByHash[row.commit.fullHash] = primary.id
            }
        }
        return CommitGraphBranchCatalog(
            branches: descriptors,
            headBranchID: headBranchID,
            primaryBranchIDByHash: primaryByHash
        )
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

    private static func side(for lane: Int) -> CommitGraphBranchSide {
        guard lane > 0 else { return .trunk }
        return lane.isMultiple(of: 2) ? .right : .left
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
