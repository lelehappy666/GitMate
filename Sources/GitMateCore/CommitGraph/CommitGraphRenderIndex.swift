import Foundation

public struct CommitGraphVisibleScene: Equatable, Sendable {
    public let nodes: [CommitGraphVisibleNode]
    public let groups: [CommitGraphVisibleGroup]
    public let regions: [CommitGraphRegionMarker]
    public let shallowBoundaryEndpoints:
        [CommitGraphVisibleShallowBoundaryEndpoint]
    public let edges: [CommitGraphVisibleEdge]

    public init(
        nodes: [CommitGraphVisibleNode],
        groups: [CommitGraphVisibleGroup],
        regions: [CommitGraphRegionMarker] = [],
        shallowBoundaryEndpoints:
            [CommitGraphVisibleShallowBoundaryEndpoint] = [],
        edges: [CommitGraphVisibleEdge]
    ) {
        self.nodes = nodes
        self.groups = groups
        self.regions = regions
        self.shallowBoundaryEndpoints = shallowBoundaryEndpoints
        self.edges = edges
    }
}

public struct CommitGraphRenderUpdate: Equatable, Sendable {
    public let updatedNodeHashes: [String]
    public let updatedGroupIDs: [UUID]
    public let updatedEdgeIDs: [String]

    public init(
        updatedNodeHashes: [String],
        updatedGroupIDs: [UUID] = [],
        updatedEdgeIDs: [String]
    ) {
        self.updatedNodeHashes = updatedNodeHashes
        self.updatedGroupIDs = updatedGroupIDs
        self.updatedEdgeIDs = updatedEdgeIDs
    }

    public static let empty = CommitGraphRenderUpdate(
        updatedNodeHashes: [],
        updatedGroupIDs: [],
        updatedEdgeIDs: []
    )
}

public struct CommitGraphRenderQueryDiagnostics: Equatable, Sendable {
    public let visitedBuckets: Int
    public let nodeCandidates: Int
    public let groupCandidates: Int
    public let edgeCandidates: Int
    public let generatedEdgeGeometries: Int

    public init(
        visitedBuckets: Int,
        nodeCandidates: Int,
        groupCandidates: Int,
        edgeCandidates: Int,
        generatedEdgeGeometries: Int = 0
    ) {
        self.visitedBuckets = visitedBuckets
        self.nodeCandidates = nodeCandidates
        self.groupCandidates = groupCandidates
        self.edgeCandidates = edgeCandidates
        self.generatedEdgeGeometries = generatedEdgeGeometries
    }
}

public struct CommitGraphLineStyleUpdate: Equatable, Sendable {
    public let didChange: Bool
    public let processedEdgeCount: Int

    public init(didChange: Bool, processedEdgeCount: Int) {
        self.didChange = didChange
        self.processedEdgeCount = processedEdgeCount
    }
}

public struct CommitGraphRenderQueryResult: Equatable, Sendable {
    public let scene: CommitGraphVisibleScene
    public let diagnostics: CommitGraphRenderQueryDiagnostics

    public init(
        scene: CommitGraphVisibleScene,
        diagnostics: CommitGraphRenderQueryDiagnostics
    ) {
        self.scene = scene
        self.diagnostics = diagnostics
    }
}

public enum CommitGraphRenderHit: Equatable, Sendable {
    case node(String)
    case group(id: UUID, isCollapsed: Bool)
}

public struct CommitGraphRenderIndex: Sendable {
    private var nodes: [CommitGraphVisibleNode]
    private var groups: [CommitGraphVisibleGroup]
    private var regions: [CommitGraphRegionMarker]
    private var shallowBoundaryEndpointsByID:
        [String: CommitGraphVisibleShallowBoundaryEndpoint]
    private let shallowBoundaryEndpointIDs: [String]
    private let shallowBoundaryEndpointIndexByID: [String: Int]
    private let shallowBoundaryIDsByChildHash: [String: [String]]
    private let shallowBoundaryIDsByGroupID: [UUID: [String]]
    private var edges: [CommitGraphVisibleEdge]
    private var lineStyle: CommitGraphLineStyle
    private let nodeIndexByHash: [String: Int]
    private let groupIndexByID: [UUID: Int]
    private let groupIndexByMemberHash: [String: Int]
    private let incidentEdgeIndices: [CommitGraphEndpointID: [Int]]
    private let edgeIndicesByCommitHash: [String: [Int]]
    private let commitHashesByEdgeIndex: [Int: Set<String>]
    private var endpointRects: [CommitGraphEndpointID: GraphRect]
    private var edgeCandidates: [Int: RenderEdgeCandidate]
    private var nodeGrid: RenderSpatialGrid
    private var groupGrid: RenderSpatialGrid
    private var regionGrid: RenderSpatialGrid
    private var shallowBoundaryGrid: RenderSpatialGrid
    private var edgeGrid: RenderSpatialGrid

