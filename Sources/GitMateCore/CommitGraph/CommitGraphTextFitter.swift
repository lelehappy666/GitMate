import Foundation

public enum CommitGraphTextFitter {
    public static func truncated(
        _ text: String,
        maximumWidth: Double,
        measure: (String) -> Double
    ) -> String {
        guard !text.isEmpty,
              maximumWidth.isFinite,
              maximumWidth > 0
        else {
            return ""
        }
        guard measure(text) > maximumWidth else {
            return text
        }

        let ellipsis = "…"
        guard measure(ellipsis) <= maximumWidth else {
            return ""
        }

        var lowerBound = 0
        var upperBound = text.count
        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound + 1) / 2
            let candidate = String(text.prefix(midpoint)) + ellipsis
            if measure(candidate) <= maximumWidth {
                lowerBound = midpoint
            } else {
                upperBound = midpoint - 1
            }
        }
        return String(text.prefix(lowerBound)) + ellipsis
    }
}
