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

public struct CommitGraphSelectionModifiers:
    OptionSet,
    Equatable,
    Sendable
{
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = CommitGraphSelectionModifiers(rawValue: 1 << 0)
    public static let shift = CommitGraphSelectionModifiers(rawValue: 1 << 1)
}

public enum CommitGraphPointerChange: Equatable, Sendable {
    case pan(GraphPoint)
    case moveNode(hash: String, translation: GraphPoint)
    case moveGroup(id: UUID, translation: GraphPoint)
    case moveRegion(id: UUID, translation: GraphPoint)
    case resizeRegion(id: UUID, translation: GraphPoint)
}

public struct CommitGraphEdgePorts: Codable, Equatable, Sendable {
    public let source: PortAnchor
    public let target: PortAnchor

    public init(source: PortAnchor, target: PortAnchor) {
        self.source = source
        self.target = target
    }
}

public enum CommitGraphGroupSource: String, Codable, Sendable {
    case manual
    case branchSuggestion
}

public struct CommitGraphGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var memberHashes: Set<String>
    public var source: CommitGraphGroupSource
    public var origin: GraphPoint
    public var relativePositions: [String: GraphPoint]
    public var isCollapsed: Bool

    public init(
        id: UUID,
        title: String,
        memberHashes: Set<String>,
        source: CommitGraphGroupSource,
        origin: GraphPoint,
        relativePositions: [String: GraphPoint],
        isCollapsed: Bool
    ) {
        self.id = id
        self.title = title
        self.memberHashes = memberHashes
        self.source = source
        self.origin = origin
        self.relativePositions = relativePositions
        self.isCollapsed = isCollapsed
    }

    public func absolutePosition(for hash: String) -> GraphPoint? {
        guard let relative = relativePositions[hash] else { return nil }
        return GraphPoint(
            x: origin.x + relative.x,
            y: origin.y + relative.y
        )
    }
}

public struct CommitGraphRegionMarker:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let id: UUID
    public var title: String
    public var colorHex: String
    public var rect: GraphRect

    public init(
        id: UUID = UUID(),
        title: String,
        colorHex: String,
        rect: GraphRect
    ) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
        self.rect = rect
    }
}

public enum CommitGraphBoundaryDirection: String, Codable, Sendable {
    case enteringGroup
    case leavingGroup
}

public struct CollapsedEdgeKey: Codable, Equatable, Hashable, Sendable {
    public let groupID: UUID
    public let externalNodeID: String
    public let direction: CommitGraphBoundaryDirection

    public init(
        groupID: UUID,
        externalNodeID: String,
        direction: CommitGraphBoundaryDirection
    ) {
        self.groupID = groupID
        self.externalNodeID = externalNodeID
        self.direction = direction
    }
}

