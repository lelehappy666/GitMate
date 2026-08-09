import Foundation

public struct CommitGraphBranchBundle: Identifiable, Equatable, Sendable {
    public let id: String
    public let branchID: String
    public let branchName: String
    public let memberHashes: [String]
    public let firstHash: String
    public let lastHash: String
    public let commitCount: Int
    public let timeRange: ClosedRange<Date>
    public let rect: GraphRect
    public let colorIndex: Int

    public init(
        id: String,
        branchID: String,
        branchName: String,
        memberHashes: [String],
        firstHash: String,
        lastHash: String,
        commitCount: Int,
        timeRange: ClosedRange<Date>,
        rect: GraphRect,
        colorIndex: Int
    ) {
        self.id = id
        self.branchID = branchID
        self.branchName = branchName
        self.memberHashes = memberHashes
        self.firstHash = firstHash
        self.lastHash = lastHash
        self.commitCount = commitCount
        self.timeRange = timeRange
        self.rect = rect
        self.colorIndex = colorIndex
    }
}

public struct CommitGraphBranchBundleInput: Sendable {
    public let catalog: CommitGraphBranchCatalog
    public let layout: CommitGraphLayoutResult
    public let edges: [CommitGraphEdge]
    public let forcedVisibleHashes: Set<String>
    public let groupBoundaryHashes: Set<String>
    public let regionBoundaryHashes: Set<String>
    public let shallowBoundaryHashes: Set<String>
    public let expandedBundleIDs: Set<String>

    public init(
        catalog: CommitGraphBranchCatalog,
        layout: CommitGraphLayoutResult,
        edges: [CommitGraphEdge],
        forcedVisibleHashes: Set<String>,
        groupBoundaryHashes: Set<String>,
        regionBoundaryHashes: Set<String>,
        shallowBoundaryHashes: Set<String>,
        expandedBundleIDs: Set<String>
    ) {
        self.catalog = catalog
        self.layout = layout
        self.edges = edges
        self.forcedVisibleHashes = forcedVisibleHashes
        self.groupBoundaryHashes = groupBoundaryHashes
        self.regionBoundaryHashes = regionBoundaryHashes
        self.shallowBoundaryHashes = shallowBoundaryHashes
        self.expandedBundleIDs = expandedBundleIDs
    }
}

public struct CommitGraphBranchBundleProjection: Equatable, Sendable {
    public let bundles: [CommitGraphBranchBundle]
    public let hiddenMemberHashes: Set<String>
    public let hiddenInternalEdgeIDs: Set<String>

    private let bundleIndexByMemberHash: [String: Int]
    private let bundleIndicesByBucket: [Int: [Int]]

    public init(
        bundles: [CommitGraphBranchBundle] = [],
        hiddenMemberHashes: Set<String> = [],
        hiddenInternalEdgeIDs: Set<String> = []
    ) {
        self.bundles = bundles
        self.hiddenMemberHashes = hiddenMemberHashes
        self.hiddenInternalEdgeIDs = hiddenInternalEdgeIDs
        var byHash: [String: Int] = [:]
        var byBucket: [Int: [Int]] = [:]
        for (index, bundle) in bundles.enumerated() {
            for hash in bundle.memberHashes {
                byHash[hash] = index
            }
            let first = Self.bucket(bundle.rect.minimumY)
            let last = Self.bucket(bundle.rect.maximumY)
            for value in first...last {
                byBucket[value, default: []].append(index)
            }
        }
        bundleIndexByMemberHash = byHash
        bundleIndicesByBucket = byBucket
    }

    public func bundle(containing hash: String) -> CommitGraphBranchBundle? {
        guard let index = bundleIndexByMemberHash[hash] else { return nil }
        return bundles[index]
    }

    public func visibleBundles(in rect: GraphRect) -> [CommitGraphBranchBundle] {
        guard rect.width.isFinite,
              rect.height.isFinite,
              rect.minimumY.isFinite,
              rect.maximumY.isFinite
        else { return [] }
        let first = Self.bucket(rect.minimumY)
        let last = Self.bucket(rect.maximumY)
        var candidates = Set<Int>()
        for value in first...last {
            candidates.formUnion(bundleIndicesByBucket[value] ?? [])
        }
        return candidates.sorted().compactMap { index in
            let bundle = bundles[index]
            return Self.intersects(bundle.rect, rect) ? bundle : nil
        }
    }

    private static let bucketHeight = 512.0

    private static func bucket(_ value: Double) -> Int {
        Int(floor(value / bucketHeight))
    }

    private static func intersects(_ first: GraphRect, _ second: GraphRect) -> Bool {
        first.maximumX >= second.minimumX
            && first.minimumX <= second.maximumX
            && first.maximumY >= second.minimumY
            && first.minimumY <= second.maximumY
    }
}