    public init(projection: CommitGraphSceneProjection) {
        nodes = projection.nodes
        groups = projection.groups
        regions = projection.regions
        shallowBoundaryEndpointIDs = projection.shallowBoundaryEndpoints
            .map(\.id)
        shallowBoundaryEndpointsByID = Dictionary(
            projection.shallowBoundaryEndpoints.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        shallowBoundaryEndpointIndexByID = Dictionary(
            shallowBoundaryEndpointIDs.enumerated().map {
                ($0.element, $0.offset)
            },
            uniquingKeysWith: { first, _ in first }
        )
        shallowBoundaryIDsByChildHash = Dictionary(
            grouping: projection.shallowBoundaryEndpoints,
            by: { $0.endpoint.childHash }
        ).mapValues { $0.map(\.id) }
        edges = projection.edges
        lineStyle = projection.lineStyle
        nodeIndexByHash = Dictionary(
            projection.nodes.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        groupIndexByID = Dictionary(
            projection.groups.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        let builtGroupIndexByMemberHash = Dictionary(
            projection.groups.enumerated().flatMap { index, group in
                group.memberHashes.map { ($0, index) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        groupIndexByMemberHash = builtGroupIndexByMemberHash
        var builtBoundaryIDsByGroupID: [UUID: [String]] = [:]
        for endpoint in projection.shallowBoundaryEndpoints {
            guard let groupIndex = builtGroupIndexByMemberHash[
                endpoint.endpoint.childHash
            ] else {
                continue
            }
            builtBoundaryIDsByGroupID[
                projection.groups[groupIndex].id,
                default: []
            ].append(endpoint.id)
        }
        shallowBoundaryIDsByGroupID = builtBoundaryIDsByGroupID
        endpointRects = CommitGraphSceneProjector.endpointRects(
            in: projection
        )

        var adjacency: [CommitGraphEndpointID: [Int]] = [:]
        var edgesByCommitHash: [String: [Int]] = [:]
        var hashesByEdgeIndex: [Int: Set<String>] = [:]
        var candidates: [Int: RenderEdgeCandidate] = [:]
        var builtEdgeGrid = RenderSpatialGrid()
        for (index, edge) in projection.edges.enumerated() {
            adjacency[edge.source, default: []].append(index)
            adjacency[edge.target, default: []].append(index)
            let commitHashes = Self.commitHashes(for: edge)
            hashesByEdgeIndex[index] = commitHashes
            for hash in commitHashes {
                edgesByCommitHash[hash, default: []].append(index)
            }
            guard let candidate = Self.candidate(
                for: edge,
                endpointRects: endpointRects
            ) else {
                continue
            }
            candidates[index] = candidate
            builtEdgeGrid.replace(
                item: index,
                cells: candidate.indexCells
            )
        }
        incidentEdgeIndices = adjacency.mapValues {
            Array(Set($0)).sorted()
        }
        edgeIndicesByCommitHash = edgesByCommitHash.mapValues {
            Array(Set($0)).sorted()
        }
        commitHashesByEdgeIndex = hashesByEdgeIndex
        edgeCandidates = candidates
        edgeGrid = builtEdgeGrid

        var builtNodeGrid = RenderSpatialGrid()
        for (index, node) in projection.nodes.enumerated() {
            builtNodeGrid.replace(
                item: index,
                rect: CommitGraphSceneGeometry.nodeRect(
                    center: node.position
                )
            )
        }
        nodeGrid = builtNodeGrid

        var builtShallowBoundaryGrid = RenderSpatialGrid()
        for (index, endpoint) in projection.shallowBoundaryEndpoints.enumerated() {
            builtShallowBoundaryGrid.replace(
                item: index,
                rect: Self.shallowBoundaryRect(for: endpoint)
            )
        }
        shallowBoundaryGrid = builtShallowBoundaryGrid

        var builtGroupGrid = RenderSpatialGrid()
        for (index, group) in projection.groups.enumerated() {
            builtGroupGrid.replace(item: index, rect: group.rect)
        }
        groupGrid = builtGroupGrid

        var builtRegionGrid = RenderSpatialGrid()
        for (index, region) in projection.regions.enumerated() {
            builtRegionGrid.replace(item: index, rect: region.rect)
        }
        regionGrid = builtRegionGrid

    }

    public func query(
        viewport: GraphViewport,
        screenSize: GraphSize,
        padding: Double = 180
    ) -> CommitGraphVisibleScene {
        queryWithDiagnostics(
            viewport: viewport,
            screenSize: screenSize,
            padding: padding
        ).scene
    }

    public func queryWithDiagnostics(
        viewport: GraphViewport,
        screenSize: GraphSize,
        padding: Double = 180
    ) -> CommitGraphRenderQueryResult {
        let bounds = Self.visibleCanvasRect(
            viewport: viewport,
            screenSize: screenSize,
            padding: padding
        )
        let nodeQuery = nodeGrid.candidates(in: bounds)
        let groupQuery = groupGrid.candidates(in: bounds)
        let regionQuery = regionGrid.candidates(in: bounds)
        let shallowBoundaryQuery = shallowBoundaryGrid.candidates(in: bounds)
        let edgeQuery = edgeGrid.candidates(in: bounds)
        let nodeIndices = nodeQuery.items
            .filter {
                CommitGraphSceneGeometry.nodeRect(
                    center: nodes[$0].position
                ).intersects(bounds)
            }
            .sorted()
        let groupIndices = groupQuery.items
            .filter { groups[$0].rect.intersects(bounds) }
            .sorted()
        var generatedEdgeGeometries = 0
        let visibleEdges = edgeQuery.items.sorted().compactMap { index
            -> CommitGraphVisibleEdge? in
            guard edgeCandidates[index] != nil,
                  let geometry = Self.geometry(
                    for: edges[index],
                    endpointRects: endpointRects,
                    lineStyle: lineStyle
                  )
            else {
                return nil
            }
            generatedEdgeGeometries += 1
            guard geometry.intersects(bounds) else { return nil }
            let edge = edges[index]
            return CommitGraphVisibleEdge(
                id: edge.id,
                source: edge.source,
                target: edge.target,
                kind: edge.kind,
                colorIndex: edge.colorIndex,
                ports: edge.ports,
                aggregateKey: edge.aggregateKey,
                aggregateCount: edge.aggregateCount,
                originalEdgeIDs: edge.originalEdgeIDs,
                path: geometry.generatedPath,
                routeHint: edge.routeHint,
                publicationState: edge.publicationState
            )
        }

        return CommitGraphRenderQueryResult(
            scene: CommitGraphVisibleScene(
                nodes: nodeIndices.map { nodes[$0] },
                groups: groupIndices.map { groups[$0] },
                regions: regionQuery.items.sorted()
                    .filter { regions[$0].rect.intersects(bounds) }
                    .map { regions[$0] },
                shallowBoundaryEndpoints: shallowBoundaryQuery.items.sorted()
                    .compactMap { index in
                        guard index < shallowBoundaryEndpointIDs.count else {
                            return nil
                        }
                        return shallowBoundaryEndpointsByID[
                            shallowBoundaryEndpointIDs[index]
                        ]
                    }
                    .filter {
                        Self.shallowBoundaryRect(for: $0).intersects(bounds)
                    },
                edges: visibleEdges
            ),
            diagnostics: CommitGraphRenderQueryDiagnostics(
                visitedBuckets: nodeQuery.visitedBuckets
                    + groupQuery.visitedBuckets
                    + regionQuery.visitedBuckets
                    + shallowBoundaryQuery.visitedBuckets
                    + edgeQuery.visitedBuckets,
                nodeCandidates: nodeQuery.items.count
                    + shallowBoundaryQuery.items.count,
                groupCandidates: groupQuery.items.count,
                edgeCandidates: edgeQuery.items.count,
                generatedEdgeGeometries: generatedEdgeGeometries
            )
        )
    }

    /// 仅查询指针所在空间网格桶，不回退遍历可见或完整投影。
    public func hitTest(canvasPoint point: GraphPoint) -> CommitGraphRenderHit? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let queryRect = GraphRect(
            x: point.x - 0.5,
            y: point.y - 0.5,
            width: 1,
            height: 1
        )
        let groupCandidates = groupGrid.candidates(in: queryRect).items
            .sorted(by: >)
        // Canvas 的顺序是展开 Group -> node -> 折叠 Group，
        // 因此命中必须按反向层级执行，且同层按投影
        // 索引倒序，保证重叠时点到用户看到的最上层。
        for index in groupCandidates where groups[index].isCollapsed {
            let group = groups[index]
            if group.rect.contains(point) {
                return .group(id: group.id, isCollapsed: true)
            }
        }

        let nodeCandidates = nodeGrid.candidates(in: queryRect).items
            .sorted(by: >)
        for index in nodeCandidates
            where CommitGraphSceneGeometry.nodeRect(
                center: nodes[index].position
            ).contains(point) {
            return .node(nodes[index].node.hash)
        }

        for index in groupCandidates where !groups[index].isCollapsed {
            let group = groups[index]
            guard group.rect.contains(point) else { continue }
            let isInDraggableArea = point.y <= group.rect.minimumY
                + CommitGraphSceneGeometry.groupHeaderHeight
            if isInDraggableArea {
                return .group(
                    id: group.id,
                    isCollapsed: false
                )
            }
        }
        return nil
    }

    public func highlightedEdgeIDs(for hash: String) -> Set<String> {
        Set((edgeIndicesByCommitHash[hash] ?? []).map { edges[$0].id })
    }

    public func highlightedNodeHashes(for hash: String) -> Set<String> {
        var result: Set<String> = [hash]
        for index in edgeIndicesByCommitHash[hash] ?? [] {
            result.formUnion(commitHashesByEdgeIndex[index] ?? [])
        }
        return result
    }

    public mutating func setLineStyle(
        _ newStyle: CommitGraphLineStyle
    ) -> CommitGraphLineStyleUpdate {
        let changed = lineStyle != newStyle
        lineStyle = newStyle
        return CommitGraphLineStyleUpdate(
            didChange: changed,
            processedEdgeCount: 0
        )
    }

    /// 只同步版本区域及其空间网格，不触碰提交、分组和连线索引。
    public mutating func syncRegions(
        _ updatedRegions: [CommitGraphRegionMarker]
    ) {
        regions = updatedRegions
        var updatedGrid = RenderSpatialGrid()
        for (index, region) in updatedRegions.enumerated() {
            updatedGrid.replace(item: index, rect: region.rect)
        }
        regionGrid = updatedGrid
    }

    public mutating func moveNode(
        hash: String,
        to position: GraphPoint
    ) -> CommitGraphRenderUpdate {
        guard position.x.isFinite,
              position.y.isFinite,
              let nodeIndex = nodeIndexByHash[hash],
              nodes[nodeIndex].position != position
        else {
            return .empty
        }

        let previousPosition = nodes[nodeIndex].position
        let previousRect = CommitGraphSceneGeometry.nodeRect(
            center: previousPosition
        )
        nodes[nodeIndex] = CommitGraphVisibleNode(
            node: nodes[nodeIndex].node,
            position: position,
            publicationState: nodes[nodeIndex].publicationState
        )
        let rect = CommitGraphSceneGeometry.nodeRect(center: position)
        endpointRects[.node(hash)] = rect
        nodeGrid.replace(item: nodeIndex, rect: rect)

        var updatedGroupIDs: [UUID] = []
        var affectedEdgeIndices = Set(
            incidentEdgeIndices[.node(hash)] ?? []
        )
        affectedEdgeIndices.formUnion(
            edgeIndicesIntersecting(
                Self.union(previousRect, rect).expanded(by: 28)
            )
        )
        affectedEdgeIndices.formUnion(
            moveShallowBoundaries(
                ids: shallowBoundaryIDsByChildHash[hash] ?? [],
                anchorFrom: previousPosition,
                anchorTo: position
            )
        )
        if let groupIndex = groupIndexByMemberHash[hash] {
            let group = groups[groupIndex]
            var relativePositions = group.relativePositions
            relativePositions[hash] = GraphPoint(
                x: position.x - group.origin.x,
                y: position.y - group.origin.y
            )
            let updated = Self.updatedGroup(
                group,
                origin: group.origin,
                relativePositions: relativePositions
            )
            groups[groupIndex] = updated
            groupGrid.replace(item: groupIndex, rect: updated.rect)
            endpointRects[.group(group.id)] = updated.rect
            updatedGroupIDs = [group.id]
            affectedEdgeIndices.formUnion(
                incidentEdgeIndices[.group(group.id)] ?? []
            )
        }
        let updatedEdges = affectedEdgeIndices.sorted()
        refreshRouteHints(updatedEdges)
        updateEdgeCandidates(updatedEdges)

        return CommitGraphRenderUpdate(
            updatedNodeHashes: [hash],
            updatedGroupIDs: updatedGroupIDs,
            updatedEdgeIDs: updatedEdges.map { edges[$0].id }
        )
    }

    public mutating func moveGroup(
        id: UUID,
        to origin: GraphPoint
    ) -> CommitGraphRenderUpdate {
        guard origin.x.isFinite,
              origin.y.isFinite,
              let groupIndex = groupIndexByID[id],
              groups[groupIndex].origin != origin
        else {
            return .empty
        }
        let group = groups[groupIndex]
        let previousRect = group.rect
        let updated = Self.updatedGroup(
            group,
            origin: origin,
            relativePositions: group.relativePositions
        )
        groups[groupIndex] = updated
        groupGrid.replace(item: groupIndex, rect: updated.rect)
        endpointRects[.group(id)] = updated.rect

        var updatedNodeHashes: [String] = []
        var affectedEdgeIndices = Set(incidentEdgeIndices[.group(id)] ?? [])
        affectedEdgeIndices.formUnion(
            edgeIndicesIntersecting(
                Self.union(previousRect, updated.rect).expanded(by: 28)
            )
        )
        affectedEdgeIndices.formUnion(
            moveShallowBoundaries(
                ids: shallowBoundaryIDsByGroupID[id] ?? [],
                anchorFrom: group.origin,
                anchorTo: origin
            )
        )
        for hash in group.memberHashes.sorted() {
            guard let nodeIndex = nodeIndexByHash[hash],
                  let relative = group.relativePositions[hash]
            else { continue }
            let newPosition = GraphPoint(
                x: origin.x + relative.x,
                y: origin.y + relative.y
            )
            nodes[nodeIndex] = CommitGraphVisibleNode(
                node: nodes[nodeIndex].node,
                position: newPosition,
                publicationState: nodes[nodeIndex].publicationState
            )
            let rect = CommitGraphSceneGeometry.nodeRect(center: newPosition)
            nodeGrid.replace(item: nodeIndex, rect: rect)
            endpointRects[.node(hash)] = rect
            affectedEdgeIndices.formUnion(
                incidentEdgeIndices[.node(hash)] ?? []
            )
            updatedNodeHashes.append(hash)
        }
        let updatedEdges = affectedEdgeIndices.sorted()
        refreshRouteHints(updatedEdges)
        updateEdgeCandidates(updatedEdges)
        return CommitGraphRenderUpdate(
            updatedNodeHashes: updatedNodeHashes,
            updatedGroupIDs: [id],
            updatedEdgeIDs: updatedEdges.map { edges[$0].id }
        )
    }

    private mutating func updateEdgeCandidates(_ indices: [Int]) {
        for edgeIndex in indices {
            guard let candidate = Self.candidate(
                for: edges[edgeIndex],
                endpointRects: endpointRects
            ) else {
                edgeCandidates.removeValue(forKey: edgeIndex)
                edgeGrid.remove(item: edgeIndex)
                continue
            }
            edgeCandidates[edgeIndex] = candidate
            edgeGrid.replace(item: edgeIndex, cells: candidate.indexCells)
        }
    }

    private func edgeIndicesIntersecting(_ rect: GraphRect) -> Set<Int> {
        Set(edgeGrid.candidates(in: rect).items.filter { edgeIndex in
            guard edges.indices.contains(edgeIndex),
                  let geometry = Self.geometry(
                    for: edges[edgeIndex],
                    endpointRects: endpointRects,
                    lineStyle: lineStyle
                  )
            else { return false }
            return geometry.intersects(rect)
        })
    }

    private mutating func refreshRouteHints(_ indices: [Int]) {
        let router = CommitGraphOrganizationRouter()
        for edgeIndex in indices {
            guard edges.indices.contains(edgeIndex) else { continue }
            let edge = edges[edgeIndex]
            guard let sourceRect = endpointRects[edge.source],
                  let targetRect = endpointRects[edge.target]
            else { continue }
            let corridor = Self.union(sourceRect, targetRect).expanded(by: 120)
            var obstacles: [GraphRect] = []
            for nodeIndex in nodeGrid.candidates(in: corridor).items {
                let node = nodes[nodeIndex]
                let endpoint = CommitGraphEndpointID.node(node.id)
                guard endpoint != edge.source, endpoint != edge.target else {
                    continue
                }
                obstacles.append(
                    CommitGraphSceneGeometry.nodeRect(center: node.position)
                )
            }
            let endpointNodeHashes: Set<String> = [edge.source, edge.target]
                .compactMap {
                    if case let .node(hash) = $0 { return hash }
                    return nil
                }
                .reduce(into: Set<String>()) { $0.insert($1) }
            for groupIndex in groupGrid.candidates(in: corridor).items {
                let group = groups[groupIndex]
                let endpoint = CommitGraphEndpointID.group(group.id)
                guard endpoint != edge.source,
                      endpoint != edge.target,
                      group.memberHashes.isDisjoint(with: endpointNodeHashes)
                else { continue }
                obstacles.append(group.rect)
            }
            guard edge.routeHint != nil || !obstacles.isEmpty else {
                continue
            }
            let hint = CommitGraphRouteHint(
                edgeID: edge.id,
                ports: edge.ports,
                waypoints: router.route(
                    sourceRect: sourceRect,
                    targetRect: targetRect,
                    sourceAnchor: edge.ports.source,
                    targetAnchor: edge.ports.target,
                    obstacles: obstacles,
                    preferredChannel: edgeIndex % 7
                )
            )
            edges[edgeIndex] = Self.replacingRouteHint(edge, with: hint)
        }
    }

    private static func replacingRouteHint(
        _ edge: CommitGraphVisibleEdge,
        with routeHint: CommitGraphRouteHint
    ) -> CommitGraphVisibleEdge {
        CommitGraphVisibleEdge(
            id: edge.id,
            source: edge.source,
            target: edge.target,
            kind: edge.kind,
            colorIndex: edge.colorIndex,
            ports: edge.ports,
            aggregateKey: edge.aggregateKey,
            aggregateCount: edge.aggregateCount,
            originalEdgeIDs: edge.originalEdgeIDs,
            path: edge.path,
            routeHint: routeHint,
            publicationState: edge.publicationState
        )
    }

    private mutating func moveShallowBoundaries(
        ids: [String],
        anchorFrom previousAnchor: GraphPoint,
        anchorTo updatedAnchor: GraphPoint
    ) -> Set<Int> {
        var affectedEdgeIndices: Set<Int> = []
        for id in ids {
            guard let endpoint = shallowBoundaryEndpointsByID[id],
                  let endpointIndex = shallowBoundaryEndpointIndexByID[id]
            else {
                continue
            }
            let position = CommitGraphSceneGeometry.shallowBoundaryPosition(
                originalPosition: endpoint.position,
                originalAnchor: previousAnchor,
                updatedAnchor: updatedAnchor
            )
            guard position != endpoint.position else { continue }
            let updated = CommitGraphVisibleShallowBoundaryEndpoint(
                endpoint: endpoint.endpoint,
                position: position
            )
            shallowBoundaryEndpointsByID[id] = updated
            let rect = Self.shallowBoundaryRect(for: updated)
            shallowBoundaryGrid.replace(item: endpointIndex, rect: rect)
            endpointRects[.shallowBoundary(id)] = rect
            affectedEdgeIndices.formUnion(
                incidentEdgeIndices[.shallowBoundary(id)] ?? []
            )
        }
        return affectedEdgeIndices
    }

    private static func candidate(
        for edge: CommitGraphVisibleEdge,
        endpointRects: [CommitGraphEndpointID: GraphRect]
    ) -> RenderEdgeCandidate? {
        guard let sourceRect = endpointRects[edge.source],
              let targetRect = endpointRects[edge.target]
        else {
            return nil
        }
        return RenderEdgeCandidate(
            sourceRect: sourceRect,
            targetRect: targetRect,
            ports: edge.ports,
            routeHint: edge.routeHint
        )
    }

    private static func shallowBoundaryRect(
        for endpoint: CommitGraphVisibleShallowBoundaryEndpoint
    ) -> GraphRect {
        CommitGraphSceneGeometry.shallowBoundaryRect(
            center: endpoint.position
        )
    }

    private static func commitHashes(
        for edge: CommitGraphVisibleEdge
    ) -> Set<String> {
        var result = Set<String>()
        if case let .node(hash) = edge.source { result.insert(hash) }
        if case let .node(hash) = edge.target { result.insert(hash) }
        for edgeID in edge.originalEdgeIDs {
            guard let arrow = edgeID.range(of: "->") else { continue }
            let child = String(edgeID[..<arrow.lowerBound])
            let parentStart = arrow.upperBound
            let parentEnd = edgeID[parentStart...].firstIndex(of: "#")
                ?? edgeID.endIndex
            let parent = String(edgeID[parentStart..<parentEnd])
            if !child.isEmpty { result.insert(child) }
            if !parent.isEmpty { result.insert(parent) }
        }
        return result
    }

    private static func geometry(
        for edge: CommitGraphVisibleEdge,
        endpointRects: [CommitGraphEndpointID: GraphRect],
        lineStyle: CommitGraphLineStyle
    ) -> RenderEdgeGeometry? {
        guard let sourceRect = endpointRects[edge.source],
              let targetRect = endpointRects[edge.target]
        else {
            return nil
        }
        let path: CommitGraphGeneratedPath
        if let hint = edge.routeHint, hint.ports == edge.ports {
            switch lineStyle {
            case .curve:
                path = CommitGraphPathGeometry.roundedCurve(
                    points: hint.waypoints
                )
            case .orthogonal:
                path = CommitGraphPathGeometry.orthogonal(
                    points: hint.waypoints
                )
            }
        } else {
            switch lineStyle {
            case .curve:
                path = CommitGraphPathGeometry.curve(
                    startRect: sourceRect,
                    startAnchor: edge.ports.source,
                    endRect: targetRect,
                    endAnchor: edge.ports.target
                )
            case .orthogonal:
                path = CommitGraphPathGeometry.orthogonal(
                    startRect: sourceRect,
                    startAnchor: edge.ports.source,
                    endRect: targetRect,
                    endAnchor: edge.ports.target
                )
            }
        }
        return RenderEdgeGeometry(
            endpointRects: [sourceRect, targetRect],
            path: path
        )
    }

    private static func updatedGroup(
        _ group: CommitGraphVisibleGroup,
        origin: GraphPoint,
        relativePositions: [String: GraphPoint]
    ) -> CommitGraphVisibleGroup {
        let rect: GraphRect
        if group.isCollapsed {
            rect = GraphRect(
                x: origin.x,
                y: origin.y,
                width: CommitGraphSceneGeometry.collapsedGroupWidth,
                height: CommitGraphSceneGeometry.collapsedGroupHeight
            )
        } else {
            rect = CommitGraphSceneGeometry.expandedGroupRect(
                origin: origin,
                relativePositions: relativePositions
            )
        }
        return CommitGraphVisibleGroup(
            id: group.id,
            title: group.title,
            rect: rect,
            memberCount: group.memberCount,
            isCollapsed: group.isCollapsed,
            origin: origin,
            memberHashes: group.memberHashes,
            relativePositions: relativePositions
        )
    }

    private static func visibleCanvasRect(
        viewport: GraphViewport,
        screenSize: GraphSize,
        padding: Double
    ) -> GraphRect {
        let width = screenSize.width.isFinite
            ? max(screenSize.width, 0)
            : 0
        let height = screenSize.height.isFinite
            ? max(screenSize.height, 0)
            : 0
        let safePadding = padding.isFinite ? max(padding, 0) : 0
        let topLeft = CommitGraphViewportProjector.canvasPoint(
            screenPoint: GraphPoint(x: -safePadding, y: -safePadding),
            viewport: viewport
        )
        let bottomRight = CommitGraphViewportProjector.canvasPoint(
            screenPoint: GraphPoint(
                x: width + safePadding,
                y: height + safePadding
            ),
            viewport: viewport
        )
        return GraphRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }

    private static func union(_ first: GraphRect, _ second: GraphRect) -> GraphRect {
        let minimumX = min(first.minimumX, second.minimumX)
        let minimumY = min(first.minimumY, second.minimumY)
        let maximumX = max(first.maximumX, second.maximumX)
        let maximumY = max(first.maximumY, second.maximumY)
        return GraphRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }
}

private struct RenderEdgeCandidate: Sendable {
    private static let preferredCellLimit = 16
    let indexCells: Set<RenderGridCell>?

    init(
        sourceRect: GraphRect,
        targetRect: GraphRect,
        ports: CommitGraphEdgePorts,
        routeHint: CommitGraphRouteHint? = nil
    ) {
        let curve: RenderIndexedPath
        let orthogonal: RenderIndexedPath
        if let routeHint, routeHint.ports == ports {
            curve = RenderIndexedPath(
                CommitGraphPathGeometry.roundedCurve(
                    points: routeHint.waypoints
                )
            )
            orthogonal = RenderIndexedPath(
                CommitGraphPathGeometry.orthogonal(
                    points: routeHint.waypoints
                )
            )
        } else {
            curve = RenderIndexedPath(
                CommitGraphPathGeometry.curve(
                    startRect: sourceRect,
                    startAnchor: ports.source,
                    endRect: targetRect,
                    endAnchor: ports.target
                )
            )
            orthogonal = RenderIndexedPath(
                CommitGraphPathGeometry.orthogonal(
                    startRect: sourceRect,
                    startAnchor: ports.source,
                    endRect: targetRect,
                    endAnchor: ports.target
                )
            )
        }
        for scale in RenderSpatialGrid.adaptiveScales {
            var cells = Set<RenderGridCell>()
            guard Self.append(
                rect: sourceRect,
                scale: scale,
                limit: Self.preferredCellLimit,
                to: &cells
            ), Self.append(
                rect: targetRect,
                scale: scale,
                limit: Self.preferredCellLimit,
                to: &cells
            ), Self.append(
                path: curve,
                scale: scale,
                limit: Self.preferredCellLimit,
                to: &cells
            ), Self.append(
                path: orthogonal,
                scale: scale,
                limit: Self.preferredCellLimit,
                to: &cells
            ) else { continue }
            indexCells = cells
            return
        }
        indexCells = nil
    }

    private static func append(
        rect: GraphRect,
        scale: RenderGridScale,
        limit: Int,
        to cells: inout Set<RenderGridCell>
    ) -> Bool {
        guard let rectCells = RenderSpatialGrid.cells(
            for: rect,
            scale: scale
        ) else { return false }
        cells.formUnion(rectCells)
        return cells.count <= limit
    }

    private static func append(
        path: RenderIndexedPath,
        scale: RenderGridScale,
        limit: Int,
        to cells: inout Set<RenderGridCell>
    ) -> Bool {
        guard let pathCells = path.indexCells(
            scale: scale,
            limit: limit
        ) else {
            return false
        }
        cells.formUnion(pathCells)
        return cells.count <= limit
    }
}

private struct RenderEdgeGeometry: Sendable {
    let endpointRects: [GraphRect]
    let generatedPath: CommitGraphGeneratedPath
    let path: RenderIndexedPath
    let indexCells: Set<RenderGridCell>?

    init(
        endpointRects: [GraphRect],
        path generatedPath: CommitGraphGeneratedPath
    ) {
        self.endpointRects = endpointRects
        self.generatedPath = generatedPath
        path = RenderIndexedPath(generatedPath)
        for level in 0..<64 {
            var cells = Set<RenderGridCell>()
            var exceededLimit = false
            for rect in endpointRects {
                guard let rectCells = RenderSpatialGrid.cells(
                    for: rect,
                    level: level
                ) else {
                    exceededLimit = true
                    break
                }
                cells.formUnion(rectCells)
            }
            if exceededLimit { continue }
            guard let pathCells = path.indexCells(level: level) else {
                continue
            }
            cells.formUnion(pathCells)
            if cells.count > RenderSpatialGrid.maximumCellsPerItem {
                continue
            }
            indexCells = cells
            return
        }
        indexCells = nil
    }

    func intersects(_ rect: GraphRect) -> Bool {
        endpointRects.contains { $0.intersects(rect) }
            || path.intersects(rect)
    }
}

private enum RenderIndexedPath: Sendable {
    case curve(RenderBezier)
    case orthogonal([RenderSegment])

    init(_ path: CommitGraphGeneratedPath) {
        switch path {
        case let .curve(start, control1, control2, end):
            self = .curve(
                RenderBezier(
                    start: start,
                    control1: control1,
                    control2: control2,
                    end: end
                )
            )
        case let .polyline(points), let .roundedPolyline(points, _):
            self = .orthogonal(
                zip(points, points.dropFirst()).map {
                    RenderSegment(start: $0.0, end: $0.1)
                }
            )
        }
    }

    func indexCells(level: Int) -> Set<RenderGridCell>? {
        indexCells(scale: RenderGridScale(xLevel: level, yLevel: level))
    }

    func indexCells(scale: RenderGridScale) -> Set<RenderGridCell>? {
        indexCells(
            scale: scale,
            limit: RenderSpatialGrid.maximumCellsPerItem
        )
    }

    func indexCells(
        scale: RenderGridScale,
        limit: Int
    ) -> Set<RenderGridCell>? {
        switch self {
        case let .curve(curve):
            return curve.conservativeIndexCells(
                scale: scale,
                limit: limit
            )
        case let .orthogonal(segments):
            var cells = Set<RenderGridCell>()
            for segment in segments {
                guard let segmentCells = RenderSpatialGrid.cells(
                    from: segment.start,
                    to: segment.end,
                    scale: scale,
                    limit: limit
                ) else {
                    return nil
                }
                cells.formUnion(segmentCells)
                if cells.count > limit {
                    return nil
                }
            }
            return cells
        }
    }

    func intersects(_ rect: GraphRect) -> Bool {
        switch self {
        case let .curve(curve):
            return curve.intersects(rect)
        case let .orthogonal(segments):
            return segments.contains { $0.intersects(rect) }
        }
    }

}

private struct RenderBezier: Sendable {
    let start: GraphPoint
    let control1: GraphPoint
    let control2: GraphPoint
    let end: GraphPoint

    var controlBounds: GraphRect {
        let xs = [start.x, control1.x, control2.x, end.x]
        let ys = [start.y, control1.y, control2.y, end.y]
        let minimumX = xs.min() ?? 0
        let maximumX = xs.max() ?? minimumX
        let minimumY = ys.min() ?? 0
        let maximumY = ys.max() ?? minimumY
        return GraphRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }

    func intersects(_ rect: GraphRect) -> Bool {
        intersects(rect, depth: 0)
    }

    func conservativeIndexCells(
        scale: RenderGridScale,
        limit: Int
    ) -> Set<RenderGridCell>? {
        var result = Set<RenderGridCell>()
        guard appendConservativeIndexCells(
            scale: scale,
            limit: limit,
            depth: 0,
            to: &result
        ) else { return nil }
        return result
    }

    private func appendConservativeIndexCells(
        scale: RenderGridScale,
        limit: Int,
        depth: Int,
        to result: inout Set<RenderGridCell>
    ) -> Bool {
        guard let boundsCells = RenderSpatialGrid.cells(
            for: controlBounds,
            scale: scale
        ) else {
            guard depth < 32 else { return false }
            let halves = split()
            return halves.0.appendConservativeIndexCells(
                scale: scale,
                limit: limit,
                depth: depth + 1,
                to: &result
            ) && halves.1.appendConservativeIndexCells(
                scale: scale,
                limit: limit,
                depth: depth + 1,
                to: &result
            )
        }
        if boundsCells.count <= 4 || depth >= 32 {
            result.formUnion(boundsCells)
            return result.count <= limit
        }
        let halves = split()
        return halves.0.appendConservativeIndexCells(
            scale: scale,
            limit: limit,
            depth: depth + 1,
            to: &result
        ) && halves.1.appendConservativeIndexCells(
            scale: scale,
            limit: limit,
            depth: depth + 1,
            to: &result
        )
    }

    private func intersects(_ rect: GraphRect, depth: Int) -> Bool {
        let bounds = controlBounds
        guard bounds.intersects(rect) else { return false }
        if rect.contains(start) || rect.contains(end) {
            return true
        }
        if depth >= 16 || isFlat(tolerance: 0.35) {
            return true
        }
        let halves = split()
        return halves.0.intersects(rect, depth: depth + 1)
            || halves.1.intersects(rect, depth: depth + 1)
    }

    private func isFlat(tolerance: Double) -> Bool {
        let baseline = hypot(end.x - start.x, end.y - start.y)
        if baseline <= tolerance {
            return max(
                hypot(control1.x - start.x, control1.y - start.y),
                hypot(control2.x - start.x, control2.y - start.y)
            ) <= tolerance
        }
        let firstDistance = abs(
            (end.y - start.y) * control1.x
                - (end.x - start.x) * control1.y
                + end.x * start.y
                - end.y * start.x
        ) / baseline
        let secondDistance = abs(
            (end.y - start.y) * control2.x
                - (end.x - start.x) * control2.y
                + end.x * start.y
                - end.y * start.x
        ) / baseline
        return max(firstDistance, secondDistance) <= tolerance
    }

    private func split() -> (RenderBezier, RenderBezier) {
        let first = midpoint(start, control1)
        let second = midpoint(control1, control2)
        let third = midpoint(control2, end)
        let leftControl2 = midpoint(first, second)
        let rightControl1 = midpoint(second, third)
        let center = midpoint(leftControl2, rightControl1)
        return (
            RenderBezier(
                start: start,
                control1: first,
                control2: leftControl2,
                end: center
            ),
            RenderBezier(
                start: center,
                control1: rightControl1,
                control2: third,
                end: end
            )
        )
    }

    private func midpoint(_ first: GraphPoint, _ second: GraphPoint) -> GraphPoint {
        GraphPoint(
            x: (first.x + second.x) / 2,
            y: (first.y + second.y) / 2
        )
    }
}

private struct RenderSegment: Sendable {
    let start: GraphPoint
    let end: GraphPoint

    func intersects(_ rect: GraphRect) -> Bool {
        guard start.x.isFinite,
              start.y.isFinite,
              end.x.isFinite,
              end.y.isFinite
        else {
            return false
        }
        if rect.contains(start) || rect.contains(end) {
            return true
        }
        let topLeft = GraphPoint(x: rect.minimumX, y: rect.minimumY)
        let topRight = GraphPoint(x: rect.maximumX, y: rect.minimumY)
        let bottomRight = GraphPoint(x: rect.maximumX, y: rect.maximumY)
        let bottomLeft = GraphPoint(x: rect.minimumX, y: rect.maximumY)
        return Self.intersects(start, end, topLeft, topRight)
            || Self.intersects(start, end, topRight, bottomRight)
            || Self.intersects(start, end, bottomRight, bottomLeft)
            || Self.intersects(start, end, bottomLeft, topLeft)
    }

    private static func intersects(
        _ firstStart: GraphPoint,
        _ firstEnd: GraphPoint,
        _ secondStart: GraphPoint,
        _ secondEnd: GraphPoint
    ) -> Bool {
        let firstA = orientation(firstStart, firstEnd, secondStart)
        let firstB = orientation(firstStart, firstEnd, secondEnd)
        let secondA = orientation(secondStart, secondEnd, firstStart)
        let secondB = orientation(secondStart, secondEnd, firstEnd)
        if firstA == 0 && onSegment(firstStart, secondStart, firstEnd) {
            return true
        }
        if firstB == 0 && onSegment(firstStart, secondEnd, firstEnd) {
            return true
        }
        if secondA == 0 && onSegment(secondStart, firstStart, secondEnd) {
            return true
        }
        if secondB == 0 && onSegment(secondStart, firstEnd, secondEnd) {
            return true
        }
        return firstA != firstB && secondA != secondB
    }

    private static func orientation(
        _ first: GraphPoint,
        _ second: GraphPoint,
        _ third: GraphPoint
    ) -> Int {
        let value = (second.y - first.y) * (third.x - second.x)
            - (second.x - first.x) * (third.y - second.y)
        if abs(value) <= 0.000_001 { return 0 }
        return value > 0 ? 1 : 2
    }

    private static func onSegment(
        _ first: GraphPoint,
        _ middle: GraphPoint,
        _ last: GraphPoint
    ) -> Bool {
        middle.x >= min(first.x, last.x)
            && middle.x <= max(first.x, last.x)
            && middle.y >= min(first.y, last.y)
            && middle.y <= max(first.y, last.y)
    }
}

private struct RenderGridScale: Hashable, Sendable {
    let xLevel: Int
    let yLevel: Int
}

private struct RenderGridCell: Hashable, Sendable {
    let scale: RenderGridScale
    let x: Int
    let y: Int
}

private struct RenderSpatialQuery: Sendable {
    let items: Set<Int>
    let visitedBuckets: Int
}

private indirect enum RenderTreap<Value: Sendable>: Sendable {
    case empty
    case node(
        key: Int,
        priority: UInt64,
        value: Value,
        left: RenderTreap<Value>,
        right: RenderTreap<Value>
    )

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    func value(for searchedKey: Int) -> Value? {
        switch self {
        case .empty:
            return nil
        case let .node(key, _, value, left, right):
            if searchedKey == key { return value }
            return searchedKey < key
                ? left.value(for: searchedKey)
                : right.value(for: searchedKey)
        }
    }

    func setting(_ newValue: Value, for newKey: Int) -> Self {
        switch self {
        case .empty:
            return .node(
                key: newKey,
                priority: Self.priority(for: newKey),
                value: newValue,
                left: .empty,
                right: .empty
            )
        case let .node(key, priority, value, left, right):
            if newKey == key {
                return .node(
                    key: key,
                    priority: priority,
                    value: newValue,
                    left: left,
                    right: right
                )
            }
            if newKey < key {
                let updatedLeft = left.setting(newValue, for: newKey)
                let updated = Self.node(
                    key: key,
                    priority: priority,
                    value: value,
                    left: updatedLeft,
                    right: right
                )
                if updatedLeft.rootPriority > priority {
                    return Self.rotatedRight(updated)
                }
                return updated
            }
            let updatedRight = right.setting(newValue, for: newKey)
            let updated = Self.node(
                key: key,
                priority: priority,
                value: value,
                left: left,
                right: updatedRight
            )
            if updatedRight.rootPriority > priority {
                return Self.rotatedLeft(updated)
            }
            return updated
        }
    }

    func removing(_ removedKey: Int) -> Self {
        switch self {
        case .empty:
            return .empty
        case let .node(key, priority, value, left, right):
            if removedKey == key {
                return Self.merged(left, right)
            }
            if removedKey < key {
                return .node(
                    key: key,
                    priority: priority,
                    value: value,
                    left: left.removing(removedKey),
                    right: right
                )
            }
            return .node(
                key: key,
                priority: priority,
                value: value,
                left: left,
                right: right.removing(removedKey)
            )
        }
    }

    func forEach(
        minimumKey: Int,
        maximumKey: Int,
        _ body: (Int, Value) -> Void
    ) {
        switch self {
        case .empty:
            return
        case let .node(key, _, value, left, right):
            if key > minimumKey {
                left.forEach(
                    minimumKey: minimumKey,
                    maximumKey: maximumKey,
                    body
                )
            }
            if key >= minimumKey, key <= maximumKey {
                body(key, value)
            }
            if key < maximumKey {
                right.forEach(
                    minimumKey: minimumKey,
                    maximumKey: maximumKey,
                    body
                )
            }
        }
    }

    private var rootPriority: UInt64 {
        if case let .node(_, priority, _, _, _) = self {
            return priority
        }
        return 0
    }

    private static func priority(for key: Int) -> UInt64 {
        var value = UInt64(bitPattern: Int64(truncatingIfNeeded: key))
            &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    private static func rotatedRight(_ tree: Self) -> Self {
        guard case let .node(
            key,
            priority,
            value,
            .node(leftKey, leftPriority, leftValue, leftLeft, leftRight),
            right
        ) = tree else { return tree }
        return .node(
            key: leftKey,
            priority: leftPriority,
            value: leftValue,
            left: leftLeft,
            right: .node(
                key: key,
                priority: priority,
                value: value,
                left: leftRight,
                right: right
            )
        )
    }

    private static func rotatedLeft(_ tree: Self) -> Self {
        guard case let .node(
            key,
            priority,
            value,
            left,
            .node(rightKey, rightPriority, rightValue, rightLeft, rightRight)
        ) = tree else { return tree }
        return .node(
            key: rightKey,
            priority: rightPriority,
            value: rightValue,
            left: .node(
                key: key,
                priority: priority,
                value: value,
                left: left,
                right: rightLeft
            ),
            right: rightRight
        )
    }

    private static func merged(_ left: Self, _ right: Self) -> Self {
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        if left.rootPriority > right.rootPriority {
            guard case let .node(
                key,
                priority,
                value,
                leftLeft,
                leftRight
            ) = left else { return right }
            return .node(
                key: key,
                priority: priority,
                value: value,
                left: leftLeft,
                right: merged(leftRight, right)
            )
        }
        guard case let .node(
            key,
            priority,
            value,
            rightLeft,
            rightRight
        ) = right else { return left }
        return .node(
            key: key,
            priority: priority,
            value: value,
            left: merged(left, rightLeft),
            right: rightRight
        )
    }
}

private struct RenderSpatialGrid: Sendable {
    static let baseCellSize = 512.0
    static let maximumCellsPerItem = 512

    private typealias ColumnTree = RenderTreap<Set<Int>>
    private typealias RowTree = RenderTreap<ColumnTree>

    private var levels: [RenderGridScale: RowTree] = [:]
    private var cellsByItem: [Int: Set<RenderGridCell>] = [:]

    mutating func replace(item: Int, rect: GraphRect) {
        replace(item: item, cells: Self.adaptiveCells(for: rect))
    }

    mutating func replace(
        item: Int,
        cells: Set<RenderGridCell>?
    ) {
        remove(item: item)
        guard let cells else { return }
        cellsByItem[item] = cells
        for cell in cells {
            var rows = levels[cell.scale] ?? .empty
            var columns = rows.value(for: cell.y) ?? .empty
            var items = columns.value(for: cell.x) ?? []
            items.insert(item)
            columns = columns.setting(items, for: cell.x)
            rows = rows.setting(columns, for: cell.y)
            levels[cell.scale] = rows
        }
    }

    mutating func remove(item: Int) {
        guard let cells = cellsByItem.removeValue(forKey: item) else {
            return
        }
        for cell in cells {
            guard var rows = levels[cell.scale],
                  var columns = rows.value(for: cell.y),
                  var items = columns.value(for: cell.x)
            else { continue }
            items.remove(item)
            columns = items.isEmpty
                ? columns.removing(cell.x)
                : columns.setting(items, for: cell.x)
            rows = columns.isEmpty
                ? rows.removing(cell.y)
                : rows.setting(columns, for: cell.y)
            if rows.isEmpty {
                levels.removeValue(forKey: cell.scale)
            } else {
                levels[cell.scale] = rows
            }
        }
    }

    func candidates(in rect: GraphRect) -> RenderSpatialQuery {
        var result = Set<Int>()
        var visitedBuckets = 0
        for (scale, rows) in levels {
            guard let range = Self.cellRange(for: rect, scale: scale) else {
                continue
            }
            rows.forEach(
                minimumKey: range.minimumY,
                maximumKey: range.maximumY
            ) { _, columns in
                columns.forEach(
                    minimumKey: range.minimumX,
                    maximumKey: range.maximumX
                ) { _, items in
                    visitedBuckets += 1
                    result.formUnion(items)
                }
            }
        }
        return RenderSpatialQuery(
            items: result,
            visitedBuckets: visitedBuckets
        )
    }

    static func cells(
        for rect: GraphRect,
        level: Int
    ) -> Set<RenderGridCell>? {
        cells(
            for: rect,
            scale: RenderGridScale(xLevel: level, yLevel: level)
        )
    }

    static func cells(
        for rect: GraphRect,
        scale: RenderGridScale
    ) -> Set<RenderGridCell>? {
        guard let range = cellRange(for: rect, scale: scale) else {
            return nil
        }
        guard let count = cellCount(for: range),
              count <= maximumCellsPerItem
        else {
            return nil
        }
        var result = Set<RenderGridCell>()
        result.reserveCapacity(count)
        for y in range.minimumY...range.maximumY {
            for x in range.minimumX...range.maximumX {
                result.insert(RenderGridCell(scale: scale, x: x, y: y))
            }
        }
        return result
    }

    static func cells(
        from start: GraphPoint,
        to end: GraphPoint,
        level: Int
    ) -> Set<RenderGridCell>? {
        cells(
            from: start,
            to: end,
            scale: RenderGridScale(xLevel: level, yLevel: level)
        )
    }

    static func cells(
        from start: GraphPoint,
        to end: GraphPoint,
        scale: RenderGridScale
    ) -> Set<RenderGridCell>? {
        cells(
            from: start,
            to: end,
            scale: scale,
            limit: maximumCellsPerItem
        )
    }

    static func cells(
        from start: GraphPoint,
        to end: GraphPoint,
        scale: RenderGridScale,
        limit: Int
    ) -> Set<RenderGridCell>? {
        let cellWidth = cellSize(for: scale.xLevel)
        let cellHeight = cellSize(for: scale.yLevel)
        guard start.x.isFinite,
              start.y.isFinite,
              end.x.isFinite,
              end.y.isFinite,
              let startCell = cell(for: start, scale: scale),
              let endCell = cell(for: end, scale: scale)
        else {
            return nil
        }
        var result: Set<RenderGridCell> = [startCell]
        if startCell == endCell { return result }

        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let stepX = deltaX > 0 ? 1 : (deltaX < 0 ? -1 : 0)
        let stepY = deltaY > 0 ? 1 : (deltaY < 0 ? -1 : 0)
        let tDeltaX = stepX == 0 ? .infinity : cellWidth / abs(deltaX)
        let tDeltaY = stepY == 0 ? .infinity : cellHeight / abs(deltaY)
        let nextX = stepX > 0
            ? Double(startCell.x + 1) * cellWidth
            : Double(startCell.x) * cellWidth
        let nextY = stepY > 0
            ? Double(startCell.y + 1) * cellHeight
            : Double(startCell.y) * cellHeight
        var tMaxX = stepX == 0 ? .infinity : (nextX - start.x) / deltaX
        var tMaxY = stepY == 0 ? .infinity : (nextY - start.y) / deltaY
        var current = startCell

        while current != endCell {
            if tMaxX < tMaxY {
                current = RenderGridCell(
                    scale: scale,
                    x: current.x + stepX,
                    y: current.y
                )
                tMaxX += tDeltaX
            } else if tMaxY < tMaxX {
                current = RenderGridCell(
                    scale: scale,
                    x: current.x,
                    y: current.y + stepY
                )
                tMaxY += tDeltaY
            } else {
                if stepX != 0 {
                    result.insert(
                        RenderGridCell(
                            scale: scale,
                            x: current.x + stepX,
                            y: current.y
                        )
                    )
                }
                if stepY != 0 {
                    result.insert(
                        RenderGridCell(
                            scale: scale,
                            x: current.x,
                            y: current.y + stepY
                        )
                    )
                }
                current = RenderGridCell(
                    scale: scale,
                    x: current.x + stepX,
                    y: current.y + stepY
                )
                tMaxX += tDeltaX
                tMaxY += tDeltaY
            }
            result.insert(current)
            if result.count > min(limit, maximumCellsPerItem) {
                return nil
            }
        }
        return result
    }

    private static func cellRange(
        for rect: GraphRect,
        level: Int
    ) -> (
        minimumX: Int,
        maximumX: Int,
        minimumY: Int,
        maximumY: Int
    )? {
        cellRange(
            for: rect,
            scale: RenderGridScale(xLevel: level, yLevel: level)
        )
    }

    private static func cellRange(
        for rect: GraphRect,
        scale: RenderGridScale
    ) -> (
        minimumX: Int,
        maximumX: Int,
        minimumY: Int,
        maximumY: Int
    )? {
        guard rect.minimumX.isFinite,
              rect.minimumY.isFinite,
              rect.maximumX.isFinite,
              rect.maximumY.isFinite,
              let minimum = cell(
                for: GraphPoint(x: rect.minimumX, y: rect.minimumY),
                scale: scale
              ),
              let maximum = cell(
                for: GraphPoint(x: rect.maximumX, y: rect.maximumY),
                scale: scale
              )
        else {
            return nil
        }
        return (
            min(minimum.x, maximum.x),
            max(minimum.x, maximum.x),
            min(minimum.y, maximum.y),
            max(minimum.y, maximum.y)
        )
    }

    private static func adaptiveCells(
        for rect: GraphRect
    ) -> Set<RenderGridCell>? {
        for level in 0..<64 {
            if let result = cells(for: rect, level: level) {
                return result
            }
        }
        return nil
    }

    static let adaptiveScales: [RenderGridScale] = {
        var result: [RenderGridScale] = []
        result.reserveCapacity(4_096)
        for total in 0...126 {
            let minimumXLevel = max(0, total - 63)
            let maximumXLevel = min(63, total)
            for xLevel in minimumXLevel...maximumXLevel {
                result.append(
                    RenderGridScale(
                        xLevel: xLevel,
                        yLevel: total - xLevel
                    )
                )
            }
        }
        return result
    }()

    private static func cellCount(
        for range: (
            minimumX: Int,
            maximumX: Int,
            minimumY: Int,
            maximumY: Int
        )
    ) -> Int? {
        let widthDifference = range.maximumX.subtractingReportingOverflow(
            range.minimumX
        )
        let heightDifference = range.maximumY.subtractingReportingOverflow(
            range.minimumY
        )
        guard !widthDifference.overflow,
              !heightDifference.overflow
        else {
            return nil
        }
        let width = widthDifference.partialValue.addingReportingOverflow(1)
        let height = heightDifference.partialValue.addingReportingOverflow(1)
        guard !width.overflow,
              !height.overflow
        else {
            return nil
        }
        let count = width.partialValue.multipliedReportingOverflow(
            by: height.partialValue
        )
        return count.overflow ? nil : count.partialValue
    }

    private static func cellSize(for level: Int) -> Double {
        baseCellSize * pow(2, Double(max(level, 0)))
    }

    private static func cell(
        for point: GraphPoint,
        level: Int
    ) -> RenderGridCell? {
        cell(
            for: point,
            scale: RenderGridScale(xLevel: level, yLevel: level)
        )
    }

    private static func cell(
        for point: GraphPoint,
        scale: RenderGridScale
    ) -> RenderGridCell? {
        let x = floor(point.x / cellSize(for: scale.xLevel))
        let y = floor(point.y / cellSize(for: scale.yLevel))
        guard x.isFinite,
              y.isFinite,
              x >= Double(Int.min),
              x <= Double(Int.max),
              y >= Double(Int.min),
              y <= Double(Int.max)
        else {
            return nil
        }
        return RenderGridCell(scale: scale, x: Int(x), y: Int(y))
    }
}

private extension GraphRect {
    func expanded(by padding: Double) -> GraphRect {
        GraphRect(
            x: x - padding,
            y: y - padding,
            width: width + padding * 2,
            height: height + padding * 2
        )
    }

    func intersects(_ other: GraphRect) -> Bool {
        maximumX >= other.minimumX
            && minimumX <= other.maximumX
            && maximumY >= other.minimumY
            && minimumY <= other.maximumY
    }

    func contains(_ point: GraphPoint) -> Bool {
        point.x >= minimumX
            && point.x <= maximumX
            && point.y >= minimumY
            && point.y <= maximumY
    }
}