public struct CommitGraphSceneState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var nodePositions: [String: GraphPoint]
    public var groups: [CommitGraphGroup]
    public var regions: [CommitGraphRegionMarker]
    public var edgePorts: [String: CommitGraphEdgePorts]
    public var boundaryPorts: [CollapsedEdgeKey: CommitGraphEdgePorts]
    public var lineStyle: CommitGraphLineStyle

    public init(
        schemaVersion: Int = currentSchemaVersion,
        nodePositions: [String: GraphPoint] = [:],
        groups: [CommitGraphGroup] = [],
        regions: [CommitGraphRegionMarker] = [],
        edgePorts: [String: CommitGraphEdgePorts] = [:],
        boundaryPorts: [CollapsedEdgeKey: CommitGraphEdgePorts] = [:],
        lineStyle: CommitGraphLineStyle = .curve
    ) {
        self.schemaVersion = schemaVersion
        self.nodePositions = nodePositions
        self.groups = groups
        self.regions = regions
        self.edgePorts = edgePorts
        self.boundaryPorts = boundaryPorts
        self.lineStyle = lineStyle
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case nodePositions
        case groups
        case regions
        case edgePorts
        case boundaryPorts
        case lineStyle
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(
            Int.self,
            forKey: .schemaVersion
        )
        nodePositions = try container.decode(
            [String: GraphPoint].self,
            forKey: .nodePositions
        )
        groups = try container.decode(
            [CommitGraphGroup].self,
            forKey: .groups
        )
        regions = try container.decodeIfPresent(
            [CommitGraphRegionMarker].self,
            forKey: .regions
        ) ?? []
        edgePorts = try container.decode(
            [String: CommitGraphEdgePorts].self,
            forKey: .edgePorts
        )
        boundaryPorts = try container.decode(
            [CollapsedEdgeKey: CommitGraphEdgePorts].self,
            forKey: .boundaryPorts
        )
        lineStyle = try container.decode(
            CommitGraphLineStyle.self,
            forKey: .lineStyle
        )
    }

    public static func defaultState(
        layout: CommitGraphLayoutResult
    ) -> CommitGraphSceneState {
        var state = CommitGraphSceneState(
            nodePositions: Dictionary(
                uniqueKeysWithValues: layout.nodes.map {
                    ($0.hash, GraphPoint(x: $0.x, y: $0.y))
                }
            )
        )
        for edge in layout.edges {
            guard let child = layout.node(hash: edge.childHash),
                  let parent = layout.node(hash: edge.parentHash)
            else {
                continue
            }
            state.edgePorts[edge.id] = CommitGraphPortAllocator.ports(
                sourceRect: CommitGraphSceneGeometry.nodeRect(
                    center: GraphPoint(x: child.x, y: child.y)
                ),
                targetRect: CommitGraphSceneGeometry.nodeRect(
                    center: GraphPoint(x: parent.x, y: parent.y)
                )
            )
        }
        return state
    }
}

public struct CommitGraphConnectivityResult: Equatable, Sendable {
    public let isConnected: Bool
    public let disconnectedHashes: [String]

    public init(isConnected: Bool, disconnectedHashes: [String]) {
        self.isConnected = isConnected
        self.disconnectedHashes = disconnectedHashes
    }
}

public struct CommitGraphGroupSuggestion: Equatable, Identifiable, Sendable {
    public var id: String { branchName }

    public let branchName: String
    public let memberHashes: Set<String>

    public init(branchName: String, memberHashes: Set<String>) {
        self.branchName = branchName
        self.memberHashes = memberHashes
    }
}

public enum CommitGraphGroupingError: Error, Equatable, Sendable {
    case groupNotFound
    case insufficientMembers
    case disconnectedSelection([String])
    case unknownMembers([String])
    case membersAlreadyGrouped([String])
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

public enum CommitGraphEndpointID: Equatable, Hashable, Sendable {
    case node(String)
    case group(UUID)
}

public struct CommitGraphVisibleNode: Equatable, Identifiable, Sendable {
    public var id: String { node.hash }

    public let node: CommitGraphNode
    public let position: GraphPoint

    public init(node: CommitGraphNode, position: GraphPoint) {
        self.node = node
        self.position = position
    }
}

public struct CommitGraphVisibleGroup: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let rect: GraphRect
    public let memberCount: Int
    public let isCollapsed: Bool

    public init(
        id: UUID,
        title: String,
        rect: GraphRect,
        memberCount: Int,
        isCollapsed: Bool
    ) {
        self.id = id
        self.title = title
        self.rect = rect
        self.memberCount = memberCount
        self.isCollapsed = isCollapsed
    }
}

public struct CommitGraphVisibleEdge: Equatable, Identifiable, Sendable {
    public let id: String
    public let source: CommitGraphEndpointID
    public let target: CommitGraphEndpointID
    public let kind: CommitGraphEdgeKind
    public let colorIndex: Int
    public let ports: CommitGraphEdgePorts
    public let aggregateKey: CollapsedEdgeKey?
    public let aggregateCount: Int
    public let originalEdgeIDs: [String]

