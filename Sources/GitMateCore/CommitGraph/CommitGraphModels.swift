import Foundation

public struct GraphPoint: Codable, Equatable, Sendable {
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
    case shallowBoundary
}

/// 浅克隆中无法读取的父提交。
///
/// 它仅表示真实子提交与缺失父哈希之间的边界关系，绝不作为
/// `GitCommit` 或普通图节点参与提交计数、选择和分组。
public struct CommitGraphShallowBoundaryRelation:
    Identifiable,
    Equatable,
    Sendable
{
    public var id: String {
        "\(childHash)->\(missingParentHash)#\(parentIndex)"
    }

    public let childHash: String
    public let missingParentHash: String
    public let parentIndex: Int
    public let sourceLane: Int
    public let targetLane: Int
    public let colorIndex: Int

    public init(
        childHash: String,
        missingParentHash: String,
        parentIndex: Int,
        sourceLane: Int,
        targetLane: Int,
        colorIndex: Int
    ) {
        self.childHash = childHash
        self.missingParentHash = missingParentHash
        self.parentIndex = parentIndex
        self.sourceLane = sourceLane
        self.targetLane = targetLane
        self.colorIndex = colorIndex
    }
}

public struct CommitGraphShallowBoundaryEndpoint:
    Identifiable,
    Equatable,
    Sendable
{
    public var id: String { relation.id }

    public let relation: CommitGraphShallowBoundaryRelation
    public let x: Double
    public let y: Double

    public var childHash: String { relation.childHash }
    public var missingParentHash: String { relation.missingParentHash }
    public var colorIndex: Int { relation.colorIndex }

    public init(
        relation: CommitGraphShallowBoundaryRelation,
        x: Double,
        y: Double
    ) {
        self.relation = relation
        self.x = x
        self.y = y
    }
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
    public let shallowBoundaryEndpoints: [CommitGraphShallowBoundaryEndpoint]
    public let contentWidth: Double
    public let contentHeight: Double
    let spatialIndex: CommitGraphSpatialIndex

    public init(
        nodes: [CommitGraphNode] = [],
        edges: [CommitGraphEdge] = [],
        shallowBoundaryEndpoints: [CommitGraphShallowBoundaryEndpoint] = [],
        contentWidth: Double = 1_040,
        contentHeight: Double = 680
    ) {
        self.nodes = nodes
        self.edges = edges
        self.shallowBoundaryEndpoints = shallowBoundaryEndpoints
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
    private let edgeIntervalIndex: CommitGraphEdgeIntervalIndex

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

        var edgeIntervals: [CommitGraphEdgeInterval] = []
        for (index, edge) in edges.enumerated() {
            guard let childIndex = indicesByHash[edge.childHash],
                  let parentIndex = indicesByHash[edge.parentHash]
            else {
                continue
            }
            let childY = nodes[childIndex].y
            let parentY = nodes[parentIndex].y
            edgeIntervals.append(
                CommitGraphEdgeInterval(
                    index: index,
                    minimumY: min(childY, parentY),
                    maximumY: max(childY, parentY)
                )
            )
        }

        nodeIndexByHash = indicesByHash
        nodeIndicesByBucket = nodeBuckets
        edgeIntervalIndex = CommitGraphEdgeIntervalIndex(
            intervals: edgeIntervals
        )
    }

    func nodeIndices(minimumY: Double, maximumY: Double) -> [Int] {
        guard minimumY.isFinite,
              maximumY.isFinite,
              minimumY <= maximumY
        else {
            return []
        }
        let firstBucket = Self.bucket(for: minimumY)
        let lastBucket = Self.bucket(for: maximumY)
        return (firstBucket...lastBucket)
            .flatMap { nodeIndicesByBucket[$0] ?? [] }
            .sorted()
    }

    func edgeIndices(minimumY: Double, maximumY: Double) -> [Int] {
        edgeIntervalIndex.indices(
            minimumY: minimumY,
            maximumY: maximumY
        )
    }

    private static func bucket(for y: Double) -> Int {
        Int(floor(y / bucketHeight))
    }
}

