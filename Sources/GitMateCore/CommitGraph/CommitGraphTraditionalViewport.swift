import Foundation

public enum CommitGraphTraditionalViewport {
    public static func visibleRows(
        totalCount: Int,
        rowHeight: Double,
        verticalOffset: Double,
        viewportHeight: Double,
        preloadScreens: Double
    ) -> Range<Int> {
        guard totalCount > 0,
              rowHeight.isFinite,
              rowHeight > 0,
              viewportHeight.isFinite,
              viewportHeight > 0
        else {
            return 0..<0
        }

        let normalizedOffset = verticalOffset.isFinite
            ? max(verticalOffset, 0)
            : 0
        let normalizedPreload = preloadScreens.isFinite
            ? max(preloadScreens, 0)
            : 0
        let contentHeight = Double(totalCount) * rowHeight
        let maximumOffset = contentHeight.isFinite
            ? max(contentHeight - viewportHeight, 0)
            : Double.greatestFiniteMagnitude
        let offset = min(normalizedOffset, maximumOffset)
        let preloadHeight = viewportHeight * normalizedPreload
        let safePreloadHeight = preloadHeight.isFinite
            ? preloadHeight
            : Double.greatestFiniteMagnitude

        let lowerValue = max(offset - safePreloadHeight, 0) / rowHeight
        let upperExtent = offset
            .addingProduct(1, viewportHeight)
            .addingProduct(1, safePreloadHeight)
        let upperValue = upperExtent / rowHeight
        let lowerBound = index(
            floor(lowerValue),
            upperBound: totalCount
        )
        let upperBound = index(
            ceil(upperValue),
            upperBound: totalCount
        )
        return lowerBound..<max(lowerBound, upperBound)
    }

    private static func index(
        _ value: Double,
        upperBound: Int
    ) -> Int {
        guard value.isFinite else { return upperBound }
        guard value > 0 else { return 0 }
        guard value < Double(upperBound) else { return upperBound }
        return Int(value)
    }
}
