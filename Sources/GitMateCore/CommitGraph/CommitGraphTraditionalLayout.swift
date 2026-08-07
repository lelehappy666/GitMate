import Foundation

public struct CommitGraphTraditionalRow:
    Identifiable,
    Equatable,
    Sendable
{
    public var id: String { commit.fullHash }

    public let commit: GitCommit
    public let row: Int
    public let lane: Int
    public let colorIndex: Int
    public let connections: [CommitGraphLaneConnection]

    public init(
        commit: GitCommit,
        row: Int,
        lane: Int,
        colorIndex: Int,
        connections: [CommitGraphLaneConnection]
    ) {
        self.commit = commit
        self.row = row
        self.lane = lane
        self.colorIndex = colorIndex
        self.connections = connections
    }
}

public struct CommitGraphTraditionalConnectionSpan:
    Identifiable,
    Equatable,
    Sendable
{
    public var id: String { connection.id }

    public let connection: CommitGraphLaneConnection
    public let sourceRow: Int
    public let targetRow: Int

    public init(
        connection: CommitGraphLaneConnection,
        sourceRow: Int,
        targetRow: Int
    ) {
        self.connection = connection
        self.sourceRow = sourceRow
        self.targetRow = targetRow
    }
}

public struct CommitGraphTraditionalShallowBoundaryEndpoint:
    Identifiable,
    Equatable,
    Sendable
{
    public var id: String { relation.id }

    public let relation: CommitGraphShallowBoundaryRelation
    public let row: Int
    public let lane: Int

    public var childHash: String { relation.childHash }
    public var missingParentHash: String { relation.missingParentHash }
    public var colorIndex: Int { relation.colorIndex }

    public init(
        relation: CommitGraphShallowBoundaryRelation,
        row: Int,
        lane: Int
    ) {
        self.relation = relation
        self.row = row
        self.lane = lane
    }
}

public enum CommitGraphTraditionalReferenceKind:
    Equatable,
    Sendable
{
    case head
    case localBranch
    case remoteBranch
    case tag
}

public struct CommitGraphTraditionalReference:
    Equatable,
    Sendable
{
    public let name: String
    public let kind: CommitGraphTraditionalReferenceKind

    public init(
        name: String,
        kind: CommitGraphTraditionalReferenceKind
    ) {
        self.name = name
        self.kind = kind
    }
}

public struct CommitGraphTraditionalGroupBadge:
    Equatable,
    Sendable
{
    public let title: String
    public let isCollapsed: Bool
    public let groupID: UUID

    public init(
        title: String,
        isCollapsed: Bool,
        groupID: UUID
    ) {
        self.title = title
        self.isCollapsed = isCollapsed
        self.groupID = groupID
    }
}

public struct CommitGraphTraditionalLayoutResult: Equatable, Sendable {
    public let rows: [CommitGraphTraditionalRow]
    public let maximumLane: Int
    public let shallowBoundaryEndpoints:
        [CommitGraphTraditionalShallowBoundaryEndpoint]
    public let contentRowCount: Int

    private let rowIndexByHash: [String: Int]
    private let connectionSpanStorage:
        [CommitGraphTraditionalConnectionSpan]
    private let connectionIndex: CommitGraphTraditionalConnectionIndex
    private let referencesByHash:
        [String: [CommitGraphTraditionalReference]]