private struct CommitGraphEdgeInterval: Equatable, Sendable {
    let index: Int
    let minimumY: Double
    let maximumY: Double

    var midpoint: Double {
        minimumY + (maximumY - minimumY) / 2
    }
}

private struct CommitGraphEdgeIntervalIndex: Equatable, Sendable {
    private struct Node: Equatable, Sendable {
        let center: Double
        let crossingByMinimumY: [CommitGraphEdgeInterval]
        let crossingByMaximumY: [CommitGraphEdgeInterval]
        let left: Int?
        let right: Int?
    }

    private let nodes: [Node]
    private let root: Int?

    init(intervals: [CommitGraphEdgeInterval]) {
        var builtNodes: [Node] = []

        func build(_ intervals: [CommitGraphEdgeInterval]) -> Int? {
            guard !intervals.isEmpty else { return nil }
            let midpoints = intervals.map(\.midpoint).sorted()
            let center = midpoints[midpoints.count / 2]
            var leftIntervals: [CommitGraphEdgeInterval] = []
            var rightIntervals: [CommitGraphEdgeInterval] = []
            var crossingIntervals: [CommitGraphEdgeInterval] = []

            for interval in intervals {
                if interval.maximumY < center {
                    leftIntervals.append(interval)
                } else if interval.minimumY > center {
                    rightIntervals.append(interval)
                } else {
                    crossingIntervals.append(interval)
                }
            }

            let left = build(leftIntervals)
            let right = build(rightIntervals)
            let index = builtNodes.count
            builtNodes.append(
                Node(
                    center: center,
                    crossingByMinimumY: crossingIntervals.sorted {
                        if $0.minimumY != $1.minimumY {
                            return $0.minimumY < $1.minimumY
                        }
                        return $0.index < $1.index
                    },
                    crossingByMaximumY: crossingIntervals.sorted {
                        if $0.maximumY != $1.maximumY {
                            return $0.maximumY > $1.maximumY
                        }
                        return $0.index < $1.index
                    },
                    left: left,
                    right: right
                )
            )
            return index
        }

        root = build(intervals)
        nodes = builtNodes
    }

    func indices(minimumY: Double, maximumY: Double) -> [Int] {
        guard minimumY.isFinite,
              maximumY.isFinite,
              minimumY <= maximumY,
              let root
        else {
            return []
        }
        var matches: [Int] = []
        query(
            nodeIndex: root,
            minimumY: minimumY,
            maximumY: maximumY,
            matches: &matches
        )
        return matches.sorted()
    }

    private func query(
        nodeIndex: Int,
        minimumY: Double,
        maximumY: Double,
        matches: inout [Int]
    ) {
        let node = nodes[nodeIndex]
        if maximumY < node.center {
            for interval in node.crossingByMinimumY {
                guard interval.minimumY <= maximumY else { break }
                matches.append(interval.index)
            }
            if let left = node.left {
                query(
                    nodeIndex: left,
                    minimumY: minimumY,
                    maximumY: maximumY,
                    matches: &matches
                )
            }
        } else if minimumY > node.center {
            for interval in node.crossingByMaximumY {
                guard interval.maximumY >= minimumY else { break }
                matches.append(interval.index)
            }
            if let right = node.right {
                query(
                    nodeIndex: right,
                    minimumY: minimumY,
                    maximumY: maximumY,
                    matches: &matches
                )
            }
        } else {
            matches.append(
                contentsOf: node.crossingByMinimumY.map(\.index)
            )
            if let left = node.left {
                query(
                    nodeIndex: left,
                    minimumY: minimumY,
                    maximumY: maximumY,
                    matches: &matches
                )
            }
            if let right = node.right {
                query(
                    nodeIndex: right,
                    minimumY: minimumY,
                    maximumY: maximumY,
                    matches: &matches
                )
            }
        }
    }
}
