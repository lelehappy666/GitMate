import Foundation

public enum CommitGraphTraditionalContentViewport {
    public static let informationLeadingPadding = 18.0

    public static func informationOriginX(
        dividerWidth: Double
    ) -> Double {
        let width = dividerWidth.isFinite ? max(dividerWidth, 0) : 0
        return width + informationLeadingPadding
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
}
