import Foundation

public struct GraphSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
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
        let safePadding = max(padding, 0)
        let minimumX = -safePadding
        let minimumY = -safePadding
        let maximumX = max(screenSize.width, 0) + safePadding
        let maximumY = max(screenSize.height, 0) + safePadding
        let halfWidth = nodeWidth * validScale(viewport.scale) / 2
        let halfHeight = nodeHeight * validScale(viewport.scale) / 2

        return layout.nodes.filter { node in
            let center = screenPoint(
                canvasPoint: GraphPoint(x: node.x, y: node.y),
                viewport: viewport
            )
            return center.x + halfWidth >= minimumX
                && center.x - halfWidth <= maximumX
                && center.y + halfHeight >= minimumY
                && center.y - halfHeight <= maximumY
        }
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

        return layout.nodes.reversed().first { node in
            point.x >= node.x - halfWidth
                && point.x <= node.x + halfWidth
                && point.y >= node.y - halfHeight
                && point.y <= node.y + halfHeight
        }
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

    private static func validScale(_ scale: Double) -> Double {
        guard scale.isFinite, scale > 0 else {
            return 1
        }
        return scale
    }
}
