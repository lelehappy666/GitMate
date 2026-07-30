import Foundation

public enum CommitGraphPortSide: String, Codable, CaseIterable, Sendable {
    case top
    case right
    case bottom
    case left
}

public struct PortAnchor: Codable, Equatable, Sendable {
    public let side: CommitGraphPortSide
    public let offset: Double

    public init(side: CommitGraphPortSide, offset: Double) {
        self.side = side
        self.offset = Self.normalized(offset)
    }

    private enum CodingKeys: String, CodingKey {
        case side
        case offset
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            side: try container.decode(
                CommitGraphPortSide.self,
                forKey: .side
            ),
            offset: try container.decode(Double.self, forKey: .offset)
        )
    }

    private static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }
}

public enum CommitGraphLineStyle: String, Codable, CaseIterable, Sendable {
    case curve
    case orthogonal
}

public struct GraphRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = max(width, 0)
        self.height = max(height, 0)
    }

    public var minimumX: Double { x }
    public var minimumY: Double { y }
    public var maximumX: Double { x + width }
    public var maximumY: Double { y + height }
    public var midpointX: Double { x + width / 2 }
    public var midpointY: Double { y + height / 2 }
}

public enum CommitGraphGeneratedPath: Equatable, Sendable {
    case curve(
        start: GraphPoint,
        control1: GraphPoint,
        control2: GraphPoint,
        end: GraphPoint
    )
    case polyline(points: [GraphPoint])
}
