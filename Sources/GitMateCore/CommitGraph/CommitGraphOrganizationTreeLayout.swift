import Foundation

/// 自上而下的分层组织树布局。
///
/// 默认分支的第一父链固定在画布中央，其他泳道按稳定顺序分布到主干左右，
/// 其余父边仍保留为 Merge 关系。实现只使用迭代扫描，五万提交时不会产生
/// 递归栈风险。
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

        var depthByHash: [String: Int] = [:]
        depthByHash.reserveCapacity(oldestFirst.count)
        for row in oldestFirst {
            let parentDepths = row.commit.parentHashes.compactMap {
                depthByHash[$0]
            }
            depthByHash[row.commit.fullHash] =
                (parentDepths.max().map { $0 + 1 }) ?? 0
        }

        // CommitGraphLaneTopology 已经把默认分支第一父链固定为 lane 0。
        // 这里不再按叶子数量重新居中父节点，否则每次分叉都会把 main 主干
        // 推向一侧。非零泳道按 1 左、2 右、3 左……稳定展开。
        let treeSlotByHash = Dictionary(
            uniqueKeysWithValues: newestFirst.map {
                ($0.commit.fullHash, treeBranchSlot($0.lane))
            }
        )
        let maximumDistance = treeSlotByHash.values.map { abs($0) }.max() ?? 0
        let sideExtent = Double(maximumDistance) * horizontalSpacing
        let contentWidth = max(1_040, sideExtent * 2 + 300)
        let trunkCenterX = contentWidth / 2
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
                x: trunkCenterX
                    + Double(treeSlotByHash[commit.fullHash, default: 0])
                        * horizontalSpacing,
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
        let routeHintsByEdgeID = makeRouteHints(
            nodes: nodes,
            edges: edges,
            depthByHash: depthByHash
        )
        let maximumDepth = depthByHash.values.max() ?? 0
        return CommitGraphLayoutResult(
            nodes: nodes,
            edges: edges,
            shallowBoundaryEndpoints: shallowBoundaryEndpoints,
            contentWidth: contentWidth,
            contentHeight: max(
                680,
                164 + Double(maximumDepth) * verticalSpacing
            ),
            routeHintsByEdgeID: routeHintsByEdgeID
        )
    }

    private func makeRouteHints(
        nodes: [CommitGraphNode],
        edges: [CommitGraphEdge],
        depthByHash: [String: Int]
    ) -> [String: CommitGraphRouteHint] {
        let nodesByHash = Dictionary(
            nodes.map { ($0.hash, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let nodesByDepth = Dictionary(
            grouping: nodes,
            by: { depthByHash[$0.hash, default: 0] }
        )
        let router = CommitGraphOrganizationRouter()
        var result: [String: CommitGraphRouteHint] = [:]
        result.reserveCapacity(edges.count)

        for (index, edge) in edges.enumerated() {
            guard let child = nodesByHash[edge.childHash],
                  let parent = nodesByHash[edge.parentHash]
            else { continue }
            let sourceRect = CommitGraphSceneGeometry.nodeRect(
                center: GraphPoint(x: child.x, y: child.y)
            )
            let targetRect = CommitGraphSceneGeometry.nodeRect(
                center: GraphPoint(x: parent.x, y: parent.y)
            )
            let ports = CommitGraphPortAllocator.ports(
                sourceRect: sourceRect,
                targetRect: targetRect
            )
            let firstDepth = min(
                depthByHash[edge.childHash, default: 0],
                depthByHash[edge.parentHash, default: 0]
            )
            let lastDepth = max(
                depthByHash[edge.childHash, default: 0],
                depthByHash[edge.parentHash, default: 0]
            )
            let corridor = GraphRect(
                x: min(sourceRect.minimumX, targetRect.minimumX) - 56,
                y: min(sourceRect.minimumY, targetRect.minimumY) - 56,
                width: abs(sourceRect.midpointX - targetRect.midpointX)
                    + CommitGraphSceneGeometry.nodeWidth + 112,
                height: abs(sourceRect.midpointY - targetRect.midpointY)
                    + CommitGraphSceneGeometry.nodeHeight + 112
            )
            var obstacles: [GraphRect] = []
            if firstDepth <= lastDepth {
                for depth in firstDepth...lastDepth {
                    for node in nodesByDepth[depth, default: []]
                        where node.hash != edge.childHash
                            && node.hash != edge.parentHash {
                        let rect = CommitGraphSceneGeometry.nodeRect(
                            center: GraphPoint(x: node.x, y: node.y)
                        )
                        if intersects(rect, corridor) {
                            obstacles.append(rect)
                        }
                    }
                }
            }
            let waypoints = router.route(
                sourceRect: sourceRect,
                targetRect: targetRect,
                sourceAnchor: ports.source,
                targetAnchor: ports.target,
                obstacles: obstacles,
                preferredChannel: edge.kind == .merge ? index % 7 + 1 : 0
            )
            result[edge.id] = CommitGraphRouteHint(
                edgeID: edge.id,
                ports: ports,
                waypoints: waypoints
            )
        }
        return result
    }

    private func intersects(_ first: GraphRect, _ second: GraphRect) -> Bool {
        first.maximumX >= second.minimumX
            && first.minimumX <= second.maximumX
            && first.maximumY >= second.minimumY
            && first.minimumY <= second.maximumY
    }

    private func treeBranchSlot(_ column: Int) -> Int {
        guard column > 0 else { return 0 }
        let distance = (column + 1) / 2
        return column.isMultiple(of: 2) ? distance : -distance
    }
}
