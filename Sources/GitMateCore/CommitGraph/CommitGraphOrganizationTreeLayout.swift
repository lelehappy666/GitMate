import Foundation

/// 自上而下的分层组织树布局。
///
/// 第一父提交构成稳定主树，其余父边仍保留为 Merge 关系。实现只使用迭代
/// 扫描，五万提交时不会产生递归栈风险。
public struct CommitGraphOrganizationTreeLayout: Sendable {
    public let horizontalSpacing: Double
    public let verticalSpacing: Double

    public init(
        horizontalSpacing: Double = 500,
        verticalSpacing: Double = 252
    ) {
        self.horizontalSpacing = max(horizontalSpacing, 224)
        self.verticalSpacing = max(verticalSpacing, 74)
    }

    public func layout(
        topology: CommitGraphLaneTopology,
        preserving previous: CommitGraphLayoutResult? = nil
    ) -> CommitGraphLayoutResult {
        let newestFirst = topology.rowsNewestFirst
        guard !newestFirst.isEmpty else { return CommitGraphLayoutResult() }
        let oldestFirst = Array(newestFirst.reversed())
        let rowsByHash = Dictionary(
            newestFirst.map { ($0.commit.fullHash, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let knownHashes = Set(rowsByHash.keys)
        let previousColumns = Dictionary(
            (previous?.nodes ?? []).map { ($0.hash, $0.column) },
            uniquingKeysWith: { first, _ in first }
        )
        let columnByHash = Dictionary(
            newestFirst.map {
                (
                    $0.commit.fullHash,
                    previousColumns[$0.commit.fullHash] ?? $0.lane
                )
            },
            uniquingKeysWith: { first, _ in first }
        )

        var primaryParentByChild: [String: String] = [:]
        var primaryChildrenByParent: [String: [String]] = [:]
        for row in newestFirst {
            guard let parent = row.commit.parentHashes.first(
                where: knownHashes.contains
            ) else { continue }
            primaryParentByChild[row.commit.fullHash] = parent
            primaryChildrenByParent[parent, default: []].append(
                row.commit.fullHash
            )
        }
        for parent in primaryChildrenByParent.keys {
            primaryChildrenByParent[parent]?.sort {
                stableTreeOrdering(
                    first: $0,
                    second: $1,
                    columnByHash: columnByHash
                )
            }
        }

        var depthByHash: [String: Int] = [:]
        depthByHash.reserveCapacity(oldestFirst.count)
        for row in oldestFirst {
            let parentDepths = row.commit.parentHashes.compactMap {
                depthByHash[$0]
            }
            depthByHash[row.commit.fullHash] =
                (parentDepths.max().map { $0 + 1 }) ?? 0
        }

        var leafCountByHash: [String: Int] = [:]
        leafCountByHash.reserveCapacity(newestFirst.count)
        for row in newestFirst {
            let children = primaryChildrenByParent[
                row.commit.fullHash,
                default: []
            ]
            leafCountByHash[row.commit.fullHash] = max(
                children.reduce(0) {
                    $0 + leafCountByHash[$1, default: 1]
                },
                1
            )
        }

        let roots = oldestFirst.map(\.commit.fullHash)
            .filter { primaryParentByChild[$0] == nil }
            .sorted {
                stableTreeOrdering(
                    first: $0,
                    second: $1,
                    columnByHash: columnByHash
                )
            }
        var slotByHash: [String: Double] = [:]
        slotByHash.reserveCapacity(oldestFirst.count)
        var rootStart = 0
        var pending: [(hash: String, start: Int)] = []
        for root in roots {
            pending.append((root, rootStart))
            rootStart += leafCountByHash[root, default: 1] + 1
        }
        while let current = pending.popLast() {
            let width = leafCountByHash[current.hash, default: 1]
            slotByHash[current.hash] = Double(current.start)
                + Double(width - 1) / 2
            let children = primaryChildrenByParent[current.hash, default: []]
            var childStart = current.start
            var childPlacements: [(hash: String, start: Int)] = []
            childPlacements.reserveCapacity(children.count)
            for child in children {
                childPlacements.append((child, childStart))
                childStart += leafCountByHash[child, default: 1]
            }
            pending.append(contentsOf: childPlacements.reversed())
        }

        let rawXByHash = slotByHash.mapValues { $0 * horizontalSpacing }
        let minimumRawX = rawXByHash.values.min() ?? 0
        let maximumRawX = rawXByHash.values.max() ?? 0
        let naturalWidth = maximumRawX - minimumRawX + 300
        let contentWidth = max(1_040, naturalWidth)
        let xOffset = 150 + (contentWidth - naturalWidth) / 2 - minimumRawX
        let nodes = oldestFirst.enumerated().map { index, row in
            let commit = row.commit
            return CommitGraphNode(
                hash: commit.fullHash,
                shortHash: commit.shortHash,
                subject: commit.subject,
                authorName: commit.authorName,
                authorEmail: commit.authorEmail,
                authoredAt: commit.authoredAt,
                decorations: commit.decorations,
                column: columnByHash[commit.fullHash] ?? row.lane,
                row: index,
                colorIndex: row.colorIndex,
                x: rawXByHash[commit.fullHash, default: 0] + xOffset,
                y: 82 + Double(depthByHash[commit.fullHash, default: 0])
                    * verticalSpacing
            )
        }
        let edges = newestFirst.flatMap { row in
            row.connections.map { connection in
                CommitGraphEdge(
                    id: connection.id,
                    childHash: connection.childHash,
                    parentHash: connection.parentHash,
                    kind: connection.kind,
                    colorIndex: connection.colorIndex
                )
            }
        }
        let nodesByHash = Dictionary(
            nodes.map { ($0.hash, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let shallowBoundaryEndpoints = topology.shallowBoundaryRelations
            .compactMap { relation -> CommitGraphShallowBoundaryEndpoint? in
                guard let child = nodesByHash[relation.childHash] else {
                    return nil
                }
                return CommitGraphShallowBoundaryEndpoint(
                    relation: relation,
                    x: child.x,
                    y: child.y - verticalSpacing * 0.65
                )
            }
        let maximumDepth = depthByHash.values.max() ?? 0
        return CommitGraphLayoutResult(
            nodes: nodes,
            edges: edges,
            shallowBoundaryEndpoints: shallowBoundaryEndpoints,
            contentWidth: contentWidth,
            contentHeight: max(
                680,
                164 + Double(maximumDepth) * verticalSpacing
            )
        )
    }

    private func stableTreeOrdering(
        first: String,
        second: String,
        columnByHash: [String: Int]
    ) -> Bool {
        let firstSlot = treeBranchSlot(columnByHash[first, default: 0])
        let secondSlot = treeBranchSlot(columnByHash[second, default: 0])
        if firstSlot != secondSlot { return firstSlot < secondSlot }
        return first < second
    }

    private func treeBranchSlot(_ column: Int) -> Int {
        guard column > 0 else { return 0 }
        let distance = (column + 1) / 2
        return column.isMultiple(of: 2) ? distance : -distance
    }
}
