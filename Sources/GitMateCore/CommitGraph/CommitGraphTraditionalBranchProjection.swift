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
        hiddenRemoteCount: Int = 0
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
    }
}

public struct CommitGraphTraditionalBranchProjectionInput: Sendable {
    public let catalog: CommitGraphBranchCatalog
    public let totalWidth: Double
    public let selectedHash: String?
    public let pinnedBranchIDs: Set<String>
    public let lastSelectedBranchID: String?

    public init(
        catalog: CommitGraphBranchCatalog,
        totalWidth: Double,
        selectedHash: String?,
        pinnedBranchIDs: Set<String>,
        lastSelectedBranchID: String?
    ) {
        self.catalog = catalog
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

        let groups = logicalGroups(catalog: input.catalog)
            .sorted { priority($0, headBranchID: input.catalog.headBranchID)
                < priority($1, headBranchID: input.catalog.headBranchID) }

        var representatives: [CommitGraphBranchDescriptor] = []
        var slots: [CommitGraphTraditionalBranchSlot] = []
        var slotByBranchID: [String: CommitGraphTraditionalBranchSlot] = [:]
        representatives.reserveCapacity(groups.count)
        slots.reserveCapacity(groups.count)

        for (lane, group) in groups.enumerated() {
            let branches = group.orderedBranches
            guard let representative = branches.first else { continue }
            let branchIDs = branches.map(\.id)
            let referenceTitles = branches.map(\.displayName)
            let primary = branches.first(where: { $0.source == .local })
                ?? branches.first(where: { isOrigin($0) })
                ?? representative
            let slot = CommitGraphTraditionalBranchSlot(
                id: "logical:\(group.identity)",
                lane: lane,
                kind: .branch,
                title: primary.source == .remote
                    ? primary.displayName
                    : group.identity,
                source: primary.source,
                branchID: primary.id,
                branchIDs: branchIDs,
                referenceTitles: referenceTitles
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

    private struct GroupPriority: Comparable {
        let group: Int
        let activity: Date
        let identity: String

        static func < (first: GroupPriority, second: GroupPriority) -> Bool {
            if first.group != second.group { return first.group < second.group }
            if first.activity != second.activity {
                return first.activity > second.activity
            }
            return first.identity < second.identity
        }
    }

    private static func logicalGroups(
        catalog: CommitGraphBranchCatalog
    ) -> [LogicalGroup] {
        var grouped: [String: [CommitGraphBranchDescriptor]] = [:]
        for branch in catalog.branches {
            grouped[logicalIdentity(for: branch), default: []].append(branch)
        }
        return grouped.map { identity, branches in
            LogicalGroup(identity: identity, branches: branches)
        }
    }

    private static func priority(
        _ group: LogicalGroup,
        headBranchID: String?
    ) -> GroupPriority {
        let rank: Int
        if group.isMain {
            rank = 0
        } else if group.containsBranch(id: headBranchID) {
            rank = 1
        } else if group.hasLocal {
            rank = 2
        } else if group.branches.allSatisfy({ $0.source == .remote }) {
            rank = 3
        } else {
            rank = 4
        }
        return GroupPriority(
            group: rank,
            activity: group.latestActivity,
            identity: group.identity
        )
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
}
