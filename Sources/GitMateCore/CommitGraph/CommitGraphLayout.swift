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
        snapshot: CommitGraphSnapshot
    ) -> CommitGraphLayoutResult {
        layout(
            topology: CommitGraphLaneTopology.build(snapshot: snapshot)
        )
    }

    public func layout(
        topology: CommitGraphLaneTopology
    ) -> CommitGraphLayoutResult {
        return layout(
            topology: topology,
            orderedRows: Array(topology.rowsNewestFirst.reversed()),
            preserving: nil
        )
    }

    public func layout(
        page: CommitGraphPage,
        preserving previous: CommitGraphLayoutResult? = nil
    ) -> CommitGraphLayoutResult {
        let pageOrder = uniqueCommits(page.commits)
        let commits = canonicalNewestFirst(pageOrder)
        let snapshot = CommitGraphSnapshot(
            repositoryPath: "",
            fingerprint: legacyFingerprint(commits: commits),
            commitsNewestFirst: commits,
            expectedCommitCount: commits.count,
            shallowBoundaryParentHashes: [],
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let topology = CommitGraphLaneTopology.build(snapshot: snapshot)
        return layout(
            topology: topology,
            orderedRows: pageOrder.compactMap {
                topology.row(hash: $0.fullHash)
            },
            preserving: previous
        )
    }

    private func layout(
        topology: CommitGraphLaneTopology,
        orderedRows: [CommitGraphLaneRow],
        preserving previous: CommitGraphLayoutResult?
    ) -> CommitGraphLayoutResult {
        let frozenColumns = Dictionary(
            uniqueKeysWithValues: (previous?.nodes ?? []).map {
                ($0.hash, $0.column)
            }
        )
        let columns = orderedRows.map { laneRow in
            frozenColumns[laneRow.commit.fullHash] ?? laneRow.lane
        }
        let branchSlots = columns.map(treeBranchSlot)
        let minimumSlot = min(branchSlots.min() ?? 0, 0)
        let maximumSlot = max(branchSlots.max() ?? 0, 0)
        let naturalWidth = 300
            + Double(maximumSlot - minimumSlot) * horizontalSpacing
        let contentWidth = max(1_040, naturalWidth)
        let horizontalCentering = (contentWidth - naturalWidth) / 2
        let trunkX = 150
            + Double(-minimumSlot) * horizontalSpacing
            + horizontalCentering

        let nodes = orderedRows.enumerated().map { rowIndex, laneRow in
            let commit = laneRow.commit
            let column = frozenColumns[commit.fullHash] ?? laneRow.lane
            let branchSlot = treeBranchSlot(column)
            return CommitGraphNode(
                hash: commit.fullHash,
                shortHash: commit.shortHash,
                subject: commit.subject,
                authorName: commit.authorName,
                authorEmail: commit.authorEmail,
                authoredAt: commit.authoredAt,
                decorations: commit.decorations,
                column: column,
                row: rowIndex,
                colorIndex: laneRow.colorIndex,
                x: trunkX + Double(branchSlot) * horizontalSpacing,
                y: 82 + Double(rowIndex) * verticalSpacing
            )
        }
        let edges = topology.rowsNewestFirst.flatMap { row in
            row.connections.map { connection in
                CommitGraphEdge(
                    id: connection.id,
                    childHash: connection.childHash,
                    parentHash: connection.parentHash,
                    kind: connection.kind,
                    colorIndex: connection.colorIndex
                )
            }
        }
        let nodesByHash = Dictionary(
            uniqueKeysWithValues: nodes.map { ($0.hash, $0) }
        )
        let shallowBoundaryEndpoints = topology.shallowBoundaryRelations
            .compactMap { relation -> CommitGraphShallowBoundaryEndpoint? in
                guard let child = nodesByHash[relation.childHash] else {
                    return nil
                }
                return CommitGraphShallowBoundaryEndpoint(
                    relation: relation,
                    x: trunkX + Double(treeBranchSlot(relation.targetLane))
                        * horizontalSpacing,
                    y: child.y - verticalSpacing * 0.65
                )
            }
        return CommitGraphLayoutResult(
            nodes: nodes,
            edges: edges,
            shallowBoundaryEndpoints: shallowBoundaryEndpoints,
            contentWidth: contentWidth,
            contentHeight: max(
                680,
                164 + Double(max(nodes.count - 1, 0)) * verticalSpacing
            )
        )
    }

    /// 主分支固定为 0 号树干，其他泳道依次向左、向右展开。
    /// 只改变画布坐标，不改变共享拓扑中的稳定泳道编号。
    private func treeBranchSlot(_ column: Int) -> Int {
        guard column > 0 else { return 0 }
        let distance = (column + 1) / 2
        return column.isMultiple(of: 2) ? distance : -distance
    }

    private func canonicalNewestFirst(_ commits: [GitCommit]) -> [GitCommit] {
        let unique = uniqueCommits(commits)
        let indexByHash = Dictionary(
            unique.enumerated().map { ($0.element.fullHash, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        var newestFirstViolations = 0
        var oldestFirstViolations = 0
        for commit in unique {
            guard let childIndex = indexByHash[commit.fullHash] else { continue }
            for parentHash in commit.parentHashes {
                guard let parentIndex = indexByHash[parentHash] else { continue }
                if childIndex > parentIndex {
                    newestFirstViolations += 1
                } else if childIndex < parentIndex {
                    oldestFirstViolations += 1
                }
            }
        }
        return newestFirstViolations > oldestFirstViolations
            ? Array(unique.reversed())
            : unique
    }

    private func uniqueCommits(_ commits: [GitCommit]) -> [GitCommit] {
        var seen: Set<String> = []
        return commits.filter { seen.insert($0.fullHash).inserted }
    }

    private func legacyFingerprint(
        commits: [GitCommit]
    ) -> CommitGraphReferenceFingerprint {
        var referencesByName: [String: CommitGraphReference] = [:]
        var headName: String?
        var headHash: String?

        for commit in commits {
            for decoration in commit.decorations {
                if decoration.hasPrefix("HEAD -> ") {
                    let name = String(decoration.dropFirst("HEAD -> ".count))
                    guard !name.isEmpty else { continue }
                    headName = name
                    headHash = commit.fullHash
                    let refName = "refs/heads/\(name)"
                    referencesByName[refName] = CommitGraphReference(
                        name: refName,
                        targetHash: commit.fullHash,
                        kind: .localBranch
                    )
                } else if decoration.hasPrefix("tag:")
                    || decoration == "HEAD" {
                    continue
                } else if decoration.contains("/") {
                    let refName = "refs/remotes/\(decoration)"
                    referencesByName[refName] = CommitGraphReference(
                        name: refName,
                        targetHash: commit.fullHash,
                        kind: .remoteBranch
                    )
                } else {
                    let refName = "refs/heads/\(decoration)"
                    referencesByName[refName] = CommitGraphReference(
                        name: refName,
                        targetHash: commit.fullHash,
                        kind: .localBranch
                    )
                }
            }
        }
        if headHash == nil {
            headHash = commits.first?.fullHash
        }
        return CommitGraphReferenceFingerprint(
            references: referencesByName.values.sorted { $0.name < $1.name },
            headName: headName,
            headHash: headHash,
            isShallow: false
        )
    }
}
