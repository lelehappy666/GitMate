import Foundation

public enum CommitGraphSceneProjector {
    public static func project(
        layout: CommitGraphLayoutResult,
        scene: CommitGraphSceneState
    ) -> CommitGraphSceneProjection {
        let membership = Dictionary(
            scene.groups.flatMap { group in
                group.memberHashes.map { ($0, group.id) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let groupsByID = Dictionary(
            uniqueKeysWithValues: scene.groups.map { ($0.id, $0) }
        )
        let collapsedGroupIDs = Set(
            scene.groups.filter(\.isCollapsed).map(\.id)
        )

        let visibleNodes: [CommitGraphVisibleNode] = layout.nodes.compactMap {
            node -> CommitGraphVisibleNode? in
            if let groupID = membership[node.hash],
               collapsedGroupIDs.contains(groupID) {
                return nil
            }
            let position: GraphPoint
            if let groupID = membership[node.hash],
               let group = groupsByID[groupID],
               let groupPosition = group.absolutePosition(for: node.hash) {
                position = groupPosition
            } else {
                position = scene.nodePositions[node.hash]
                    ?? GraphPoint(x: node.x, y: node.y)
            }
            return CommitGraphVisibleNode(node: node, position: position)
        }

        let visibleGroups = scene.groups.map { group in
            CommitGraphVisibleGroup(
                id: group.id,
                title: group.title,
                rect: group.isCollapsed
                    ? CommitGraphSceneGeometry.collapsedGroupRect(group)
                    : CommitGraphSceneGeometry.expandedGroupRect(group),
                memberCount: group.memberHashes.count,
                isCollapsed: group.isCollapsed,
                origin: group.origin,
                memberHashes: group.memberHashes,
                relativePositions: group.relativePositions
            )
        }

        let visibleNodesByHash = Dictionary(
            uniqueKeysWithValues: visibleNodes.map { ($0.node.hash, $0) }
        )
        let visibleShallowBoundaryEndpoints = layout.shallowBoundaryEndpoints
            .compactMap {
                endpoint -> CommitGraphVisibleShallowBoundaryEndpoint? in
                guard let child = visibleNodesByHash[endpoint.childHash],
                      let laidOutChild = layout.node(hash: endpoint.childHash)
                else {
                    return nil
                }
                return CommitGraphVisibleShallowBoundaryEndpoint(
                    endpoint: endpoint,
                    position: GraphPoint(
                        x: child.position.x + endpoint.x - laidOutChild.x,
                        y: child.position.y + endpoint.y - laidOutChild.y
                    )
                )
            }

        var ordinaryEdges: [CommitGraphVisibleEdge] = []
        var aggregateEdges:
            [CollapsedEdgeKey: AggregateAccumulator] = [:]

        for edge in layout.edges {
            let childGroupID = membership[edge.childHash]
            let parentGroupID = membership[edge.parentHash]
            let childCollapsed = childGroupID.map(
                collapsedGroupIDs.contains
            ) ?? false
            let parentCollapsed = parentGroupID.map(
                collapsedGroupIDs.contains
            ) ?? false

            if childCollapsed,
               parentCollapsed,
               childGroupID == parentGroupID {
                continue
            }

            if childCollapsed || parentCollapsed {
                guard let aggregate = aggregateDescriptor(
                    edge: edge,
                    childGroupID: childGroupID,
                    parentGroupID: parentGroupID,
                    childCollapsed: childCollapsed,
                    parentCollapsed: parentCollapsed,
                    scene: scene
                ) else {
                    continue
                }
                if var existing = aggregateEdges[aggregate.key] {
                    existing.originalEdgeIDs.append(edge.id)
                    if edge.kind == .merge {
                        existing.kind = .merge
                    }
                    aggregateEdges[aggregate.key] = existing
                } else {
                    aggregateEdges[aggregate.key] = AggregateAccumulator(
                        source: aggregate.source,
                        target: aggregate.target,
                        kind: edge.kind,
                        colorIndex: edge.colorIndex,
                        ports: aggregate.ports,
                        originalEdgeIDs: [edge.id]
                    )
                }
                continue
            }

            let source = CommitGraphEndpointID.node(edge.childHash)
            let target = CommitGraphEndpointID.node(edge.parentHash)
            ordinaryEdges.append(
                CommitGraphVisibleEdge(
                    id: edge.id,
                    source: source,
                    target: target,
                    kind: edge.kind,
                    colorIndex: edge.colorIndex,
                    ports: scene.edgePorts[edge.id]
                        ?? defaultPorts(
                            edge: edge,
                            layout: layout,
                            scene: scene
                        ),
                    aggregateKey: nil,
                    aggregateCount: 1,
                    originalEdgeIDs: [edge.id]
                )
            )
        }

        for endpoint in visibleShallowBoundaryEndpoints {
            ordinaryEdges.append(
                CommitGraphVisibleEdge(
                    id: "shallow:\(endpoint.id)",
                    source: .node(endpoint.endpoint.childHash),
                    target: .shallowBoundary(endpoint.id),
                    kind: .shallowBoundary,
                    colorIndex: endpoint.endpoint.colorIndex,
                    ports: CommitGraphEdgePorts(
                        source: PortAnchor(side: .top, offset: 0.5),
                        target: PortAnchor(side: .bottom, offset: 0.5)
                    ),
                    aggregateKey: nil,
                    aggregateCount: 1,
                    originalEdgeIDs: [endpoint.id]
                )
            )
        }

        let collapsedEdges = aggregateEdges
            .sorted { edgeKey($0.key) < edgeKey($1.key) }
            .map { key, accumulator in
                CommitGraphVisibleEdge(
                    id: "aggregate:\(edgeKey(key))",
                    source: accumulator.source,
                    target: accumulator.target,
                    kind: accumulator.kind,
                    colorIndex: accumulator.colorIndex,
                    ports: accumulator.ports,
                    aggregateKey: key,
                    aggregateCount: accumulator.originalEdgeIDs.count,
                    originalEdgeIDs: accumulator.originalEdgeIDs
                )
            }

        return CommitGraphSceneProjection(
            nodes: visibleNodes,
            groups: visibleGroups,
            regions: scene.regions,
            shallowBoundaryEndpoints: visibleShallowBoundaryEndpoints,
            edges: ordinaryEdges + collapsedEdges,
            lineStyle: scene.lineStyle
        )
    }

    private struct AggregateDescriptor {
        let key: CollapsedEdgeKey
        let source: CommitGraphEndpointID
        let target: CommitGraphEndpointID
        let ports: CommitGraphEdgePorts
    }

    private struct AggregateAccumulator {
        let source: CommitGraphEndpointID
        let target: CommitGraphEndpointID
        var kind: CommitGraphEdgeKind
        let colorIndex: Int
        let ports: CommitGraphEdgePorts
        var originalEdgeIDs: [String]
    }

    private static func aggregateDescriptor(
        edge: CommitGraphEdge,
        childGroupID: UUID?,
        parentGroupID: UUID?,
        childCollapsed: Bool,
        parentCollapsed: Bool,
        scene: CommitGraphSceneState
    ) -> AggregateDescriptor? {
        let key: CollapsedEdgeKey
        let source: CommitGraphEndpointID
        let target: CommitGraphEndpointID

        if childCollapsed,
           parentCollapsed,
           let childGroupID,
           let parentGroupID {
            key = CollapsedEdgeKey(
                groupID: childGroupID,
                externalNodeID: "group:\(parentGroupID.uuidString)",
                direction: .leavingGroup
            )
            source = .group(childGroupID)
            target = .group(parentGroupID)
        } else if childCollapsed, let childGroupID {
            key = CollapsedEdgeKey(
                groupID: childGroupID,
                externalNodeID: edge.parentHash,
                direction: .leavingGroup
            )
            source = .group(childGroupID)
            target = .node(edge.parentHash)
        } else if parentCollapsed, let parentGroupID {
            key = CollapsedEdgeKey(
                groupID: parentGroupID,
                externalNodeID: edge.childHash,
                direction: .enteringGroup
            )
            source = .node(edge.childHash)
            target = .group(parentGroupID)
        } else {
            return nil
        }

        guard let ports = scene.boundaryPorts[key] else {
            return nil
        }
        return AggregateDescriptor(
            key: key,
            source: source,
            target: target,
            ports: ports
        )
    }

    private static func defaultPorts(
        edge: CommitGraphEdge,
        layout: CommitGraphLayoutResult,
        scene: CommitGraphSceneState
    ) -> CommitGraphEdgePorts {
        guard let child = position(
            hash: edge.childHash,
            layout: layout,
            scene: scene
        ),
        let parent = position(
            hash: edge.parentHash,
            layout: layout,
            scene: scene
        ) else {
            return CommitGraphEdgePorts(
                source: PortAnchor(side: .top, offset: 0.5),
                target: PortAnchor(side: .bottom, offset: 0.5)
            )
        }
        return CommitGraphPortAllocator.ports(
            sourceRect: CommitGraphSceneGeometry.nodeRect(center: child),
            targetRect: CommitGraphSceneGeometry.nodeRect(center: parent)
        )
    }

    private static func position(
        hash: String,
        layout: CommitGraphLayoutResult,
        scene: CommitGraphSceneState
    ) -> GraphPoint? {
        if let group = scene.groups.first(
            where: { $0.memberHashes.contains(hash) }
        ) {
            return group.absolutePosition(for: hash)
        }
        return scene.nodePositions[hash] ?? layout.node(hash: hash).map {
            GraphPoint(x: $0.x, y: $0.y)
        }
    }

    private static func edgeKey(_ key: CollapsedEdgeKey) -> String {
        [
            key.groupID.uuidString,
            key.externalNodeID,
            key.direction.rawValue
        ].joined(separator: "|")
    }

    static func endpointRects(
        in projection: CommitGraphSceneProjection
    ) -> [CommitGraphEndpointID: GraphRect] {
        var result = Dictionary(
            uniqueKeysWithValues: projection.nodes.map {
                (
                    CommitGraphEndpointID.node($0.id),
                    CommitGraphSceneGeometry.nodeRect(center: $0.position)
                )
            }
        )
        for group in projection.groups {
            result[.group(group.id)] = group.rect
        }
        for endpoint in projection.shallowBoundaryEndpoints {
            result[.shallowBoundary(endpoint.id)] = GraphRect(
                x: endpoint.position.x - 80,
                y: endpoint.position.y - 18,
                width: 160,
                height: 36
            )
        }
        return result
    }
}
