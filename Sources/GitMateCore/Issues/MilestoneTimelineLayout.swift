import Foundation

public struct MilestoneCanvasPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct MilestoneCanvasBounds: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) {
        self.x = x
        self.y = y
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public func contains(_ point: MilestoneCanvasPoint) -> Bool {
        point.x >= x
            && point.y >= y
            && point.x <= x + width
            && point.y <= y + height
    }
}

public struct MilestoneTimelineNode: Identifiable, Equatable, Sendable {
    public var id: Int64 { milestoneID }

    public let milestoneID: Int64
    public let position: MilestoneCanvasPoint
    public let sequence: Int

    public init(
        milestoneID: Int64,
        position: MilestoneCanvasPoint,
        sequence: Int
    ) {
        self.milestoneID = milestoneID
        self.position = position
        self.sequence = sequence
    }
}

public struct MilestoneTimelineConnection: Equatable, Sendable {
    public let sourceMilestoneID: Int64
    public let targetMilestoneID: Int64

    public init(
        sourceMilestoneID: Int64,
        targetMilestoneID: Int64
    ) {
        self.sourceMilestoneID = sourceMilestoneID
        self.targetMilestoneID = targetMilestoneID
    }
}

public struct MilestoneTimelineLayoutResult: Equatable, Sendable {
    public let nodes: [MilestoneTimelineNode]
    public let connections: [MilestoneTimelineConnection]
    public let bounds: MilestoneCanvasBounds

    public init(
        nodes: [MilestoneTimelineNode],
        connections: [MilestoneTimelineConnection],
        bounds: MilestoneCanvasBounds
    ) {
        self.nodes = nodes
        self.connections = connections
        self.bounds = bounds
    }
}

public struct MilestoneTimelineLayout: Equatable, Sendable {
    public let horizontalSpacing: Double
    public let verticalSpacing: Double
    public let contentInset: Double

    public init(
        horizontalSpacing: Double = 280,
        verticalSpacing: Double = 160,
        contentInset: Double = 220
    ) {
        self.horizontalSpacing = max(180, horizontalSpacing)
        self.verticalSpacing = max(100, verticalSpacing)
        self.contentInset = max(100, contentInset)
    }

    public func makeLayout(
        milestones: [IssueMilestone]
    ) -> MilestoneTimelineLayoutResult {
        let ordered = milestones.sorted(by: milestoneOrder)
        guard !ordered.isEmpty else {
            return MilestoneTimelineLayoutResult(
                nodes: [],
                connections: [],
                bounds: MilestoneCanvasBounds(
                    x: 0,
                    y: 0,
                    width: contentInset * 2,
                    height: contentInset * 2
                )
            )
        }

        let lanes = [1, 0, 2, 1]
        let nodes = ordered.enumerated().map { index, milestone in
            MilestoneTimelineNode(
                milestoneID: milestone.id,
                position: MilestoneCanvasPoint(
                    x: contentInset + (Double(index) * horizontalSpacing),
                    y: contentInset
                        + (Double(lanes[index % lanes.count]) * verticalSpacing)
                ),
                sequence: index
            )
        }
        let connections = zip(nodes, nodes.dropFirst()).map {
            MilestoneTimelineConnection(
                sourceMilestoneID: $0.0.milestoneID,
                targetMilestoneID: $0.1.milestoneID
            )
        }

        let minX = nodes.map(\.position.x).min() ?? 0
        let maxX = nodes.map(\.position.x).max() ?? 0
        let minY = nodes.map(\.position.y).min() ?? 0
        let maxY = nodes.map(\.position.y).max() ?? 0
        let bounds = MilestoneCanvasBounds(
            x: minX - contentInset,
            y: minY - contentInset,
            width: maxX - minX + (contentInset * 2),
            height: maxY - minY + (contentInset * 2)
        )

        return MilestoneTimelineLayoutResult(
            nodes: nodes,
            connections: connections,
            bounds: bounds
        )
    }

    private func milestoneOrder(
        _ lhs: IssueMilestone,
        _ rhs: IssueMilestone
    ) -> Bool {
        switch (lhs.dueOn, rhs.dueOn) {
        case let (left?, right?):
            if left == right {
                return lhs.number < rhs.number
            }
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.number < rhs.number
        }
    }
}
