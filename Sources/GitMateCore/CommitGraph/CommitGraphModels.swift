import Foundation

public struct GraphPoint: Equatable, Sendable {
    public static let zero = GraphPoint(x: 0, y: 0)

    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct GraphViewport: Equatable, Sendable {
    public var offsetX: Double
    public var offsetY: Double
    public var scale: Double

    public init(
        offsetX: Double = 0,
        offsetY: Double = 0,
        scale: Double = 1
    ) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.scale = scale
    }
}

public struct CommitGraphNode: Identifiable, Equatable, Sendable {
    public var id: String { hash }

    public let hash: String
    public let shortHash: String
    public let subject: String
    public let authorName: String
    public let authorEmail: String
    public let authoredAt: Date
    public let decorations: [String]
    public let column: Int
    public let row: Int
    public let colorIndex: Int
    public let x: Double
    public let y: Double

    public init(
        hash: String,
        shortHash: String,
        subject: String,
        authorName: String,
        authorEmail: String,
        authoredAt: Date,
        decorations: [String],
        column: Int,
        row: Int,
        colorIndex: Int,
        x: Double,
        y: Double
    ) {
        self.hash = hash
        self.shortHash = shortHash
        self.subject = subject
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.authoredAt = authoredAt
        self.decorations = decorations
        self.column = column
        self.row = row
        self.colorIndex = colorIndex
        self.x = x
        self.y = y
    }
}

public enum CommitGraphEdgeKind: Equatable, Sendable {
    case parent
    case merge
}

public struct CommitGraphEdge: Identifiable, Equatable, Sendable {
    public let id: String
    public let childHash: String
    public let parentHash: String
    public let kind: CommitGraphEdgeKind
    public let colorIndex: Int

    public init(
        id: String,
        childHash: String,
        parentHash: String,
        kind: CommitGraphEdgeKind,
        colorIndex: Int
    ) {
        self.id = id
        self.childHash = childHash
        self.parentHash = parentHash
        self.kind = kind
        self.colorIndex = colorIndex
    }
}

public struct CommitGraphLayoutResult: Equatable, Sendable {
    public let nodes: [CommitGraphNode]
    public let edges: [CommitGraphEdge]
    public let contentWidth: Double
    public let contentHeight: Double

    public init(
        nodes: [CommitGraphNode] = [],
        edges: [CommitGraphEdge] = [],
        contentWidth: Double = 1_040,
        contentHeight: Double = 680
    ) {
        self.nodes = nodes
        self.edges = edges
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
    }
}
