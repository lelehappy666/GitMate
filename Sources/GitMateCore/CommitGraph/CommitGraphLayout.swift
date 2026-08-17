import Foundation

public struct CommitGraphLayout: Sendable {
    public let horizontalSpacing: Double
    public let verticalSpacing: Double

    public init(
        horizontalSpacing: Double = 500,
        verticalSpacing: Double = 252
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
        CommitGraphOrganizationTreeLayout(
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        ).layout(
            topology: topology,
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
        let organization = CommitGraphOrganizationTreeLayout(
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        ).layout(
            topology: topology,
            preserving: previous
        )
        let nodesByHash = Dictionary(
            organization.nodes.map { ($0.hash, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let orderedNodes = pageOrder.compactMap { nodesByHash[$0.fullHash] }
        return CommitGraphLayoutResult(
            nodes: orderedNodes,
            edges: organization.edges,
            shallowBoundaryEndpoints: organization.shallowBoundaryEndpoints,
            contentWidth: organization.contentWidth,
            contentHeight: organization.contentHeight,
            routeHintsByEdgeID: organization.routeHintsByEdgeID
        )
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
