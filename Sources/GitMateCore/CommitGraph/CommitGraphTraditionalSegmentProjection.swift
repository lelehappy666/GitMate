import Foundation

/// 传统提交图的最终泳道投影。
///
/// 完整快照变化时构建一次；绘制阶段只使用哈希表查询，不再重新判断
/// 提交属于哪个分支。
public struct CommitGraphTraditionalSegmentProjection:
    Equatable,
    Sendable
{
    public let connections: [CommitGraphLaneConnection]
    public let maximumLane: Int

    private let laneByHash: [String: Int]
    private let colorIndexByHash: [String: Int]
    private let connectionByPair: [ConnectionPair: CommitGraphLaneConnection]

    public init(
        laneByHash: [String: Int],
        colorIndexByHash: [String: Int],
        connections: [CommitGraphLaneConnection],
        maximumLane: Int
    ) {
        self.laneByHash = laneByHash
        self.colorIndexByHash = colorIndexByHash
        self.connections = connections
        self.maximumLane = max(maximumLane, 0)
        connectionByPair = Dictionary(
            connections.map {
                (ConnectionPair(child: $0.childHash, parent: $0.parentHash), $0)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public static let empty = CommitGraphTraditionalSegmentProjection(
        laneByHash: [:],
        colorIndexByHash: [:],
        connections: [],
        maximumLane: 0
    )

    public func lane(for hash: String) -> Int? {
        laneByHash[hash]
    }

    public func colorIndex(for hash: String) -> Int? {
        colorIndexByHash[hash]
    }

    public func connection(
        childHash: String,
        parentHash: String
    ) -> CommitGraphLaneConnection? {
        connectionByPair[
            ConnectionPair(child: childHash, parent: parentHash)
        ]
    }

    private struct ConnectionPair: Hashable, Sendable {
        let child: String
        let parent: String
    }
}

public enum CommitGraphTraditionalSegmentProjector {
    public static func project(
        topology: CommitGraphLaneTopology,
        catalog: CommitGraphBranchCatalog,
        branchProjection: CommitGraphTraditionalBranchProjection
    ) -> CommitGraphTraditionalSegmentProjection {
        guard !topology.rowsNewestFirst.isEmpty else { return .empty }

        let rowsByHash = Dictionary(
            topology.rowsNewestFirst.map { ($0.commit.fullHash, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let rowIndexByHash = Dictionary(
            topology.rowsNewestFirst.enumerated().map {
                ($0.element.commit.fullHash, $0.offset)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var laneByHash: [String: Int] = [:]
        laneByHash.reserveCapacity(topology.rowsNewestFirst.count)

        for slot in branchProjection.slots where !slot.isPlaceholder {
            let branches = slot.branchIDs.compactMap(catalog.branch(id:))
            let tips = Set(branches.map(\.tipHash)).sorted {
                let firstRow = rowIndexByHash[$0] ?? Int.max
                let secondRow = rowIndexByHash[$1] ?? Int.max
                if firstRow != secondRow { return firstRow < secondRow }
                return $0 < $1
            }
            for tip in tips {
                claimFirstParentChain(
                    from: tip,
                    lane: slot.lane,
                    rowsByHash: rowsByHash,
                    laneByHash: &laneByHash
                )
            }
        }

        // deleted branch、Merge 侧链和 synthetic 组件不一定落在某个引用的
        // 第一父链上。目录已经为这些提交保留稳定成员身份，只领取尚未归属
        // 的提交，绝不会覆盖 main 已经领取的共享祖先。
        for slot in branchProjection.slots where !slot.isPlaceholder {
            let memberHashes = slot.branchIDs
                .compactMap(catalog.branch(id:))
                .flatMap(\.memberHashes)
                .sorted {
                    let firstRow = rowIndexByHash[$0] ?? Int.max
                    let secondRow = rowIndexByHash[$1] ?? Int.max
                    if firstRow != secondRow { return firstRow < secondRow }
                    return $0 < $1
                }
            for hash in memberHashes where rowsByHash[hash] != nil {
                if laneByHash[hash] == nil { laneByHash[hash] = slot.lane }
            }
        }

        let firstRealLane = branchProjection.slots.first(where: {
            !$0.isPlaceholder
        })?.lane ?? 1
        for row in topology.rowsNewestFirst where laneByHash[row.commit.fullHash] == nil {
            if let branch = catalog.branch(containing: row.commit.fullHash),
               let lane = branchProjection.displayLane(for: branch.id) {
                laneByHash[row.commit.fullHash] = lane
            } else {
                laneByHash[row.commit.fullHash] = firstRealLane
            }
        }

        let colorIndexByHash = Dictionary(
            laneByHash.map { ($0.key, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        let connections = topology.rowsNewestFirst.flatMap { row in
            row.connections.compactMap { connection -> CommitGraphLaneConnection? in
                guard let sourceLane = laneByHash[connection.childHash],
                      let targetLane = laneByHash[connection.parentHash]
                else { return nil }
                return CommitGraphLaneConnection(
                    childHash: connection.childHash,
                    parentHash: connection.parentHash,
                    parentIndex: connection.parentIndex,
                    sourceLane: sourceLane,
                    targetLane: targetLane,
                    kind: connection.kind,
                    colorIndex: sourceLane
                )
            }
        }
        return CommitGraphTraditionalSegmentProjection(
            laneByHash: laneByHash,
            colorIndexByHash: colorIndexByHash,
            connections: connections,
            maximumLane: branchProjection.slots.map(\.lane).max() ?? 0
        )
    }

    private static func claimFirstParentChain(
        from tip: String,
        lane: Int,
        rowsByHash: [String: CommitGraphLaneRow],
        laneByHash: inout [String: Int]
    ) {
        var current: String? = tip
        var visited = Set<String>()
        while let hash = current,
              visited.insert(hash).inserted,
              laneByHash[hash] == nil,
              let row = rowsByHash[hash] {
            laneByHash[hash] = lane
            current = row.commit.parentHashes.first
        }
    }
}
