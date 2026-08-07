import Foundation

public struct CommitGraphVisibleScene: Equatable, Sendable {
    public let nodes: [CommitGraphVisibleNode]
    public let groups: [CommitGraphVisibleGroup]
    public let edges: [CommitGraphVisibleEdge]

    public init(
        nodes: [CommitGraphVisibleNode],
        groups: [CommitGraphVisibleGroup],
        edges: [CommitGraphVisibleEdge]
    ) {
        self.nodes = nodes
        self.groups = groups
        self.edges = edges
    }
}

public struct CommitGraphRenderUpdate: Equatable, Sendable {
    public let updatedNodeHashes: [String]
    public let updatedEdgeIDs: [String]

    public init(
        updatedNodeHashes: [String],
        updatedEdgeIDs: [String]
    ) {
        self.updatedNodeHashes = updatedNodeHashes
        self.updatedEdgeIDs = updatedEdgeIDs
    }

    public static let empty = CommitGraphRenderUpdate(
        updatedNodeHashes: [],
        updatedEdgeIDs: []
    )
}

public struct CommitGraphRenderIndex: Sendable {
    private var nodes: [CommitGraphVisibleNode]
    private let groups: [CommitGraphVisibleGroup]
    private let edges: [CommitGraphVisibleEdge]
    private let nodeIndexByHash: [String: Int]
    private let incidentEdgeIndices: [String: [Int]]
    private var endpointRects: [CommitGraphEndpointID: GraphRect]
    private var edgeGeometry: [Int: RenderEdgeGeometry]
    private var nodeGrid: RenderSpatialGrid
    private let groupGrid: RenderSpatialGrid
    private var edgeGrid: RenderSpatialGrid

