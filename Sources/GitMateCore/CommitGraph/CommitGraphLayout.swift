import Foundation

public struct CommitGraphLayout: Sendable {
    public let horizontalSpacing: Double
    public let verticalSpacing: Double

    public init(
        horizontalSpacing: Double = 250,
        verticalSpacing: Double = 126
    ) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    public func layout(
        page: CommitGraphPage,
        preserving previous: CommitGraphLayoutResult? = nil
    ) -> CommitGraphLayoutResult {
        let commits = uniqueCommits(page.commits)
        let frozenColumns = Dictionary(
            uniqueKeysWithValues: (previous?.nodes ?? []).map {
                ($0.hash, $0.column)
            }
        )
        var expectedColumns: [String: Int] = [:]
        var nodes: [CommitGraphNode] = []
        var edges: [CommitGraphEdge] = []

        for (row, commit) in commits.enumerated() {
            let occupiedColumns = Set(
                expectedColumns
                    .filter { $0.key != commit.fullHash }
                    .map(\.value)
            )
            let column = frozenColumns[commit.fullHash]
                ?? expectedColumns[commit.fullHash]
                ?? nearestFreeColumn(
                    to: 0,
                    occupied: occupiedColumns,
                    seed: stableHash(commit.fullHash)
                )
            expectedColumns[commit.fullHash] = nil

            let branchKey = commit.decorations.first ?? commit.fullHash
            nodes.append(
                CommitGraphNode(
                    hash: commit.fullHash,
                    shortHash: commit.shortHash,
                    subject: commit.subject,
                    authorName: commit.authorName,
                    authorEmail: commit.authorEmail,
                    authoredAt: commit.authoredAt,
                    decorations: commit.decorations,
                    column: column,
                    row: row,
                    colorIndex: stableHash(branchKey) % 6,
                    x: 150 + Double(column) * horizontalSpacing,
                    y: 82 + Double(row) * verticalSpacing
                )
            )

            for (parentIndex, parentHash) in commit.parentHashes.enumerated() {
                let kind: CommitGraphEdgeKind = parentIndex == 0
                    ? .parent
                    : .merge
                if frozenColumns[parentHash] == nil,
                   expectedColumns[parentHash] == nil {
                    if parentIndex == 0 {
                        expectedColumns[parentHash] = column
                    } else {
                        expectedColumns[parentHash] = nearestFreeColumn(
                            to: column,
                            occupied: Set(expectedColumns.values)
                                .union(frozenColumns.values),
                            seed: stableHash(parentHash)
                        )
                    }
                }
                let colorKey = parentIndex == 0
                    ? branchKey
                    : parentHash
                edges.append(
                    CommitGraphEdge(
                        id: "\(commit.fullHash)->\(parentHash)#\(parentIndex)",
                        childHash: commit.fullHash,
                        parentHash: parentHash,
                        kind: kind,
                        colorIndex: stableHash(colorKey) % 6
                    )
                )
            }
        }

        let maximumColumn = nodes.map(\.column).max() ?? 0
        return CommitGraphLayoutResult(
            nodes: nodes,
            edges: edges,
            contentWidth: max(
                1_040,
                300 + Double(maximumColumn) * horizontalSpacing
            ),
            contentHeight: max(
                680,
                164 + Double(max(nodes.count - 1, 0)) * verticalSpacing
            )
        )
    }

    private func uniqueCommits(_ commits: [GitCommit]) -> [GitCommit] {
        var seen: Set<String> = []
        return commits.filter { seen.insert($0.fullHash).inserted }
    }

    private func nearestFreeColumn(
        to preferred: Int,
        occupied: Set<Int>,
        seed: Int
    ) -> Int {
        guard occupied.contains(preferred) else {
            return preferred
        }
        for distance in 1...max(occupied.count + 1, 1) {
            let candidates = seed.isMultiple(of: 2)
                ? [preferred + distance, max(preferred - distance, 0)]
                : [max(preferred - distance, 0), preferred + distance]
            if let result = candidates.first(where: {
                $0 >= 0 && !occupied.contains($0)
            }) {
                return result
            }
        }
        return (occupied.max() ?? preferred) + 1
    }

    private func stableHash(_ value: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(Int.max))
    }
}
