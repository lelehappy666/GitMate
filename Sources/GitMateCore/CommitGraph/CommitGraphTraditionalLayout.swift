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

public struct CommitGraphTraditionalLayoutResult: Equatable, Sendable {
    public let rows: [CommitGraphTraditionalRow]
    public let maximumLane: Int

    private let rowIndexByHash: [String: Int]

    public init(rows: [CommitGraphTraditionalRow], maximumLane: Int) {
        self.rows = rows
        self.maximumLane = max(maximumLane, 0)
        rowIndexByHash = Dictionary(
            rows.enumerated().map {
                ($0.element.commit.fullHash, $0.offset)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func row(hash: String) -> CommitGraphTraditionalRow? {
        guard let index = rowIndexByHash[hash] else { return nil }
        return rows[index]
    }
}

public struct CommitGraphTraditionalLayout: Sendable {
    public init() {}

    public func layout(
        topology: CommitGraphLaneTopology
    ) -> CommitGraphTraditionalLayoutResult {
        CommitGraphTraditionalLayoutResult(
            rows: topology.rowsNewestFirst.enumerated().map { index, row in
                CommitGraphTraditionalRow(
                    commit: row.commit,
                    row: index,
                    lane: row.lane,
                    colorIndex: row.colorIndex,
                    connections: row.connections
                )
            },
            maximumLane: topology.maximumLane
        )
    }
}
