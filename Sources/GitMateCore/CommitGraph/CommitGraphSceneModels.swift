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

public enum CommitGraphViewMode: String, Codable, CaseIterable, Sendable {
    case traditional
    case canvas
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
    public static let currentSchemaVersion = 5
    public static let currentLayoutAlgorithmVersion = 3

    public var schemaVersion: Int
    public var layoutAlgorithmVersion: Int
    public var nodePositions: [String: GraphPoint]
    public var groups: [CommitGraphGroup]
    public var regions: [CommitGraphRegionMarker]
    public var edgePorts: [String: CommitGraphEdgePorts]
    public var boundaryPorts: [CollapsedEdgeKey: CommitGraphEdgePorts]
    public var lineStyle: CommitGraphLineStyle
    public var viewMode: CommitGraphViewMode
    public var canvasViewport: GraphViewport
    public var manuallyPositionedHashes: Set<String>
    public var pinnedTraditionalBranchIDs: Set<String>
    public var lastTraditionalBranchID: String?
    public var traditionalDividerWidth: Double?

    public init(
        schemaVersion: Int = currentSchemaVersion,
        layoutAlgorithmVersion: Int = currentLayoutAlgorithmVersion,
        nodePositions: [String: GraphPoint] = [:],
        groups: [CommitGraphGroup] = [],
        regions: [CommitGraphRegionMarker] = [],
        edgePorts: [String: CommitGraphEdgePorts] = [:],
        boundaryPorts: [CollapsedEdgeKey: CommitGraphEdgePorts] = [:],
        lineStyle: CommitGraphLineStyle = .curve,
        viewMode: CommitGraphViewMode = .traditional,
        canvasViewport: GraphViewport = GraphViewport(),
        manuallyPositionedHashes: Set<String> = [],
        pinnedTraditionalBranchIDs: Set<String> = [],
        lastTraditionalBranchID: String? = nil,
        traditionalDividerWidth: Double? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.layoutAlgorithmVersion = layoutAlgorithmVersion
        self.nodePositions = nodePositions
        self.groups = groups
        self.regions = regions
        self.edgePorts = edgePorts
        self.boundaryPorts = boundaryPorts
        self.lineStyle = lineStyle
        self.viewMode = viewMode
        self.canvasViewport = canvasViewport
        self.manuallyPositionedHashes = manuallyPositionedHashes
        self.pinnedTraditionalBranchIDs = pinnedTraditionalBranchIDs
        self.lastTraditionalBranchID = lastTraditionalBranchID
        self.traditionalDividerWidth = traditionalDividerWidth
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case layoutAlgorithmVersion
        case nodePositions
        case groups
        case regions
        case edgePorts
        case boundaryPorts
        case lineStyle
        case viewMode
        case canvasViewport
        case manuallyPositionedHashes
        case pinnedTraditionalBranchIDs
        case lastTraditionalBranchID
        case traditionalDividerWidth
    }

    private struct CodableViewport: Codable {
        let offsetX: Double
        let offsetY: Double
        let scale: Double

        init(_ viewport: GraphViewport) {
            offsetX = viewport.offsetX
            offsetY = viewport.offsetY
            scale = viewport.scale
        }

