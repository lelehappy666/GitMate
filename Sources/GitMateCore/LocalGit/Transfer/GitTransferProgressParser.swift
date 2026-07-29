import Foundation

public enum GitTransferPhase: Equatable, Sendable {
    case connecting
    case negotiating
    case transferring
    case integrating
    case conflicted
    case completed
}

public struct GitTransferEvent: Equatable, Sendable {
    public let phase: GitTransferPhase
    public let currentObjects: Int?
    public let totalObjects: Int?
    public let bytesPerSecond: Int64?
    public let message: String?

    public init(
        phase: GitTransferPhase,
        currentObjects: Int? = nil,
        totalObjects: Int? = nil,
        bytesPerSecond: Int64? = nil,
        message: String? = nil
    ) {
        self.phase = phase
        self.currentObjects = currentObjects
        self.totalObjects = totalObjects
        self.bytesPerSecond = bytesPerSecond
        self.message = message
    }
}

public struct GitTransferProgressParser: Sendable {
    public init() {}

    public func parse(line: String) -> GitTransferEvent {
        let redacted = GitOutputRedactor.redact(line)
        let lowercased = redacted.lowercased()
        let phase: GitTransferPhase
        if lowercased.contains("enumerating")
            || lowercased.contains("negotiating") {
            phase = .negotiating
        } else {
            phase = .transferring
        }
        let counts = Self.objectCounts(in: redacted)
        return GitTransferEvent(
            phase: phase,
            currentObjects: counts?.current,
            totalObjects: counts?.total,
            bytesPerSecond: Self.bytesPerSecond(in: redacted),
            message: redacted
        )
    }

    private static func objectCounts(
        in value: String
    ) -> (current: Int, total: Int)? {
        guard let open = value.firstIndex(of: "("),
              let slash = value[open...].firstIndex(of: "/"),
              let close = value[slash...].firstIndex(of: ")")
        else {
            return nil
        }
        let currentStart = value.index(after: open)
        let totalStart = value.index(after: slash)
        guard let current = Int(value[currentStart..<slash]),
              let total = Int(value[totalStart..<close])
        else {
            return nil
        }
        return (current, total)
    }

    private static func bytesPerSecond(in value: String) -> Int64? {
        let units: [(String, Double)] = [
            ("GiB/s", 1_073_741_824),
            ("MiB/s", 1_048_576),
            ("KiB/s", 1_024),
            ("bytes/s", 1)
        ]
        for (unit, multiplier) in units {
            guard let range = value.range(of: unit) else {
                continue
            }
            let prefix = value[..<range.lowerBound]
            guard let token = prefix
                .split(whereSeparator: { $0.isWhitespace || $0 == "|" })
                .last,
                let number = Double(token)
            else {
                continue
            }
            return Int64(number * multiplier)
        }
        return nil
    }
}