    public init(projection: CommitGraphSceneProjection) {
        nodes = projection.nodes
        groups = projection.groups
        edges = projection.edges
        nodeIndexByHash = Dictionary(
            projection.nodes.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        endpointRects = CommitGraphSceneProjector.endpointRects(
            in: projection
        )

        var adjacency: [String: [Int]] = [:]
        var geometries: [Int: RenderEdgeGeometry] = [:]
        var builtEdgeGrid = RenderSpatialGrid()
        for (index, edge) in projection.edges.enumerated() {
            if case let .node(hash) = edge.source {
                adjacency[hash, default: []].append(index)
            }
            if case let .node(hash) = edge.target {
                adjacency[hash, default: []].append(index)
            }
            guard let geometry = Self.geometry(
                for: edge,
                endpointRects: endpointRects
            ) else {
                continue
            }
            geometries[index] = geometry
            builtEdgeGrid.replace(
                item: index,
                cells: geometry.indexCells
            )
        }
        incidentEdgeIndices = adjacency.mapValues {
            Array(Set($0)).sorted()
        }
        edgeGeometry = geometries
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

        var builtGroupGrid = RenderSpatialGrid()
        for (index, group) in projection.groups.enumerated() {
            builtGroupGrid.replace(item: index, rect: group.rect)
        }
        groupGrid = builtGroupGrid
    }

    public func query(
        viewport: GraphViewport,
        screenSize: GraphSize,
        padding: Double = 180
    ) -> CommitGraphVisibleScene {
        let bounds = Self.visibleCanvasRect(
            viewport: viewport,
            screenSize: screenSize,
            padding: padding
        )
        let nodeIndices = nodeGrid.candidates(in: bounds)
            .filter {
                CommitGraphSceneGeometry.nodeRect(
                    center: nodes[$0].position
                ).intersects(bounds)
            }
            .sorted()
        let groupIndices = groupGrid.candidates(in: bounds)
            .filter { groups[$0].rect.intersects(bounds) }
            .sorted()
        let edgeIndices = edgeGrid.candidates(in: bounds)
            .filter { edgeGeometry[$0]?.intersects(bounds) == true }
            .sorted()

        return CommitGraphVisibleScene(
            nodes: nodeIndices.map { nodes[$0] },
            groups: groupIndices.map { groups[$0] },
            edges: edgeIndices.map { edges[$0] }
        )
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

        nodes[nodeIndex] = CommitGraphVisibleNode(
            node: nodes[nodeIndex].node,
            position: position
        )
        let rect = CommitGraphSceneGeometry.nodeRect(center: position)
        endpointRects[.node(hash)] = rect
        nodeGrid.replace(item: nodeIndex, rect: rect)

        let updatedEdges = incidentEdgeIndices[hash] ?? []
        for edgeIndex in updatedEdges {
            guard let geometry = Self.geometry(
                for: edges[edgeIndex],
                endpointRects: endpointRects
            ) else {
                edgeGeometry.removeValue(forKey: edgeIndex)
                edgeGrid.remove(item: edgeIndex)
                continue
            }
            edgeGeometry[edgeIndex] = geometry
            edgeGrid.replace(
                item: edgeIndex,
                cells: geometry.indexCells
            )
        }

        return CommitGraphRenderUpdate(
            updatedNodeHashes: [hash],
            updatedEdgeIDs: updatedEdges.map { edges[$0].id }
        )
    }

    private static func geometry(
        for edge: CommitGraphVisibleEdge,
        endpointRects: [CommitGraphEndpointID: GraphRect]
    ) -> RenderEdgeGeometry? {
        guard let sourceRect = endpointRects[edge.source],
              let targetRect = endpointRects[edge.target]
        else {
            return nil
        }
        let curve = CommitGraphPathGeometry.curve(
            startRect: sourceRect,
            startAnchor: edge.ports.source,
            endRect: targetRect,
            endAnchor: edge.ports.target
        )
        let orthogonal = CommitGraphPathGeometry.orthogonal(
            startRect: sourceRect,
            startAnchor: edge.ports.source,
            endRect: targetRect,
            endAnchor: edge.ports.target
        )
        return RenderEdgeGeometry(
            endpointRects: [sourceRect, targetRect],
            segments: RenderEdgeGeometry.segments(for: curve)
                + RenderEdgeGeometry.segments(for: orthogonal)
        )
    }

    private static func visibleCanvasRect(
        viewport: GraphViewport,
        screenSize: GraphSize,
        padding: Double
    ) -> GraphRect {
        let scale: Double
        if viewport.scale.isFinite, viewport.scale > 0 {
            scale = min(
                max(
                    viewport.scale,
                    CommitGraphViewportProjector.minimumScale
                ),
                CommitGraphViewportProjector.maximumScale
            )
        } else {
            scale = 1
        }
        let offsetX = viewport.offsetX.isFinite ? viewport.offsetX : 0
        let offsetY = viewport.offsetY.isFinite ? viewport.offsetY : 0
        let width = screenSize.width.isFinite
            ? max(screenSize.width, 0)
            : 0
        let height = screenSize.height.isFinite
            ? max(screenSize.height, 0)
            : 0
        let safePadding = padding.isFinite ? max(padding, 0) : 0
        let minimumX = (-safePadding - offsetX) / scale
        let minimumY = (-safePadding - offsetY) / scale
        let maximumX = (width + safePadding - offsetX) / scale
        let maximumY = (height + safePadding - offsetY) / scale
        return GraphRect(
            x: min(minimumX, maximumX),
            y: min(minimumY, maximumY),
            width: abs(maximumX - minimumX),
            height: abs(maximumY - minimumY)
        )
    }
}

private struct RenderEdgeGeometry: Sendable {
    let endpointRects: [GraphRect]
    let segments: [RenderSegment]
    let indexCells: Set<RenderGridCell>?

    init(endpointRects: [GraphRect], segments: [RenderSegment]) {
        self.endpointRects = endpointRects
        self.segments = segments
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
            for segment in segments {
                guard let segmentCells = RenderSpatialGrid.cells(
                    from: segment.start,
                    to: segment.end,
                    level: level
                ) else {
                    exceededLimit = true
                    break
                }
                cells.formUnion(segmentCells)
                if cells.count > RenderSpatialGrid.maximumCellsPerItem {
                    exceededLimit = true
                    break
                }
            }
            if exceededLimit { continue }
            indexCells = cells
            return
        }
        indexCells = nil
    }

