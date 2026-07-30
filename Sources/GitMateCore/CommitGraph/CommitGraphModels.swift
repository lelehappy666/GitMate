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
    let spatialIndex: CommitGraphSpatialIndex

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
        spatialIndex = CommitGraphSpatialIndex(
            nodes: nodes,
            edges: edges
        )
    }

    public func node(hash: String) -> CommitGraphNode? {
        guard let index = spatialIndex.nodeIndexByHash[hash] else {
            return nil
        }
        return nodes[index]
    }
}

struct CommitGraphSpatialIndex: Equatable, Sendable {
    static let bucketHeight = 256.0

    let nodeIndexByHash: [String: Int]
    private let nodeIndicesByBucket: [Int: [Int]]
    private let edgeIndicesByBucket: [Int: [Int]]

    init(nodes: [CommitGraphNode], edges: [CommitGraphEdge]) {
        let indicesByHash = Dictionary(
            nodes.enumerated().map {
                ($0.element.hash, $0.offset)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var nodeBuckets: [Int: [Int]] = [:]
        for (index, node) in nodes.enumerated() {
            nodeBuckets[Self.bucket(for: node.y), default: []].append(index)
        }

        var edgeBuckets: [Int: [Int]] = [:]
        for (index, edge) in edges.enumerated() {
            guard let childIndex = indicesByHash[edge.childHash],
                  let parentIndex = indicesByHash[edge.parentHash]
            else {
                continue
            }
            let childY = nodes[childIndex].y
            let parentY = nodes[parentIndex].y
            let firstBucket = Self.bucket(for: min(childY, parentY))
            let lastBucket = Self.bucket(for: max(childY, parentY))
            for bucket in firstBucket...lastBucket {
                edgeBuckets[bucket, default: []].append(index)
            }
        }

        nodeIndexByHash = indicesByHash
        nodeIndicesByBucket = nodeBuckets
        edgeIndicesByBucket = edgeBuckets
    }

    func nodeIndices(minimumY: Double, maximumY: Double) -> [Int] {
        indices(
            in: nodeIndicesByBucket,
            minimumY: minimumY,
            maximumY: maximumY,
            deduplicating: false
        )
    }

    func edgeIndices(minimumY: Double, maximumY: Double) -> [Int] {
        indices(
            in: edgeIndicesByBucket,
            minimumY: minimumY,
            maximumY: maximumY,
            deduplicating: true
        )
    }

    private func indices(
        in buckets: [Int: [Int]],
        minimumY: Double,
        maximumY: Double,
        deduplicating: Bool
    ) -> [Int] {
        guard minimumY.isFinite,
              maximumY.isFinite,
              minimumY <= maximumY
        else {
            return []
        }
        let firstBucket = Self.bucket(for: minimumY)
        let lastBucket = Self.bucket(for: maximumY)
        if deduplicating {
            var indices: Set<Int> = []
            for bucket in firstBucket...lastBucket {
                indices.formUnion(buckets[bucket] ?? [])
            }
            return indices.sorted()
        }
        return (firstBucket...lastBucket)
            .flatMap { buckets[$0] ?? [] }
            .sorted()
    }

    private static func bucket(for y: Double) -> Int {
        Int(floor(y / bucketHeight))
    }
}