public enum CommitGraphBranchBundleBuilder {
    public static func build(
        input: CommitGraphBranchBundleInput
    ) -> CommitGraphBranchBundleProjection {
        guard !input.layout.nodes.isEmpty else {
            return CommitGraphBranchBundleProjection()
        }
        let nodesByHash = Dictionary(
            input.layout.nodes.map { ($0.hash, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let knownHashes = Set(nodesByHash.keys)
        let knownEdges = input.edges.filter {
            knownHashes.contains($0.childHash)
                && knownHashes.contains($0.parentHash)
        }
        var parentCountByChild: [String: Int] = [:]
        var childCountByParent: [String: Int] = [:]
        var directPairs = Set<String>()
        var anchors = input.forcedVisibleHashes
            .union(input.groupBoundaryHashes)
            .union(input.regionBoundaryHashes)
            .union(input.shallowBoundaryHashes)

        for edge in knownEdges {
            parentCountByChild[edge.childHash, default: 0] += 1
            childCountByParent[edge.parentHash, default: 0] += 1
            directPairs.insert(pair(edge.parentHash, edge.childHash))
            if edge.kind == .merge {
                anchors.insert(edge.childHash)
                anchors.insert(edge.parentHash)
            }
        }
        for node in input.layout.nodes {
            if parentCountByChild[node.hash, default: 0] != 1
                || childCountByParent[node.hash, default: 0] != 1
                || !node.decorations.isEmpty {
                anchors.insert(node.hash)
            }
        }
        for branch in input.catalog.branches {
            anchors.insert(branch.tipHash)
        }

        let nodesByBranch = Dictionary(
            grouping: input.layout.nodes.compactMap { node
                -> (String, CommitGraphNode)? in
                guard let branch = input.catalog.branch(containing: node.hash)
                else { return nil }
                return (branch.id, node)
            },
            by: { $0.0 }
        )
        var bundles: [CommitGraphBranchBundle] = []
        for branchID in nodesByBranch.keys.sorted() {
            guard let branch = input.catalog.branch(id: branchID) else { continue }
            let nodes = (nodesByBranch[branchID] ?? [])
                .map(\.1)
                .sorted { $0.row < $1.row }
            var segment: [CommitGraphNode] = []

            func flush() {
                guard segment.count >= 2,
                      let first = segment.first,
                      let last = segment.last
                else {
                    segment.removeAll(keepingCapacity: true)
                    return
                }
                let id = "\(branchID)|\(first.hash)|\(last.hash)"
                defer { segment.removeAll(keepingCapacity: true) }
                guard !input.expandedBundleIDs.contains(id) else { return }
                bundles.append(makeBundle(id: id, branch: branch, nodes: segment))
            }

            for node in nodes {
                guard !anchors.contains(node.hash) else {
                    flush()
                    continue
                }
                if let previous = segment.last,
                   !directPairs.contains(pair(previous.hash, node.hash)) {
                    flush()
                }
                segment.append(node)
            }
            flush()
        }
        bundles.sort {
            if $0.rect.minimumY != $1.rect.minimumY {
                return $0.rect.minimumY < $1.rect.minimumY
            }
            return $0.id < $1.id
        }

        let bundleIDByHash = Dictionary(
            bundles.flatMap { bundle in
                bundle.memberHashes.map { ($0, bundle.id) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let hiddenHashes = Set(bundleIDByHash.keys)
        let hiddenEdges = Set<String>(input.edges.compactMap { edge
            -> String? in
            guard let childBundle = bundleIDByHash[edge.childHash],
                  childBundle == bundleIDByHash[edge.parentHash]
            else { return nil }
            return edge.id
        })
        return CommitGraphBranchBundleProjection(
            bundles: bundles,
            hiddenMemberHashes: hiddenHashes,
            hiddenInternalEdgeIDs: hiddenEdges
        )
    }

    private static func pair(_ parent: String, _ child: String) -> String {
        "\(parent)\u{1F}\(child)"
    }

    private static func makeBundle(
        id: String,
        branch: CommitGraphBranchDescriptor,
        nodes: [CommitGraphNode]
    ) -> CommitGraphBranchBundle {
        let first = nodes[0]
        let last = nodes[nodes.count - 1]
        let dates = nodes.map(\.authoredAt)
        let minimumDate = dates.min() ?? first.authoredAt
        let maximumDate = dates.max() ?? last.authoredAt
        let minimumX = nodes.map(\.x).min() ?? first.x
        let maximumX = nodes.map(\.x).max() ?? last.x
        let minimumY = nodes.map(\.y).min() ?? first.y
        let maximumY = nodes.map(\.y).max() ?? last.y
        return CommitGraphBranchBundle(
            id: id,
            branchID: branch.id,
            branchName: branch.displayName,
            memberHashes: nodes.map(\.hash),
            firstHash: first.hash,
            lastHash: last.hash,
            commitCount: nodes.count,
            timeRange: minimumDate...maximumDate,
            rect: GraphRect(
                x: minimumX - 28,
                y: minimumY - 34,
                width: max(maximumX - minimumX + 56, 56),
                height: max(maximumY - minimumY + 68, 68)
            ),
            colorIndex: first.colorIndex
        )
    }
}
