import Foundation

/// 传统布局不再按窗口宽度隐藏分支；该类型保留用于兼容旧调用方。
public enum CommitGraphTraditionalLaneCapacity {
    public static let minimum = 0
    public static let maximum = Int.max

    public static func visibleCount(totalWidth _: Double) -> Int {
        Int.max
    }
}

public enum CommitGraphTraditionalBranchSlotKind: Equatable, Sendable {
    case branch
    case hiddenLocalBranches
    case hiddenRemoteBranches
}

public struct CommitGraphTraditionalBranchSlot:
    Identifiable,
    Equatable,
    Sendable
{
    public let id: String
    public let lane: Int
    public let kind: CommitGraphTraditionalBranchSlotKind
    public let title: String
    public let source: CommitGraphBranchSource
    public let branchID: String?
    public let branchIDs: [String]
    public let referenceTitles: [String]
    public let hiddenLocalCount: Int
    public let hiddenRemoteCount: Int
    public let logicalIdentity: String
    public let isPlaceholder: Bool

    public init(
        id: String,
        lane: Int,
        kind: CommitGraphTraditionalBranchSlotKind,
        title: String,
        source: CommitGraphBranchSource,
        branchID: String?,
        branchIDs: [String]? = nil,
        referenceTitles: [String]? = nil,
        hiddenLocalCount: Int = 0,
        hiddenRemoteCount: Int = 0,
        logicalIdentity: String? = nil,
        isPlaceholder: Bool = false
    ) {
        self.id = id
        self.lane = max(lane, 0)
        self.kind = kind
        self.title = title
        self.source = source
        self.branchID = branchID
        self.branchIDs = branchIDs
            ?? branchID.map { [$0] }
            ?? []
        self.referenceTitles = referenceTitles ?? [title]
        self.hiddenLocalCount = max(hiddenLocalCount, 0)
        self.hiddenRemoteCount = max(hiddenRemoteCount, 0)
        self.logicalIdentity = logicalIdentity ?? title
        self.isPlaceholder = isPlaceholder
    }
}

public struct CommitGraphTraditionalBranchProjectionInput: Sendable {
    public let catalog: CommitGraphBranchCatalog
    public let topology: CommitGraphLaneTopology
    public let totalWidth: Double
    public let selectedHash: String?
    public let pinnedBranchIDs: Set<String>
    public let lastSelectedBranchID: String?

    public init(
        catalog: CommitGraphBranchCatalog,
        topology: CommitGraphLaneTopology = CommitGraphLaneTopology(
            rowsNewestFirst: [],
            maximumLane: 0
        ),
        totalWidth: Double,
        selectedHash: String?,
        pinnedBranchIDs: Set<String>,
        lastSelectedBranchID: String?
    ) {
        self.catalog = catalog
        self.topology = topology
        self.totalWidth = totalWidth
        self.selectedHash = selectedHash
        self.pinnedBranchIDs = pinnedBranchIDs
        self.lastSelectedBranchID = lastSelectedBranchID
    }
}

public struct CommitGraphTraditionalBranchProjection:
    Equatable,
    Sendable
{
    public let capacity: Int
    public let visibleBranches: [CommitGraphBranchDescriptor]
    public let hiddenLocalBranches: [CommitGraphBranchDescriptor]
    public let hiddenRemoteBranches: [CommitGraphBranchDescriptor]
    public let slots: [CommitGraphTraditionalBranchSlot]

    private let slotByBranchID: [String: CommitGraphTraditionalBranchSlot]

    public var hiddenLocalCount: Int { hiddenLocalBranches.count }
    public var hiddenRemoteCount: Int { hiddenRemoteBranches.count }

    public init(
        capacity: Int,
        visibleBranches: [CommitGraphBranchDescriptor],
        hiddenLocalBranches: [CommitGraphBranchDescriptor],
        hiddenRemoteBranches: [CommitGraphBranchDescriptor],
        slots: [CommitGraphTraditionalBranchSlot],
        slotByBranchID: [String: CommitGraphTraditionalBranchSlot]
    ) {
        self.capacity = max(capacity, slots.count)
        self.visibleBranches = visibleBranches
        self.hiddenLocalBranches = hiddenLocalBranches
        self.hiddenRemoteBranches = hiddenRemoteBranches
        self.slots = slots
        self.slotByBranchID = slotByBranchID
    }

    public static let empty = CommitGraphTraditionalBranchProjection(
        capacity: 0,
        visibleBranches: [],
        hiddenLocalBranches: [],
        hiddenRemoteBranches: [],
        slots: [],
        slotByBranchID: [:]
    )

    public func displayLane(for branchID: String) -> Int? {
        slotByBranchID[branchID]?.lane
    }

    public func slot(
        forBranchID branchID: String
    ) -> CommitGraphTraditionalBranchSlot? {
        slotByBranchID[branchID]
    }
}

