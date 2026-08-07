import Foundation

public struct CommitGraphLaneConnection:
    Identifiable,
    Equatable,
    Sendable
{
    public var id: String {
        "\(childHash)->\(parentHash)#\(parentIndex)"
    }

    public let childHash: String
    public let parentHash: String
    public let parentIndex: Int
    public let sourceLane: Int
    public let targetLane: Int
    public let kind: CommitGraphEdgeKind
    public let colorIndex: Int

    public init(
        childHash: String,
        parentHash: String,
        parentIndex: Int,
        sourceLane: Int,
        targetLane: Int,
        kind: CommitGraphEdgeKind,
        colorIndex: Int
    ) {
        self.childHash = childHash
        self.parentHash = parentHash
        self.parentIndex = parentIndex
        self.sourceLane = sourceLane
        self.targetLane = targetLane
        self.kind = kind
        self.colorIndex = colorIndex
    }
}

public struct CommitGraphLaneRow: Equatable, Sendable {
    public let commit: GitCommit
    public let lane: Int
    public let colorIndex: Int
    public let connections: [CommitGraphLaneConnection]

    public init(
        commit: GitCommit,
        lane: Int,
        colorIndex: Int,
        connections: [CommitGraphLaneConnection]
    ) {
        self.commit = commit
        self.lane = lane
        self.colorIndex = colorIndex
        self.connections = connections
    }
}

public struct CommitGraphLaneTopology: Equatable, Sendable {
    public let rowsNewestFirst: [CommitGraphLaneRow]
    public let maximumLane: Int

    private let rowIndexByHash: [String: Int]

