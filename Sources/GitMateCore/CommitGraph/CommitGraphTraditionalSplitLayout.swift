import Foundation

public enum CommitGraphTraditionalSplitLayout {
    public static func defaultDividerWidth(
        viewportWidth: Double
    ) -> Double {
        let width = normalized(viewportWidth)
        guard width > 0 else { return 0 }
        let proposed = min(max(width * 0.38, 280), 420)
        return clampedDividerWidth(proposed, viewportWidth: width)
    }

    public static func clampedDividerWidth(
        _ proposed: Double?,
        viewportWidth: Double
    ) -> Double {
        let width = normalized(viewportWidth)
        guard width > 0 else { return 0 }

        let minimumLeft = min(220, width * 0.45)
        let minimumRight = min(420, width * 0.55)
        let maximumLeft = max(minimumLeft, width - minimumRight)
        let fallback = min(max(width * 0.38, 280), 420)
        let value = proposed.flatMap { $0.isFinite ? $0 : nil } ?? fallback
        return min(max(value, minimumLeft), maximumLeft)
    }

    public static func maximumLaneOffset(
        laneContentWidth: Double,
        dividerWidth: Double
    ) -> Double {
        max(normalized(laneContentWidth) - normalized(dividerWidth), 0)
    }

    public static func clampedLaneOffset(
        _ proposed: Double,
        laneContentWidth: Double,
        dividerWidth: Double
    ) -> Double {
        let value = proposed.isFinite ? proposed : 0
        return min(
            max(value, 0),
            maximumLaneOffset(
                laneContentWidth: laneContentWidth,
                dividerWidth: dividerWidth
            )
        )
    }

    public static func visibleLaneRange(
        slotCount: Int,
        horizontalOffset: Double,
        dividerWidth: Double,
        preloadLanes: Int = 2
    ) -> Range<Int> {
        guard slotCount > 0 else { return 0..<0 }
        let spacing = CommitGraphTraditionalLaneGeometry.spacing
        let padding = CommitGraphTraditionalLaneGeometry.leadingPadding
        let offset = max(horizontalOffset.isFinite ? horizontalOffset : 0, 0)
        let width = normalized(dividerWidth)
        let start = max(
            Int(floor((offset - padding) / spacing)) - max(preloadLanes, 0),
            0
        )
        let end = min(
            Int(ceil((offset + width - padding) / spacing))
                + max(preloadLanes, 0) + 1,
            slotCount
        )
        return start..<max(start, end)
    }

    private static func normalized(_ value: Double) -> Double {
        value.isFinite ? max(value, 0) : 0
    }
}
