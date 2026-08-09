import Foundation

public struct GraphSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public enum GraphViewportChange: Equatable, Sendable {
    case pan(GraphPoint)
    case zoom(multiplier: Double, anchor: GraphPoint)
}

public enum CommitGraphViewportProjector {
    public static let minimumScale = 0.35
    public static let maximumScale = 2.0
    public static let nodeWidth = 224.0
    public static let nodeHeight = 74.0

    public static func visibleNodes(
        layout: CommitGraphLayoutResult,
        viewport: GraphViewport,
        screenSize: GraphSize,
        padding: Double = 180
    ) -> [CommitGraphNode] {
        let bounds = visibleCanvasBounds(
            viewport: viewport,
            screenSize: screenSize,
            padding: padding
        )
        let candidateIndices = layout.spatialIndex.nodeIndices(
            minimumY: bounds.minimumY - nodeHeight / 2,
            maximumY: bounds.maximumY + nodeHeight / 2
        )
        let halfWidth = nodeWidth / 2
        let halfHeight = nodeHeight / 2

        return candidateIndices.compactMap { index in
            let node = layout.nodes[index]
            guard node.x + halfWidth >= bounds.minimumX,
                  node.x - halfWidth <= bounds.maximumX,
                  node.y + halfHeight >= bounds.minimumY,
                  node.y - halfHeight <= bounds.maximumY
            else {
                return nil
            }
            return node
        }
    }

    public static func visibleEdges(
        layout: CommitGraphLayoutResult,
        viewport: GraphViewport,
        screenSize: GraphSize,
        padding: Double = 180
    ) -> [CommitGraphEdge] {
        let bounds = visibleCanvasBounds(
            viewport: viewport,
            screenSize: screenSize,
            padding: padding
        )
        let candidateIndices = layout.spatialIndex.edgeIndices(
            minimumY: bounds.minimumY,
            maximumY: bounds.maximumY
        )

        return candidateIndices.compactMap { index in
            let edge = layout.edges[index]
            guard let child = layout.node(hash: edge.childHash),
                  let parent = layout.node(hash: edge.parentHash),
                  max(child.x, parent.x) >= bounds.minimumX,
                  min(child.x, parent.x) <= bounds.maximumX,
                  max(child.y, parent.y) >= bounds.minimumY,
                  min(child.y, parent.y) <= bounds.maximumY
            else {
                return nil
            }
            return edge
        }
    }

    private static func visibleCanvasBounds(
        viewport: GraphViewport,
        screenSize: GraphSize,
        padding: Double
    ) -> (
        minimumX: Double,
        minimumY: Double,
        maximumX: Double,
        maximumY: Double
    ) {
        let safePadding = max(padding, 0)
        let topLeft = canvasPoint(
            screenPoint: GraphPoint(
                x: -safePadding,
                y: -safePadding
            ),
            viewport: viewport
        )
        let bottomRight = canvasPoint(
            screenPoint: GraphPoint(
                x: max(screenSize.width, 0) + safePadding,
                y: max(screenSize.height, 0) + safePadding
            ),
            viewport: viewport
        )
        return (
            minimumX: min(topLeft.x, bottomRight.x),
            minimumY: min(topLeft.y, bottomRight.y),
            maximumX: max(topLeft.x, bottomRight.x),
            maximumY: max(topLeft.y, bottomRight.y)
        )
    }

    public static func node(
        at screenPoint: GraphPoint,
        layout: CommitGraphLayoutResult,
        viewport: GraphViewport
    ) -> CommitGraphNode? {
        let point = canvasPoint(
            screenPoint: screenPoint,
            viewport: viewport
        )
        let halfWidth = nodeWidth / 2
        let halfHeight = nodeHeight / 2
        let candidateIndices = layout.spatialIndex.nodeIndices(
            minimumY: point.y - halfHeight,
            maximumY: point.y + halfHeight
        )

        for index in candidateIndices.reversed() {
            let node = layout.nodes[index]
            if point.x >= node.x - halfWidth,
               point.x <= node.x + halfWidth,
               point.y >= node.y - halfHeight,
               point.y <= node.y + halfHeight {
                return node
            }
        }
        return nil
    }

    public static func screenPoint(
        canvasPoint: GraphPoint,
        viewport: GraphViewport
    ) -> GraphPoint {
        let scale = validScale(viewport.scale)
        return GraphPoint(
            x: canvasPoint.x * scale + viewport.offsetX,
            y: canvasPoint.y * scale + viewport.offsetY
        )
    }

    public static func canvasPoint(
        screenPoint: GraphPoint,
        viewport: GraphViewport
    ) -> GraphPoint {
        let scale = validScale(viewport.scale)
        return GraphPoint(
            x: (screenPoint.x - viewport.offsetX) / scale,
            y: (screenPoint.y - viewport.offsetY) / scale
        )
    }

    public static func zoomed(
        _ viewport: GraphViewport,
        by multiplier: Double,
        anchor: GraphPoint
    ) -> GraphViewport {
        guard multiplier.isFinite, multiplier > 0 else {
            return viewport
        }

        let oldScale = validScale(viewport.scale)
        let newScale = min(
            max(oldScale * multiplier, minimumScale),
            maximumScale
        )
        guard newScale != oldScale else {
            var clamped = viewport
            clamped.scale = newScale
            return clamped
        }

        let canvasAnchor = canvasPoint(
            screenPoint: anchor,
            viewport: GraphViewport(
                offsetX: viewport.offsetX,
                offsetY: viewport.offsetY,
                scale: oldScale
            )
        )
        return GraphViewport(
            offsetX: anchor.x - canvasAnchor.x * newScale,
            offsetY: anchor.y - canvasAnchor.y * newScale,
            scale: newScale
        )
    }

    public static func applying(
        _ changes: [GraphViewportChange],
        to viewport: GraphViewport
    ) -> GraphViewport {
        changes.reduce(viewport) { current, change in
            switch change {
            case let .pan(translation):
                var updated = current
                updated.offsetX += translation.x
                updated.offsetY += translation.y
                return updated
            case let .zoom(multiplier, anchor):
                return zoomed(
                    current,
                    by: multiplier,
                    anchor: anchor
                )
            }
        }
    }

    private static func validScale(_ scale: Double) -> Double {
        guard scale.isFinite, scale > 0 else {
            return 1
        }
        return scale
    }
}
