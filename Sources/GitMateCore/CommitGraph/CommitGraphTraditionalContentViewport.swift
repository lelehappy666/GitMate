import Foundation

public enum CommitGraphTraditionalContentViewport {
    public static let informationWidth = 560.0

    public static func contentWidth(
        viewportWidth: Double,
        maximumLane: Int
    ) -> Double {
        let safeViewportWidth = normalizedDimension(viewportWidth)
        let laneWidth = max(
            220,
            CommitGraphTraditionalLaneGeometry.contentWidth(
                maximumLane: max(maximumLane, 0)
            ) + 12
        )
        return max(safeViewportWidth, laneWidth + informationWidth)
    }

    public static func maximumHorizontalOffset(
        contentWidth: Double,
        viewportWidth: Double
    ) -> Double {
        max(
            normalizedDimension(contentWidth)
                - normalizedDimension(viewportWidth),
            0
        )
    }

    public static func clampedHorizontalOffset(
        _ value: Double,
        contentWidth: Double,
        viewportWidth: Double
    ) -> Double {
        let normalizedValue = value.isFinite ? value : 0
        return min(
            max(normalizedValue, 0),
            maximumHorizontalOffset(
                contentWidth: contentWidth,
                viewportWidth: viewportWidth
            )
        )
    }

    public static func overlayRows(
        totalCount: Int,
        rowHeight: Double,
        verticalOffset: Double,
        viewportHeight: Double
    ) -> Range<Int> {
        CommitGraphTraditionalViewport.visibleRows(
            totalCount: totalCount,
            rowHeight: rowHeight,
            verticalOffset: verticalOffset,
            viewportHeight: viewportHeight,
            preloadScreens: 0
        )
    }

    private static func normalizedDimension(_ value: Double) -> Double {
        value.isFinite ? max(value, 0) : 0
    }
}

public enum CommitGraphTraditionalHorizontalDrag {
    public static let activationThreshold = 4.0

    public static func isDragging(horizontalDistance: Double) -> Bool {
        guard horizontalDistance.isFinite else { return false }
        return abs(horizontalDistance) > activationThreshold
    }
}