public enum CommitGraphTraditionalBranchProjector {
    public static func project(
        _ input: CommitGraphTraditionalBranchProjectionInput
    ) -> CommitGraphTraditionalBranchProjection {
        guard !input.catalog.branches.isEmpty else { return .empty }

        let ancestry = AncestryIndex(topology: input.topology)
        let groups = orderedLogicalGroups(
            catalog: input.catalog,
            ancestry: ancestry
        )

        var representatives: [CommitGraphBranchDescriptor] = []
        var slots: [CommitGraphTraditionalBranchSlot] = []
        var slotByBranchID: [String: CommitGraphTraditionalBranchSlot] = [:]
        let hasMain = groups.contains { $0.isMain }
        representatives.reserveCapacity(groups.count)
        slots.reserveCapacity(groups.count + (hasMain ? 0 : 1))

        if !hasMain {
            slots.append(
                CommitGraphTraditionalBranchSlot(
                    id: "logical:main:placeholder",
                    lane: 0,
                    kind: .branch,
                    title: "main（不存在）",
                    source: .local,
                    branchID: nil,
                    branchIDs: [],
                    referenceTitles: [],
                    logicalIdentity: "main",
                    isPlaceholder: true
                )
            )
        }

        for (offset, group) in groups.enumerated() {
            let lane = offset + (hasMain ? 0 : 1)
            let branches = group.orderedBranches
            guard let representative = branches.first else { continue }
            let branchIDs = branches.map(\.id)
            let referenceTitles = branches.map(\.displayName)
            let primary = branches.first(where: { $0.source == .local })
                ?? branches.first(where: { isOrigin($0) })
                ?? representative
            let slot = CommitGraphTraditionalBranchSlot(
                id: "logical:\(group.stableIdentity)",
                lane: lane,
                kind: .branch,
                title: primary.source == .remote
                    ? primary.displayName
                    : group.identity,
                source: primary.source,
                branchID: primary.id,
                branchIDs: branchIDs,
                referenceTitles: referenceTitles,
                logicalIdentity: group.identity
            )
            representatives.append(primary)
            slots.append(slot)
            for branchID in branchIDs {
                slotByBranchID[branchID] = slot
            }
        }

        return CommitGraphTraditionalBranchProjection(
            capacity: slots.count,
            visibleBranches: representatives,
            hiddenLocalBranches: [],
            hiddenRemoteBranches: [],
            slots: slots,
            slotByBranchID: slotByBranchID
        )
    }

    private struct LogicalGroup {
        let identity: String
        let stableIdentity: String
        let branches: [CommitGraphBranchDescriptor]

        var orderedBranches: [CommitGraphBranchDescriptor] {
            branches.sorted { first, second in
                let firstRank = sourceRank(first)
                let secondRank = sourceRank(second)
                if firstRank != secondRank { return firstRank < secondRank }
                return first.id < second.id
            }
        }

        var latestActivity: Date {
            branches.map(\.latestActivity).max() ?? .distantPast
        }

        var hasLocal: Bool {
            branches.contains { $0.source == .local }
        }

        var isMain: Bool { identity == "main" }

        func containsBranch(id: String?) -> Bool {
            guard let id else { return false }
            return branches.contains { $0.id == id }
        }

        private func sourceRank(
            _ branch: CommitGraphBranchDescriptor
        ) -> Int {
            switch branch.source {
            case .local: 0
            case .remote:
                CommitGraphTraditionalBranchProjector.isOrigin(branch) ? 1 : 2
            case .detached: 3
            case .synthetic: 4
            }
        }
    }

    private struct LogicalFamily {
        let identity: String
        let groups: [LogicalGroup]

        var latestActivity: Date {
            groups.map(\.latestActivity).max() ?? .distantPast
        }

        var hasLocal: Bool {
            groups.contains { $0.hasLocal }
        }

        func containsBranch(id: String?) -> Bool {
            groups.contains { $0.containsBranch(id: id) }
        }
    }

    private struct FamilyPriority: Comparable {
        let group: Int
        let activity: Date
        let identity: String

        static func < (first: FamilyPriority, second: FamilyPriority) -> Bool {
            if first.group != second.group { return first.group < second.group }
            if first.activity != second.activity {
                return first.activity > second.activity
            }
            return first.identity < second.identity
        }
    }

    private static func orderedLogicalGroups(
        catalog: CommitGraphBranchCatalog,
        ancestry: AncestryIndex
    ) -> [LogicalGroup] {
        var grouped: [String: [CommitGraphBranchDescriptor]] = [:]
        for branch in catalog.branches {
            grouped[logicalIdentity(for: branch), default: []].append(branch)
        }
        let families = grouped.map { identity, branches in
            LogicalFamily(
                identity: identity,
                groups: linearGroups(
                    identity: identity,
                    branches: branches,
                    ancestry: ancestry
                )
            )
        }
        return families
            .sorted {
                familyPriority($0, headBranchID: catalog.headBranchID)
                    < familyPriority($1, headBranchID: catalog.headBranchID)
            }
            .flatMap { family in
                family.groups.sorted(by: groupOrdering)
            }
    }

