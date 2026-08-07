import Foundation

public enum CommitGraphSceneReconciler {
    public static func reconcile(
        scene: CommitGraphSceneState,
        oldSnapshot: CommitGraphSnapshot,
        newSnapshot: CommitGraphSnapshot,
        defaultPositions: [String: GraphPoint]
    ) -> CommitGraphSceneState {
        _ = oldSnapshot
        let availableHashes = Set(
            newSnapshot.commitsNewestFirst.map(\.fullHash)
        )
        var nodePositions: [String: GraphPoint] = [:]
        for hash in availableHashes {
            if let existing = scene.nodePositions[hash] {
                nodePositions[hash] = existing
            } else if let fallback = defaultPositions[hash] {
                nodePositions[hash] = fallback
            }
        }

        var claimedHashes: Set<String> = []
        var reconciledGroups: [CommitGraphGroup] = []
        for originalGroup in scene.groups {
            let survivingHashes = originalGroup.memberHashes
                .intersection(availableHashes)
                .subtracting(claimedHashes)
            var relativePositions: [String: GraphPoint] = [:]
            for hash in survivingHashes {
                if let relative = originalGroup.relativePositions[hash] {
                    relativePositions[hash] = relative
                } else if let absolute = nodePositions[hash] {
                    relativePositions[hash] = GraphPoint(
                        x: absolute.x - originalGroup.origin.x,
                        y: absolute.y - originalGroup.origin.y
                    )
                } else {
                    relativePositions[hash] = .zero
                }
            }

            if survivingHashes.count >= 2 {
                var group = originalGroup
                group.memberHashes = survivingHashes
                group.relativePositions = relativePositions
                reconciledGroups.append(group)
                claimedHashes.formUnion(survivingHashes)
                for hash in survivingHashes {
                    nodePositions.removeValue(forKey: hash)
                }
            } else {
                for hash in survivingHashes {
                    if let relative = relativePositions[hash] {
                        nodePositions[hash] = GraphPoint(
                            x: originalGroup.origin.x + relative.x,
                            y: originalGroup.origin.y + relative.y
                        )
                    }
                }
            }
        }

        let validEdgeIDs = Set(
            newSnapshot.commitsNewestFirst.flatMap { commit in
                commit.parentHashes.enumerated().map { index, parentHash in
                    "\(commit.fullHash)->\(parentHash)#\(index)"
                }
            }
        )
        let groupIDs = Set(reconciledGroups.map(\.id))
        let validBoundaryKeys = validBoundaryKeys(
            snapshot: newSnapshot,
            groups: reconciledGroups
        )
        let edgePorts = scene.edgePorts.filter {
            validEdgeIDs.contains($0.key)
        }
        let boundaryPorts = scene.boundaryPorts.filter { key, _ in
            groupIDs.contains(key.groupID)
                && validBoundaryKeys.contains(key)
        }

        return CommitGraphSceneState(
            schemaVersion: scene.schemaVersion,
            nodePositions: nodePositions,
            groups: reconciledGroups,
            regions: scene.regions,
            edgePorts: edgePorts,
            boundaryPorts: boundaryPorts,
            lineStyle: scene.lineStyle
        )
    }

    private static func validBoundaryKeys(
        snapshot: CommitGraphSnapshot,
        groups: [CommitGraphGroup]
    ) -> Set<CollapsedEdgeKey> {
        let membership = Dictionary(
            groups.flatMap { group in
                group.memberHashes.map { ($0, group.id) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        var keys: Set<CollapsedEdgeKey> = []

        for commit in snapshot.commitsNewestFirst {
            let childGroupID = membership[commit.fullHash]
            for parentHash in commit.parentHashes {
                let parentGroupID = membership[parentHash]
                guard childGroupID != parentGroupID else { continue }

                if let childGroupID {
                    keys.insert(
                        CollapsedEdgeKey(
                            groupID: childGroupID,
                            externalNodeID: parentHash,
                            direction: .leavingGroup
                        )
                    )
                    if let parentGroupID {
                        keys.insert(
                            CollapsedEdgeKey(
                                groupID: childGroupID,
                                externalNodeID: "group:\(parentGroupID.uuidString)",
                                direction: .leavingGroup
                            )
                        )
                    }
                }
                if let parentGroupID {
                    keys.insert(
                        CollapsedEdgeKey(
                            groupID: parentGroupID,
                            externalNodeID: commit.fullHash,
                            direction: .enteringGroup
                        )
                    )
                }
            }
        }
        return keys
    }
}
