import Foundation

public enum CommitGraphLevelOfDetail: Equatable, Sendable {
    case full
    case compact
    case overview

    public static let fullThreshold = 0.8
    public static let compactThreshold = 0.5

    public static func forScale(_ scale: Double) -> Self {
        if scale == .infinity {
            return .full
        }
        guard scale.isFinite, scale > 0 else {
            return .overview
        }
        if scale >= fullThreshold {
            return .full
        }
        if scale >= compactThreshold {
            return .compact
        }
        return .overview
    }
}