    func intersects(_ rect: GraphRect) -> Bool {
        endpointRects.contains { $0.intersects(rect) }
            || segments.contains { $0.intersects(rect) }
    }

    static func segments(
        for path: CommitGraphGeneratedPath
    ) -> [RenderSegment] {
        let points: [GraphPoint]
        switch path {
        case let .curve(start, control1, control2, end):
            points = (0...20).map { step in
                cubicPoint(
                    start: start,
                    control1: control1,
                    control2: control2,
                    end: end,
                    t: Double(step) / 20
                )
            }
        case let .polyline(pathPoints):
            points = pathPoints
        }
        return zip(points, points.dropFirst()).map {
            RenderSegment(start: $0.0, end: $0.1)
        }
    }

    private static func cubicPoint(
        start: GraphPoint,
        control1: GraphPoint,
        control2: GraphPoint,
        end: GraphPoint,
        t: Double
    ) -> GraphPoint {
        let inverse = 1 - t
        return GraphPoint(
            x: inverse * inverse * inverse * start.x
                + 3 * inverse * inverse * t * control1.x
                + 3 * inverse * t * t * control2.x
                + t * t * t * end.x,
            y: inverse * inverse * inverse * start.y
                + 3 * inverse * inverse * t * control1.y
                + 3 * inverse * t * t * control2.y
                + t * t * t * end.y
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

private struct RenderGridCell: Hashable, Sendable {
    let level: Int
    let x: Int
    let y: Int
}

private struct RenderSpatialGrid: Sendable {
    static let baseCellSize = 512.0
    static let maximumCellsPerItem = 512

    private var buckets: [RenderGridCell: Set<Int>] = [:]
    private var cellsByItem: [Int: Set<RenderGridCell>] = [:]
    private var bucketCountByLevel: [Int: Int] = [:]
    private var activeLevels: Set<Int> = []
    private var overflowItems: Set<Int> = []

    mutating func replace(item: Int, rect: GraphRect) {
        replace(item: item, cells: Self.adaptiveCells(for: rect))
    }

    mutating func replace(
        item: Int,
        cells: Set<RenderGridCell>?
    ) {
        remove(item: item)
        guard let cells else {
            overflowItems.insert(item)
            return
        }
        cellsByItem[item] = cells
        for cell in cells {
            if buckets[cell] == nil {
                bucketCountByLevel[cell.level, default: 0] += 1
                activeLevels.insert(cell.level)
            }
            buckets[cell, default: []].insert(item)
        }
    }

    mutating func remove(item: Int) {
        overflowItems.remove(item)
        guard let cells = cellsByItem.removeValue(forKey: item) else {
            return
        }
        for cell in cells {
            buckets[cell]?.remove(item)
            if buckets[cell]?.isEmpty == true {
                buckets.removeValue(forKey: cell)
                let remaining = max(
                    (bucketCountByLevel[cell.level] ?? 1) - 1,
                    0
                )
                if remaining == 0 {
                    bucketCountByLevel.removeValue(forKey: cell.level)
                    activeLevels.remove(cell.level)
                } else {
                    bucketCountByLevel[cell.level] = remaining
                }
            }
        }
    }

    func candidates(in rect: GraphRect) -> Set<Int> {
        var result = overflowItems
        for level in activeLevels {
            guard let range = Self.cellRange(for: rect, level: level),
                  let requestedCellCount = Self.cellCount(for: range)
            else {
                for (cell, items) in buckets where cell.level == level {
                    result.formUnion(items)
                }
                continue
            }
            let levelBucketCount = bucketCountByLevel[level] ?? 0
            if requestedCellCount > max(levelBucketCount * 2, 4_096) {
                for (cell, items) in buckets
                where cell.level == level
                    && cell.x >= range.minimumX
                    && cell.x <= range.maximumX
                    && cell.y >= range.minimumY
                    && cell.y <= range.maximumY {
                    result.formUnion(items)
                }
                continue
            }
            for y in range.minimumY...range.maximumY {
                for x in range.minimumX...range.maximumX {
                    result.formUnion(
                        buckets[
                            RenderGridCell(level: level, x: x, y: y)
                        ] ?? []
                    )
                }
            }
        }
        return result
    }

    static func cells(
        for rect: GraphRect,
        level: Int
    ) -> Set<RenderGridCell>? {
        guard let range = cellRange(for: rect, level: level) else {
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
                result.insert(RenderGridCell(level: level, x: x, y: y))
            }
        }
        return result
    }

    static func cells(
        from start: GraphPoint,
        to end: GraphPoint,
        level: Int
    ) -> Set<RenderGridCell>? {
        let currentCellSize = cellSize(for: level)
        guard start.x.isFinite,
              start.y.isFinite,
              end.x.isFinite,
              end.y.isFinite,
              let startCell = cell(for: start, level: level),
              let endCell = cell(for: end, level: level)
        else {
            return nil
        }
        var result: Set<RenderGridCell> = [startCell]
        if startCell == endCell { return result }

        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let stepX = deltaX > 0 ? 1 : (deltaX < 0 ? -1 : 0)
        let stepY = deltaY > 0 ? 1 : (deltaY < 0 ? -1 : 0)
        let tDeltaX = stepX == 0 ? .infinity : currentCellSize / abs(deltaX)
        let tDeltaY = stepY == 0 ? .infinity : currentCellSize / abs(deltaY)
        let nextX = stepX > 0
            ? Double(startCell.x + 1) * currentCellSize
            : Double(startCell.x) * currentCellSize
        let nextY = stepY > 0
            ? Double(startCell.y + 1) * currentCellSize
            : Double(startCell.y) * currentCellSize
        var tMaxX = stepX == 0 ? .infinity : (nextX - start.x) / deltaX
        var tMaxY = stepY == 0 ? .infinity : (nextY - start.y) / deltaY
        var current = startCell

        while current != endCell {
            if tMaxX < tMaxY {
                current = RenderGridCell(
                    level: level,
                    x: current.x + stepX,
                    y: current.y
                )
                tMaxX += tDeltaX
            } else if tMaxY < tMaxX {
                current = RenderGridCell(
                    level: level,
                    x: current.x,
                    y: current.y + stepY
                )
                tMaxY += tDeltaY
            } else {
                if stepX != 0 {
                    result.insert(
                        RenderGridCell(
                            level: level,
                            x: current.x + stepX,
                            y: current.y
                        )
                    )
                }
                if stepY != 0 {
                    result.insert(
                        RenderGridCell(
                            level: level,
                            x: current.x,
                            y: current.y + stepY
                        )
                    )
                }
                current = RenderGridCell(
                    level: level,
                    x: current.x + stepX,
                    y: current.y + stepY
                )
                tMaxX += tDeltaX
                tMaxY += tDeltaY
            }
            result.insert(current)
            if result.count > maximumCellsPerItem {
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
        guard rect.minimumX.isFinite,
              rect.minimumY.isFinite,
              rect.maximumX.isFinite,
              rect.maximumY.isFinite,
              let minimum = cell(
                for: GraphPoint(x: rect.minimumX, y: rect.minimumY),
                level: level
              ),
              let maximum = cell(
                for: GraphPoint(x: rect.maximumX, y: rect.maximumY),
                level: level
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
        let currentCellSize = cellSize(for: level)
        let x = floor(point.x / currentCellSize)
        let y = floor(point.y / currentCellSize)
        guard x.isFinite,
              y.isFinite,
              x >= Double(Int.min),
              x <= Double(Int.max),
              y >= Double(Int.min),
              y <= Double(Int.max)
        else {
            return nil
        }
        return RenderGridCell(level: level, x: Int(x), y: Int(y))
    }
}

private extension GraphRect {
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