    public init(
        rows: [CommitGraphTraditionalRow],
        maximumLane: Int,
        shallowBoundaryEndpoints:
            [CommitGraphTraditionalShallowBoundaryEndpoint] = []
    ) {
        self.rows = rows
        self.maximumLane = max(maximumLane, 0)
        self.shallowBoundaryEndpoints = shallowBoundaryEndpoints
        contentRowCount = max(
            rows.count,
            (shallowBoundaryEndpoints.map(\.row).max() ?? -1) + 1
        )
        let builtRowIndexByHash = Dictionary(
            rows.enumerated().map {
                ($0.element.commit.fullHash, $0.offset)
            },
            uniquingKeysWith: { first, _ in first }
        )
        rowIndexByHash = builtRowIndexByHash
        connectionSpanStorage = rows.flatMap { row in
            row.connections.compactMap { connection in
                guard let targetRow = builtRowIndexByHash[
                    connection.parentHash
                ] else {
                    return nil
                }
                return CommitGraphTraditionalConnectionSpan(
                    connection: connection,
                    sourceRow: row.row,
                    targetRow: targetRow
                )
            }
        }
        connectionIndex = CommitGraphTraditionalConnectionIndex(
            spans: connectionSpanStorage
        )
        referencesByHash = Dictionary(
            uniqueKeysWithValues: rows.map { row in
                (
                    row.commit.fullHash,
                    Self.references(from: row.commit.decorations)
                )
            }
        )
    }

    public func row(hash: String) -> CommitGraphTraditionalRow? {
        guard let index = rowIndexByHash[hash] else { return nil }
        return rows[index]
    }

    public func connectionSpans(
        intersecting rows: Range<Int>
    ) -> [CommitGraphTraditionalConnectionSpan] {
        connectionIndex.indices(intersecting: rows).map {
            connectionSpanStorage[$0]
        }
    }

    public func references(
        hash: String
    ) -> [CommitGraphTraditionalReference] {
        referencesByHash[hash] ?? []
    }

    private static func references(
        from decorations: [String]
    ) -> [CommitGraphTraditionalReference] {
        var result: [CommitGraphTraditionalReference] = []
        var seen = Set<String>()

        func append(
            _ name: String,
            kind: CommitGraphTraditionalReferenceKind
        ) {
            let normalized = name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !normalized.isEmpty else { return }
            let key = "\(String(describing: kind)):\(normalized)"
            guard seen.insert(key).inserted else { return }
            result.append(
                CommitGraphTraditionalReference(
                    name: normalized,
                    kind: kind
                )
            )
        }

        for decoration in decorations {
            let value = decoration.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if value.hasPrefix("HEAD -> ") {
                append("HEAD", kind: .head)
                append(
                    String(value.dropFirst("HEAD -> ".count)),
                    kind: .localBranch
                )
            } else if value == "HEAD" {
                append("HEAD", kind: .head)
            } else if value.hasPrefix("tag: ") {
                append(
                    String(value.dropFirst("tag: ".count)),
                    kind: .tag
                )
            } else if value.hasPrefix("refs/tags/") {
                append(
                    String(value.dropFirst("refs/tags/".count)),
                    kind: .tag
                )
            } else if value.hasPrefix("refs/remotes/") {
                append(
                    String(value.dropFirst("refs/remotes/".count)),
                    kind: .remoteBranch
                )
            } else if value.hasPrefix("refs/heads/") {
                append(
                    String(value.dropFirst("refs/heads/".count)),
                    kind: .localBranch
                )
            } else if value.contains("/") {
                append(value, kind: .remoteBranch)
            } else {
                append(value, kind: .localBranch)
            }
        }
        return result
    }
}