    private static func familyPriority(
        _ family: LogicalFamily,
        headBranchID: String?
    ) -> FamilyPriority {
        let rank: Int
        if family.identity == "main" {
            rank = 0
        } else if family.containsBranch(id: headBranchID) {
            rank = 1
        } else if family.hasLocal {
            rank = 2
        } else if family.groups.flatMap(\.branches).allSatisfy({
            $0.source == .remote
        }) {
            rank = 3
        } else {
            rank = 4
        }
        return FamilyPriority(
            group: rank,
            activity: family.latestActivity,
            identity: family.identity
        )
    }

    private static func linearGroups(
        identity: String,
        branches: [CommitGraphBranchDescriptor],
        ancestry: AncestryIndex
    ) -> [LogicalGroup] {
        var clusters: [[CommitGraphBranchDescriptor]] = []
        for branch in branches.sorted(by: stableBranchOrdering) {
            if let index = clusters.firstIndex(where: { cluster in
                cluster.allSatisfy {
                    ancestry.areLinearlyRelated(
                        first: $0.tipHash,
                        second: branch.tipHash
                    )
                }
            }) {
                clusters[index].append(branch)
            } else {
                clusters.append([branch])
            }
        }
        return clusters.map { cluster in
            let branchIDs = cluster.map(\.id).sorted().joined(separator: "+")
            return LogicalGroup(
                identity: identity,
                stableIdentity: "\(identity):\(branchIDs)",
                branches: cluster
            )
        }
    }

    private static func stableBranchOrdering(
        _ first: CommitGraphBranchDescriptor,
        _ second: CommitGraphBranchDescriptor
    ) -> Bool {
        let firstRank = sourceRank(first)
        let secondRank = sourceRank(second)
        if firstRank != secondRank { return firstRank < secondRank }
        return first.id < second.id
    }

    private static func groupOrdering(
        _ first: LogicalGroup,
        _ second: LogicalGroup
    ) -> Bool {
        let firstRepresentative = first.orderedBranches.first
        let secondRepresentative = second.orderedBranches.first
        guard let firstRepresentative, let secondRepresentative else {
            return first.stableIdentity < second.stableIdentity
        }
        let firstRank = sourceRank(firstRepresentative)
        let secondRank = sourceRank(secondRepresentative)
        if firstRank != secondRank { return firstRank < secondRank }
        if first.latestActivity != second.latestActivity {
            return first.latestActivity > second.latestActivity
        }
        return first.stableIdentity < second.stableIdentity
    }

    private static func sourceRank(
        _ branch: CommitGraphBranchDescriptor
    ) -> Int {
        switch branch.source {
        case .local: 0
        case .remote: isOrigin(branch) ? 1 : 2
        case .detached: 3
        case .synthetic: 4
        }
    }

    private static func logicalIdentity(
        for branch: CommitGraphBranchDescriptor
    ) -> String {
        switch branch.source {
        case .local:
            return branch.displayName
        case .remote:
            let components = branch.displayName.split(separator: "/")
            guard components.count > 1 else { return branch.displayName }
            return components.dropFirst().joined(separator: "/")
        case .detached, .synthetic:
            return branch.id
        }
    }

    private static func isOrigin(
        _ branch: CommitGraphBranchDescriptor
    ) -> Bool {
        branch.source == .remote
            && branch.displayName.hasPrefix("origin/")
    }

    private struct AncestryIndex {
        let parentsByHash: [String: [String]]

        init(topology: CommitGraphLaneTopology) {
            parentsByHash = Dictionary(
                topology.rowsNewestFirst.map {
                    ($0.commit.fullHash, $0.commit.parentHashes)
                },
                uniquingKeysWith: { first, _ in first }
            )
        }

        func areLinearlyRelated(first: String, second: String) -> Bool {
            first == second
                || isAncestor(first, of: second)
                || isAncestor(second, of: first)
        }

        private func isAncestor(_ ancestor: String, of descendant: String) -> Bool {
            guard parentsByHash[ancestor] != nil,
                  parentsByHash[descendant] != nil
            else { return false }
            var visited = Set<String>()
            var stack = [descendant]
            while let hash = stack.popLast(), visited.insert(hash).inserted {
                for parent in parentsByHash[hash] ?? [] {
                    if parent == ancestor { return true }
                    if parentsByHash[parent] != nil { stack.append(parent) }
                }
            }
            return false
        }
    }
}