    public init(
        rowsNewestFirst: [CommitGraphLaneRow],
        maximumLane: Int
    ) {
        self.rowsNewestFirst = rowsNewestFirst
        self.maximumLane = max(maximumLane, 0)
        rowIndexByHash = Dictionary(
            rowsNewestFirst.enumerated().map {
                ($0.element.commit.fullHash, $0.offset)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func row(hash: String) -> CommitGraphLaneRow? {
        guard let index = rowIndexByHash[hash] else { return nil }
        return rowsNewestFirst[index]
    }

    public static func build(
        snapshot: CommitGraphSnapshot
    ) -> CommitGraphLaneTopology {
        let commits = uniqueCommits(snapshot.commitsNewestFirst)
        guard !commits.isEmpty else {
            return CommitGraphLaneTopology(
                rowsNewestFirst: [],
                maximumLane: 0
            )
        }

        let commitsByHash = Dictionary(
            commits.map { ($0.fullHash, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let knownHashes = Set(commitsByHash.keys)
        let defaultTarget = defaultTargetHash(
            fingerprint: snapshot.fingerprint,
            knownHashes: knownHashes,
            fallback: commits[0].fullHash
        )
        let coreHashes = firstParentChain(
            from: defaultTarget,
            commitsByHash: commitsByHash
        )
        let defaultIdentity = defaultBranchIdentity(
            fingerprint: snapshot.fingerprint,
            targetHash: defaultTarget
        )
        let referenceIdentityByHash = referenceIdentities(
            fingerprint: snapshot.fingerprint,
            knownHashes: knownHashes
        )
        let hashesWithKnownChildren = Set(
            commits.flatMap { commit in
                commit.parentHashes.filter { knownHashes.contains($0) }
            }
        )
        let startingHashes = commits
            .map(\.fullHash)
            .filter {
                !coreHashes.contains($0)
                    && !hashesWithKnownChildren.contains($0)
            }
            .sorted {
                let firstIdentity = referenceIdentityByHash[$0] ?? $0
                let secondIdentity = referenceIdentityByHash[$1] ?? $1
                if firstIdentity != secondIdentity {
                    return firstIdentity < secondIdentity
                }
                return $0 < $1
            }
        let startingLaneByHash = Dictionary(
            uniqueKeysWithValues: startingHashes.enumerated().map {
                ($0.element, $0.offset + 1)
            }
        )

        var allocator = CommitGraphLaneAllocator(
            firstUnreservedLane: startingHashes.count + 1
        )
        var laneByPendingHash: [String: Int] = [:]
        var identityByPendingHash: [String: String] = [:]

        var rows: [CommitGraphLaneRow] = []
        rows.reserveCapacity(commits.count)
        var maximumLane = allocator.maximumAllocatedLane

        for commit in commits {
            let isCoreCommit = coreHashes.contains(commit.fullHash)
            let assignedLane = laneByPendingHash.removeValue(
                forKey: commit.fullHash
            )
            let lane = isCoreCommit
                ? 0
                : (assignedLane
                    ?? startingLaneByHash[commit.fullHash]
                    ?? allocator.allocate())
            let identity = isCoreCommit
                ? defaultIdentity
                : (identityByPendingHash.removeValue(
                    forKey: commit.fullHash
                ) ?? referenceIdentityByHash[commit.fullHash]
                    ?? branchIdentity(for: commit))
            let colorIndex = stableColorIndex(identity)
            maximumLane = max(maximumLane, lane)
            var keepsCurrentLaneActive = false
            var connections: [CommitGraphLaneConnection] = []
            connections.reserveCapacity(commit.parentHashes.count)

            for (parentIndex, parentHash) in commit.parentHashes.enumerated() {
                let parentIsKnown = knownHashes.contains(parentHash)
                let targetLane: Int
                let targetIdentity: String

                if coreHashes.contains(parentHash) {
                    targetLane = 0
                    targetIdentity = defaultIdentity
                } else if let existingLane = laneByPendingHash[parentHash] {
                    targetLane = existingLane
                    targetIdentity = identityByPendingHash[parentHash]
                        ?? parentHash
                } else if parentIndex == 0 {
                    targetLane = lane
                    targetIdentity = identity
                } else {
                    targetLane = allocator.allocate()
                    targetIdentity = referenceIdentityByHash[parentHash]
                        ?? parentHash
                }

                if parentIsKnown, laneByPendingHash[parentHash] == nil {
                    laneByPendingHash[parentHash] = targetLane
                    identityByPendingHash[parentHash] = targetIdentity
                } else if !parentIsKnown, targetLane > 0,
                          targetLane != lane {
                    allocator.release(targetLane)
                }
                if parentIsKnown, targetLane == lane {
                    keepsCurrentLaneActive = true
                }
                maximumLane = max(maximumLane, targetLane)
                connections.append(
                    CommitGraphLaneConnection(
                        childHash: commit.fullHash,
                        parentHash: parentHash,
                        parentIndex: parentIndex,
                        sourceLane: lane,
                        targetLane: targetLane,
                        kind: parentIndex == 0 ? .parent : .merge,
                        colorIndex: parentIndex == 0
                            ? colorIndex
                            : stableColorIndex(targetIdentity)
                    )
                )
            }

            if lane > 0, !keepsCurrentLaneActive {
                allocator.release(lane)
            }
            rows.append(
                CommitGraphLaneRow(
                    commit: commit,
                    lane: lane,
                    colorIndex: colorIndex,
                    connections: connections
                )
            )
        }

        return CommitGraphLaneTopology(
            rowsNewestFirst: rows,
            maximumLane: maximumLane
        )
    }

    private static func uniqueCommits(_ commits: [GitCommit]) -> [GitCommit] {
        var seen: Set<String> = []
        return commits.filter { seen.insert($0.fullHash).inserted }
    }

    private static func defaultTargetHash(
        fingerprint: CommitGraphReferenceFingerprint,
        knownHashes: Set<String>,
        fallback: String
    ) -> String {
        let references = fingerprint.references
        let prioritizedNames = [
            "refs/remotes/origin/HEAD",
            "refs/heads/main",
            "refs/remotes/origin/main",
            "refs/heads/master",
            "refs/remotes/origin/master"
        ]
        if let originHead = references.first(where: {
            $0.name == prioritizedNames[0]
                && knownHashes.contains($0.targetHash)
        }) {
            return originHead.targetHash
        }
        if let headHash = fingerprint.headHash,
           knownHashes.contains(headHash) {
            return headHash
        }
        for name in prioritizedNames.dropFirst() {
            if let reference = references.first(where: {
                $0.name == name && knownHashes.contains($0.targetHash)
            }) {
                return reference.targetHash
            }
        }
        if let namedMainOrMaster = references
            .filter({
                knownHashes.contains($0.targetHash)
                    && ($0.name.hasSuffix("/main")
                        || $0.name.hasSuffix("/master"))
            })
            .sorted(by: { $0.name < $1.name })
            .first {
            return namedMainOrMaster.targetHash
        }
        if let firstReference = references
            .filter({ knownHashes.contains($0.targetHash) })
            .sorted(by: { $0.name < $1.name })
            .first {
            return firstReference.targetHash
        }
        return fallback
    }

    private static func defaultBranchIdentity(
        fingerprint: CommitGraphReferenceFingerprint,
        targetHash: String
    ) -> String {
        if let originHead = fingerprint.references.first(where: {
            $0.name == "refs/remotes/origin/HEAD"
                && $0.targetHash == targetHash
        }) {
            return originHead.name
        }
        if let headName = fingerprint.headName {
            return "refs/heads/\(headName)"
        }
        return fingerprint.references
            .filter { $0.targetHash == targetHash }
            .map(\.name)
            .sorted()
            .first ?? targetHash
    }

    private static func referenceIdentities(
        fingerprint: CommitGraphReferenceFingerprint,
        knownHashes: Set<String>
    ) -> [String: String] {
        var identities: [String: String] = [:]
        for reference in fingerprint.references
            where knownHashes.contains(reference.targetHash) {
            if let current = identities[reference.targetHash] {
                identities[reference.targetHash] = min(current, reference.name)
            } else {
                identities[reference.targetHash] = reference.name
            }
        }
        return identities
    }

    private static func firstParentChain(
        from targetHash: String,
        commitsByHash: [String: GitCommit]
    ) -> Set<String> {
        var chain: Set<String> = []
        var currentHash: String? = targetHash
        while let hash = currentHash,
              chain.insert(hash).inserted,
              let commit = commitsByHash[hash] {
            currentHash = commit.parentHashes.first
        }
        return chain
    }

    private static func branchIdentity(for commit: GitCommit) -> String {
        commit.decorations
            .filter { !$0.hasPrefix("tag:") }
            .sorted()
            .first ?? commit.fullHash
    }

    private static func stableColorIndex(_ value: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % 6)
    }
}

private struct CommitGraphLaneAllocator {
    private var freeLanes: [Int] = []
    private var freeLaneSet: Set<Int> = []
    private var nextLane: Int

    private(set) var maximumAllocatedLane: Int

    init(firstUnreservedLane: Int = 1) {
        nextLane = max(firstUnreservedLane, 1)
        maximumAllocatedLane = nextLane - 1
    }

    mutating func allocate() -> Int {
        let lane: Int
        if let minimum = popMinimum() {
            lane = minimum
        } else {
            lane = nextLane
            nextLane += 1
        }
        maximumAllocatedLane = max(maximumAllocatedLane, lane)
        return lane
    }

    mutating func release(_ lane: Int) {
        guard lane > 0, freeLaneSet.insert(lane).inserted else { return }
        freeLanes.append(lane)
        siftUp(from: freeLanes.count - 1)
    }

    private mutating func popMinimum() -> Int? {
        guard let minimum = freeLanes.first else { return nil }
        freeLaneSet.remove(minimum)
        if freeLanes.count == 1 {
            freeLanes.removeLast()
            return minimum
        }
        freeLanes[0] = freeLanes.removeLast()
        siftDown(from: 0)
        return minimum
    }

    private mutating func siftUp(from startIndex: Int) {
        var child = startIndex
        while child > 0 {
            let parent = (child - 1) / 2
            guard freeLanes[child] < freeLanes[parent] else { return }
            freeLanes.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(from startIndex: Int) {
        var parent = startIndex
        while true {
            let left = parent * 2 + 1
            guard left < freeLanes.count else { return }
            let right = left + 1
            let child = right < freeLanes.count
                && freeLanes[right] < freeLanes[left]
                ? right
                : left
            guard freeLanes[child] < freeLanes[parent] else { return }
            freeLanes.swapAt(child, parent)
            parent = child
        }
    }
}