    public init(
        id: String,
        source: CommitGraphEndpointID,
        target: CommitGraphEndpointID,
        kind: CommitGraphEdgeKind,
        colorIndex: Int,
        ports: CommitGraphEdgePorts,
        aggregateKey: CollapsedEdgeKey?,
        aggregateCount: Int,
        originalEdgeIDs: [String]
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.kind = kind
        self.colorIndex = colorIndex
        self.ports = ports
        self.aggregateKey = aggregateKey
        self.aggregateCount = aggregateCount
        self.originalEdgeIDs = originalEdgeIDs
    }
}

public struct CommitGraphSceneProjection: Equatable, Sendable {
    public let nodes: [CommitGraphVisibleNode]
    public let groups: [CommitGraphVisibleGroup]
    public let edges: [CommitGraphVisibleEdge]

    public init(
        nodes: [CommitGraphVisibleNode],
        groups: [CommitGraphVisibleGroup],
        edges: [CommitGraphVisibleEdge]
    ) {
        self.nodes = nodes
        self.groups = groups
        self.edges = edges
    }
}

enum CommitGraphSceneGeometry {
    static let nodeWidth = 224.0
    static let nodeHeight = 74.0
    static let collapsedGroupWidth = 224.0
    static let collapsedGroupHeight = 92.0
    static let groupPadding = 30.0
    static let groupHeaderHeight = 38.0

    static func nodeRect(center: GraphPoint) -> GraphRect {
        GraphRect(
            x: center.x - nodeWidth / 2,
            y: center.y - nodeHeight / 2,
            width: nodeWidth,
            height: nodeHeight
        )
    }

    static func collapsedGroupRect(_ group: CommitGraphGroup) -> GraphRect {
        GraphRect(
            x: group.origin.x,
            y: group.origin.y,
            width: collapsedGroupWidth,
            height: collapsedGroupHeight
        )
    }

    static func expandedGroupRect(_ group: CommitGraphGroup) -> GraphRect {
        let points = group.relativePositions.values
        guard let minimumX = points.map(\.x).min(),
              let maximumX = points.map(\.x).max(),
              let minimumY = points.map(\.y).min(),
              let maximumY = points.map(\.y).max()
        else {
            return collapsedGroupRect(group)
        }
        return GraphRect(
            x: group.origin.x + minimumX
                - nodeWidth / 2
                - groupPadding,
            y: group.origin.y + minimumY
                - nodeHeight / 2
                - groupHeaderHeight,
            width: maximumX - minimumX
                + nodeWidth
                + groupPadding * 2,
            height: maximumY - minimumY
                + nodeHeight
                + groupPadding
                + groupHeaderHeight
        )
    }
}

enum CommitGraphPortAllocator {
    static func ports(
        sourceRect: GraphRect,
        targetRect: GraphRect
    ) -> CommitGraphEdgePorts {
        let deltaX = targetRect.midpointX - sourceRect.midpointX
        let deltaY = targetRect.midpointY - sourceRect.midpointY

        if abs(deltaY) >= abs(deltaX) {
            if deltaY < 0 {
                return CommitGraphEdgePorts(
                    source: PortAnchor(side: .top, offset: 0.5),
                    target: PortAnchor(side: .bottom, offset: 0.5)
                )
            }
            return CommitGraphEdgePorts(
                source: PortAnchor(side: .bottom, offset: 0.5),
                target: PortAnchor(side: .top, offset: 0.5)
            )
        }
        if deltaX < 0 {
            return CommitGraphEdgePorts(
                source: PortAnchor(side: .left, offset: 0.5),
                target: PortAnchor(side: .right, offset: 0.5)
            )
        }
        return CommitGraphEdgePorts(
            source: PortAnchor(side: .right, offset: 0.5),
            target: PortAnchor(side: .left, offset: 0.5)
        )
    }
}
