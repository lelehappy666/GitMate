import Foundation

public enum CommitGraphTraditionalLaneCapacity {
    public static let minimum = 4
    public static let maximum = 8

    public static func visibleCount(totalWidth: Double) -> Int {
        guard totalWidth.isFinite, totalWidth > 0 else { return minimum }
        let computed = Int(floor((totalWidth - 400) / 100))
        return min(max(computed, minimum), maximum)
    }
}

public enum CommitGraphTraditionalBranchSlotKind: Equatable, Sendable {
    case branch
    case hiddenBranches
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
    public let hiddenLocalCount: Int
    public let hiddenRemoteCount: Int

    public init(
        id: String,
        lane: Int,
        kind: CommitGraphTraditionalBranchSlotKind,
        title: String,
        source: CommitGraphBranchSource,
        branchID: String?,
        hiddenLocalCount: Int = 0,
        hiddenRemoteCount: Int = 0
    ) {
        self.id = id
        self.lane = max(lane, 0)
        self.kind = kind
        self.title = title
        self.source = source
        self.branchID = branchID
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
        self.capacity = min(
            max(capacity, CommitGraphTraditionalLaneCapacity.minimum),
            CommitGraphTraditionalLaneCapacity.maximum
        )
        self.visibleBranches = visibleBranches
        self.hiddenLocalBranches = hiddenLocalBranches
        self.hiddenRemoteBranches = hiddenRemoteBranches
        self.slots = slots
        self.slotByBranchID = slotByBranchID
    }

    public static let empty = CommitGraphTraditionalBranchProjection(
        capacity: CommitGraphTraditionalLaneCapacity.minimum,
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
        let capacity = CommitGraphTraditionalLaneCapacity.visibleCount(
            totalWidth: input.totalWidth
        )
        guard !input.catalog.branches.isEmpty else {
            return CommitGraphTraditionalBranchProjection(
                capacity: capacity,
                visibleBranches: [],
                hiddenLocalBranches: [],
                hiddenRemoteBranches: [],
                slots: [],
                slotByBranchID: [:]
            )
        }

        let selectedBranchID = input.selectedHash.flatMap {
            input.catalog.branch(containing: $0)?.id
        } ?? input.lastSelectedBranchID.flatMap {
            input.catalog.branch(id: $0)?.id
        }
        let relatedIDs = selectedBranchID.map {
            input.catalog.relatedBranchIDs(to: $0)
        } ?? []
        let ordered = input.catalog.branches.sorted {
            priority(
                $0,
                headBranchID: input.catalog.headBranchID,
                selectedBranchID: selectedBranchID,
                pinnedBranchIDs: input.pinnedBranchIDs,
                relatedBranchIDs: relatedIDs
            ) < priority(
                $1,
                headBranchID: input.catalog.headBranchID,
                selectedBranchID: selectedBranchID,
                pinnedBranchIDs: input.pinnedBranchIDs,
                relatedBranchIDs: relatedIDs
            )
        }
        let needsAggregate = ordered.count > capacity
        let branchLimit = max(capacity - (needsAggregate ? 1 : 0), 1)
        let visible = Array(ordered.prefix(branchLimit))
        let visibleIDs = Set(visible.map(\.id))
        let hidden = ordered.filter { !visibleIDs.contains($0.id) }
        let hiddenLocal = hidden.filter { $0.source != .remote }
        let hiddenRemote = hidden.filter { $0.source == .remote }

        var slots: [CommitGraphTraditionalBranchSlot] = visible.enumerated().map {
            index,
            branch in
            CommitGraphTraditionalBranchSlot(
                id: "branch:\(branch.id)",
                lane: index,
                kind: .branch,
                title: branch.displayName,
                source: branch.source,
                branchID: branch.id
            )
        }
        if !hidden.isEmpty {
            slots.append(
                CommitGraphTraditionalBranchSlot(
                    id: "hidden:all",
                    lane: slots.count,
                    kind: .hiddenBranches,
                    title: "其他分支",
                    source: .synthetic,
                    branchID: nil,
                    hiddenLocalCount: hiddenLocal.count,
                    hiddenRemoteCount: hiddenRemote.count
                )
            )
        }
        var slotByBranchID = Dictionary(
            uniqueKeysWithValues: zip(visible, slots).map {
                ($0.0.id, $0.1)
            }
        )
        if let aggregate = slots.last,
           aggregate.kind == .hiddenBranches {
            for branch in hidden {
                slotByBranchID[branch.id] = aggregate
            }
        }
        return CommitGraphTraditionalBranchProjection(
            capacity: capacity,
            visibleBranches: visible,
            hiddenLocalBranches: hiddenLocal,
            hiddenRemoteBranches: hiddenRemote,
            slots: slots,
            slotByBranchID: slotByBranchID
        )
    }

    private struct Priority: Comparable {
        let group: Int
        let activity: Date
        let source: Int
        let id: String

        static func < (first: Priority, second: Priority) -> Bool {
            if first.group != second.group { return first.group < second.group }
            if first.activity != second.activity {
                return first.activity > second.activity
            }
            if first.source != second.source { return first.source < second.source }
            return first.id < second.id
        }
    }

    private static func priority(
        _ branch: CommitGraphBranchDescriptor,
        headBranchID: String?,
        selectedBranchID: String?,
        pinnedBranchIDs: Set<String>,
        relatedBranchIDs: Set<String>
    ) -> Priority {
        let group: Int
        if branch.id == headBranchID {
            group = 0
        } else if branch.id == selectedBranchID {
            group = 1
        } else if pinnedBranchIDs.contains(branch.id) {
            group = 2
        } else if relatedBranchIDs.contains(branch.id) {
            group = 3
        } else if branch.source == .local {
            group = 4
        } else if branch.source == .remote {
            group = 5
        } else {
            group = 6
        }
        let source: Int = branch.source == .local
            ? 0
            : (branch.source == .remote ? 1 : 2)
        return Priority(
            group: group,
            activity: branch.latestActivity,
            source: source,
            id: branch.id
        )
    }
}