        var viewport: GraphViewport {
            GraphViewport(
                offsetX: offsetX,
                offsetY: offsetY,
                scale: scale
            )
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedSchemaVersion = try container.decode(
            Int.self,
            forKey: .schemaVersion
        )
        schemaVersion = storedSchemaVersion < Self.currentSchemaVersion
            ? Self.currentSchemaVersion
            : storedSchemaVersion
        layoutAlgorithmVersion = storedSchemaVersion < 3
            ? 1
            : try container.decodeIfPresent(
                Int.self,
                forKey: .layoutAlgorithmVersion
            ) ?? Self.currentLayoutAlgorithmVersion
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
        if storedSchemaVersion == 1 {
            viewMode = .traditional
            canvasViewport = GraphViewport()
        } else {
            viewMode = try container.decode(
                CommitGraphViewMode.self,
                forKey: .viewMode
            )
            canvasViewport = try container.decode(
                CodableViewport.self,
                forKey: .canvasViewport
            ).viewport
        }
        manuallyPositionedHashes = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .manuallyPositionedHashes
        ) ?? []
        pinnedTraditionalBranchIDs = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .pinnedTraditionalBranchIDs
        ) ?? []
        lastTraditionalBranchID = try container.decodeIfPresent(
            String.self,
            forKey: .lastTraditionalBranchID
        )
        traditionalDividerWidth = try container.decodeIfPresent(
            Double.self,
            forKey: .traditionalDividerWidth
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(
            layoutAlgorithmVersion,
            forKey: .layoutAlgorithmVersion
        )
        try container.encode(nodePositions, forKey: .nodePositions)
        try container.encode(groups, forKey: .groups)
        try container.encode(regions, forKey: .regions)
        try container.encode(edgePorts, forKey: .edgePorts)
        try container.encode(boundaryPorts, forKey: .boundaryPorts)
        try container.encode(lineStyle, forKey: .lineStyle)
        try container.encode(viewMode, forKey: .viewMode)
        try container.encode(
            CodableViewport(canvasViewport),
            forKey: .canvasViewport
        )
        try container.encode(
            manuallyPositionedHashes,
            forKey: .manuallyPositionedHashes
        )
        try container.encode(
            pinnedTraditionalBranchIDs,
            forKey: .pinnedTraditionalBranchIDs
        )
        try container.encodeIfPresent(
            lastTraditionalBranchID,
            forKey: .lastTraditionalBranchID
        )
        try container.encodeIfPresent(
            traditionalDividerWidth,
            forKey: .traditionalDividerWidth
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
    case shallowBoundary(String)
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
    public let origin: GraphPoint
    public let memberHashes: Set<String>
    public let relativePositions: [String: GraphPoint]

    public init(
        id: UUID,
        title: String,
        rect: GraphRect,
        memberCount: Int,
        isCollapsed: Bool,
        origin: GraphPoint? = nil,
        memberHashes: Set<String>? = nil,
        relativePositions: [String: GraphPoint] = [:]
    ) {
        self.id = id
        self.title = title
        self.rect = rect
        self.memberCount = memberCount
        self.isCollapsed = isCollapsed
        self.origin = origin ?? GraphPoint(x: rect.x, y: rect.y)
        self.memberHashes = memberHashes ?? Set(relativePositions.keys)
        self.relativePositions = relativePositions
    }
}

public struct CommitGraphVisibleShallowBoundaryEndpoint:
    Equatable,
    Identifiable,
    Sendable
{
    public var id: String { endpoint.id }

    public let endpoint: CommitGraphShallowBoundaryEndpoint
    public let position: GraphPoint

    public init(
        endpoint: CommitGraphShallowBoundaryEndpoint,
        position: GraphPoint
    ) {
        self.endpoint = endpoint
        self.position = position
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
    public let path: CommitGraphGeneratedPath?

    public init(
        id: String,
        source: CommitGraphEndpointID,
        target: CommitGraphEndpointID,
        kind: CommitGraphEdgeKind,
        colorIndex: Int,
        ports: CommitGraphEdgePorts,
        aggregateKey: CollapsedEdgeKey?,
        aggregateCount: Int,
        originalEdgeIDs: [String],
        path: CommitGraphGeneratedPath? = nil
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
        self.path = path
    }
}

public struct CommitGraphSceneProjection: Equatable, Sendable {
    public let nodes: [CommitGraphVisibleNode]
    public let groups: [CommitGraphVisibleGroup]
    public let regions: [CommitGraphRegionMarker]
    public let shallowBoundaryEndpoints:
        [CommitGraphVisibleShallowBoundaryEndpoint]
    public let edges: [CommitGraphVisibleEdge]
    public let lineStyle: CommitGraphLineStyle

    public init(
        nodes: [CommitGraphVisibleNode],
        groups: [CommitGraphVisibleGroup],
        regions: [CommitGraphRegionMarker] = [],
        shallowBoundaryEndpoints:
            [CommitGraphVisibleShallowBoundaryEndpoint] = [],
        edges: [CommitGraphVisibleEdge],
        lineStyle: CommitGraphLineStyle = .curve
    ) {
        self.nodes = nodes
        self.groups = groups
        self.regions = regions
        self.shallowBoundaryEndpoints = shallowBoundaryEndpoints
        self.edges = edges
        self.lineStyle = lineStyle
    }
}

enum CommitGraphSceneGeometry {
    static let nodeWidth = 224.0
    static let nodeHeight = 74.0
    static let collapsedGroupWidth = 224.0
    static let collapsedGroupHeight = 92.0
    static let groupPadding = 30.0
    static let groupHeaderHeight = 34.0

    static func nodeRect(center: GraphPoint) -> GraphRect {
        GraphRect(
            x: center.x - nodeWidth / 2,
            y: center.y - nodeHeight / 2,
            width: nodeWidth,
            height: nodeHeight
        )
    }

    static func shallowBoundaryPosition(
        endpoint: CommitGraphShallowBoundaryEndpoint,
        layout: CommitGraphLayoutResult,
        scene: CommitGraphSceneState
    ) -> GraphPoint? {
        guard let laidOutChild = layout.node(hash: endpoint.childHash) else {
            return nil
        }
        if let group = scene.groups.first(where: {
            $0.memberHashes.contains(endpoint.childHash)
        }) {
            if group.isCollapsed {
                let groupRect = collapsedGroupRect(group)
                return shallowBoundaryPosition(
                    originalPosition: GraphPoint(
                        x: endpoint.x,
                        y: endpoint.y
                    ),
                    originalAnchor: GraphPoint(
                        x: laidOutChild.x,
                        y: laidOutChild.y
                    ),
                    updatedAnchor: GraphPoint(
                        x: groupRect.midpointX,
                        y: groupRect.minimumY
                    )
                )
            }
            guard let childPosition = group.absolutePosition(
                for: endpoint.childHash
            ) else {
                return nil
            }
            return shallowBoundaryPosition(
                originalPosition: GraphPoint(x: endpoint.x, y: endpoint.y),
                originalAnchor: GraphPoint(
                    x: laidOutChild.x,
                    y: laidOutChild.y
                ),
                updatedAnchor: childPosition
            )
        }
        let childPosition = scene.nodePositions[endpoint.childHash]
            ?? GraphPoint(x: laidOutChild.x, y: laidOutChild.y)
        return shallowBoundaryPosition(
            originalPosition: GraphPoint(x: endpoint.x, y: endpoint.y),
            originalAnchor: GraphPoint(
                x: laidOutChild.x,
                y: laidOutChild.y
            ),
            updatedAnchor: childPosition
        )
    }

    static func shallowBoundaryPosition(
        originalPosition: GraphPoint,
        originalAnchor: GraphPoint,
        updatedAnchor: GraphPoint
    ) -> GraphPoint {
        return GraphPoint(
            x: originalPosition.x + updatedAnchor.x - originalAnchor.x,
            y: originalPosition.y + updatedAnchor.y - originalAnchor.y
        )
    }

    static func shallowBoundaryRect(center: GraphPoint) -> GraphRect {
        GraphRect(
            x: center.x - 80,
            y: center.y - 18,
            width: 160,
            height: 36
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
        expandedGroupRect(
            origin: group.origin,
            relativePositions: group.relativePositions
        )
    }

    static func expandedGroupRect(
        origin: GraphPoint,
        relativePositions: [String: GraphPoint]
    ) -> GraphRect {
        let points = relativePositions.values
        guard let minimumX = points.map(\.x).min(),
              let maximumX = points.map(\.x).max(),
              let minimumY = points.map(\.y).min(),
              let maximumY = points.map(\.y).max()
        else {
            return GraphRect(
                x: origin.x,
                y: origin.y,
                width: collapsedGroupWidth,
                height: collapsedGroupHeight
            )
        }
        return GraphRect(
            x: origin.x + minimumX
                - nodeWidth / 2
                - groupPadding,
            y: origin.y + minimumY
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
