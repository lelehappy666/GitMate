import Foundation

public struct GitTransferProgress: Equatable, Sendable {
    public let fraction: Double
    public let phase: String
    public let activity: String

    public init(
        fraction: Double,
        phase: String,
        activity: String
    ) {
        self.fraction = min(max(fraction, 0), 1)
        self.phase = phase
        self.activity = activity
    }
}

public enum GitProgressParser {
    public static func parse(_ activity: String) -> GitTransferProgress? {
        let range = NSRange(
            activity.startIndex..<activity.endIndex,
            in: activity
        )
        guard let match = percentageExpression.firstMatch(
            in: activity,
            range: range
        ), let percentageRange = Range(match.range(at: 1), in: activity),
        let percentage = Double(activity[percentageRange]) else {
            return nil
        }

        return GitTransferProgress(
            fraction: percentage / 100,
            phase: phase(for: activity),
            activity: activity
        )
    }

    private static func phase(for activity: String) -> String {
        let normalized = activity.lowercased()
        let phases = [
            ("counting objects", "正在统计对象"),
            ("compressing objects", "正在压缩对象"),
            ("receiving objects", "正在接收对象"),
            ("resolving deltas", "正在解析增量"),
            ("updating files", "正在写入文件"),
            ("checking out files", "正在检出文件")
        ]
        return phases.first(where: { normalized.contains($0.0) })?.1
            ?? "正在下载仓库"
    }

    private static let percentageExpression = try! NSRegularExpression(
        pattern: #"([0-9]{1,3})%"#
    )
}