private struct CommitGraphTraditionalConnectionIndex:
    Equatable,
    Sendable
{
    private struct Interval: Equatable, Sendable {
        let spanIndex: Int
        let minimumRow: Int
        let maximumRow: Int

        var midpoint: Int {
            minimumRow + (maximumRow - minimumRow) / 2
        }
    }

    private indirect enum Node: Equatable, Sendable {
        case empty
        case branch(
            center: Int,
            crossingByMinimumRow: [Interval],
            crossingByMaximumRow: [Interval],
            left: Node,
            right: Node
        )

        func query(
            minimumRow: Int,
            maximumRow: Int,
            into result: inout [Int]
        ) {
            switch self {
            case .empty:
                return
            case let .branch(
                center,
                crossingByMinimumRow,
                crossingByMaximumRow,
                left,
                right
            ):
                if maximumRow < center {
                    for interval in crossingByMinimumRow {
                        guard interval.minimumRow <= maximumRow else {
                            break
                        }
                        result.append(interval.spanIndex)
                    }
                    left.query(
                        minimumRow: minimumRow,
                        maximumRow: maximumRow,
                        into: &result
                    )
                } else if minimumRow > center {
                    for interval in crossingByMaximumRow {
                        guard interval.maximumRow >= minimumRow else {
                            break
                        }
                        result.append(interval.spanIndex)
                    }
                    right.query(
                        minimumRow: minimumRow,
                        maximumRow: maximumRow,
                        into: &result
                    )
                } else {
                    result.append(
                        contentsOf: crossingByMinimumRow.map(\.spanIndex)
                    )
                    left.query(
                        minimumRow: minimumRow,
                        maximumRow: maximumRow,
                        into: &result
                    )
                    right.query(
                        minimumRow: minimumRow,
                        maximumRow: maximumRow,
                        into: &result
                    )
                }
            }
        }
    }

    private let root: Node

    init(spans: [CommitGraphTraditionalConnectionSpan]) {
        root = Self.build(
            spans.enumerated().map { index, span in
                Interval(
                    spanIndex: index,
                    minimumRow: min(span.sourceRow, span.targetRow),
                    maximumRow: max(span.sourceRow, span.targetRow)
                )
            }
        )
    }

    func indices(intersecting rows: Range<Int>) -> [Int] {
        guard !rows.isEmpty else { return [] }
        var result: [Int] = []
        root.query(
            minimumRow: rows.lowerBound,
            maximumRow: rows.upperBound - 1,
            into: &result
        )
        return result.sorted()
    }

    private static func build(_ intervals: [Interval]) -> Node {
        guard !intervals.isEmpty else { return .empty }
        let sortedMidpoints = intervals.map(\.midpoint).sorted()
        let center = sortedMidpoints[sortedMidpoints.count / 2]
        var left: [Interval] = []
        var right: [Interval] = []
        var crossing: [Interval] = []
        left.reserveCapacity(intervals.count / 2)
        right.reserveCapacity(intervals.count / 2)
        crossing.reserveCapacity(intervals.count / 2)

        for interval in intervals {
            if interval.maximumRow < center {
                left.append(interval)
            } else if interval.minimumRow > center {
                right.append(interval)
            } else {
                crossing.append(interval)
            }
        }
        return .branch(
            center: center,
            crossingByMinimumRow: crossing.sorted {
                if $0.minimumRow != $1.minimumRow {
                    return $0.minimumRow < $1.minimumRow
                }
                return $0.spanIndex < $1.spanIndex
            },
            crossingByMaximumRow: crossing.sorted {
                if $0.maximumRow != $1.maximumRow {
                    return $0.maximumRow > $1.maximumRow
                }
                return $0.spanIndex < $1.spanIndex
            },
            left: build(left),
            right: build(right)
        )
    }
}

public struct CommitGraphTraditionalLayout: Sendable {
    public init() {}

    public func layout(
        topology: CommitGraphLaneTopology
    ) -> CommitGraphTraditionalLayoutResult {
        let rows = topology.rowsNewestFirst.enumerated().map { index, row in
            CommitGraphTraditionalRow(
                commit: row.commit,
                row: index,
                lane: row.lane,
                colorIndex: row.colorIndex,
                connections: row.connections
            )
        }
        let rowByHash = Dictionary(
            uniqueKeysWithValues: rows.map { ($0.commit.fullHash, $0) }
        )
        let endpoints = topology.shallowBoundaryRelations.enumerated().compactMap {
            index,
            relation -> CommitGraphTraditionalShallowBoundaryEndpoint? in
            guard rowByHash[relation.childHash] != nil else { return nil }
            return CommitGraphTraditionalShallowBoundaryEndpoint(
                relation: relation,
                row: rows.count + index,
                lane: relation.targetLane
            )
        }
        return CommitGraphTraditionalLayoutResult(
            rows: rows,
            maximumLane: topology.maximumLane,
            shallowBoundaryEndpoints: endpoints
        )
    }
}
