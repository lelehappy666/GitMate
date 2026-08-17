import Foundation

public enum CommitGraphSceneReconciler {
    public static func reconcile(
        scene: CommitGraphSceneState,
        oldSnapshot: CommitGraphSnapshot,
        newSnapshot: CommitGraphSnapshot,
        defaultPositions: [String: GraphPoint]
    ) -> CommitGraphSceneState {
        _ = oldSnapshot
        let scene = migratingLayoutIfNeeded(
            scene,
            defaultPositions: defaultPositions
        )
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
        let boundaryRelations = boundaryRelations(
            snapshot: newSnapshot,
            groups: reconciledGroups,
            nodePositions: nodePositions
        )
        let edgePorts = scene.edgePorts.filter {
            validEdgeIDs.contains($0.key)
        }
        var boundaryPorts: [CollapsedEdgeKey: CommitGraphEdgePorts] = [:]
        for (key, relation) in boundaryRelations {
            if let existing = scene.boundaryPorts[key] {
                boundaryPorts[key] = existing
            } else if let sourceRect = relation.sourceRect,
                      let targetRect = relation.targetRect {
                boundaryPorts[key] = CommitGraphPortAllocator.ports(
                    sourceRect: sourceRect,
                    targetRect: targetRect
                )
            }
        }

        return CommitGraphSceneState(
            schemaVersion: CommitGraphSceneState.currentSchemaVersion,
            layoutAlgorithmVersion:
                CommitGraphSceneState.currentLayoutAlgorithmVersion,
            nodePositions: nodePositions,
            groups: reconciledGroups,
            regions: scene.regions,
            edgePorts: edgePorts,
            boundaryPorts: boundaryPorts,
            lineStyle: scene.lineStyle,
            viewMode: scene.viewMode,
            canvasViewport: scene.canvasViewport,
            manuallyPositionedHashes: scene.manuallyPositionedHashes
                .intersection(availableHashes)
                .subtracting(claimedHashes),
            pinnedTraditionalBranchIDs: scene.pinnedTraditionalBranchIDs,
            lastTraditionalBranchID: scene.lastTraditionalBranchID,
            traditionalDividerWidth: scene.traditionalDividerWidth,
            expandedBranchBundleIDs: scene.expandedBranchBundleIDs
        )
    }

    private static func migratingLayoutIfNeeded(
        _ scene: CommitGraphSceneState,
        defaultPositions: [String: GraphPoint]
    ) -> CommitGraphSceneState {
        guard scene.layoutAlgorithmVersion
                < CommitGraphSceneState.currentLayoutAlgorithmVersion
        else { return scene }

        let groupedHashes = Set(scene.groups.flatMap(\.memberHashes))
        var migratedNodePositions = defaultPositions.filter {
            !groupedHashes.contains($0.key)
        }
        let survivingManualHashes = scene.manuallyPositionedHashes
            .intersection(Set(defaultPositions.keys))
            .subtracting(groupedHashes)
        for hash in survivingManualHashes {
            if let manualPosition = scene.nodePositions[hash] {
                migratedNodePositions[hash] = manualPosition
            }
        }

        return CommitGraphSceneState(
            schemaVersion: CommitGraphSceneState.currentSchemaVersion,
            layoutAlgorithmVersion:
                CommitGraphSceneState.currentLayoutAlgorithmVersion,
            nodePositions: migratedNodePositions,
            groups: scene.groups,
            regions: scene.regions,
            edgePorts: scene.edgePorts,
            boundaryPorts: scene.boundaryPorts,
            lineStyle: scene.lineStyle,
            viewMode: scene.viewMode,
            canvasViewport: scene.canvasViewport,
            manuallyPositionedHashes: survivingManualHashes,
            pinnedTraditionalBranchIDs: scene.pinnedTraditionalBranchIDs,
            lastTraditionalBranchID: scene.lastTraditionalBranchID,
            traditionalDividerWidth: scene.traditionalDividerWidth,
            expandedBranchBundleIDs: scene.expandedBranchBundleIDs
        )
    }

    private struct BoundaryRelation {
        let sourceRect: GraphRect?
        let targetRect: GraphRect?
    }

    private static func boundaryRelations(
        snapshot: CommitGraphSnapshot,
        groups: [CommitGraphGroup],
        nodePositions: [String: GraphPoint]
    ) -> [CollapsedEdgeKey: BoundaryRelation] {
        let membership = Dictionary(
            groups.flatMap { group in
                group.memberHashes.map { ($0, group.id) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let groupsByID = Dictionary(
            uniqueKeysWithValues: groups.map { ($0.id, $0) }
        )
        var relations: [CollapsedEdgeKey: BoundaryRelation] = [:]

        for commit in snapshot.commitsNewestFirst {
            let childGroupID = membership[commit.fullHash]
            for parentHash in commit.parentHashes {
                let parentGroupID = membership[parentHash]
                guard childGroupID != parentGroupID else { continue }

                if let childGroupID,
                   let childGroup = groupsByID[childGroupID] {
                    let parentPosition = position(
                        hash: parentHash,
                        groupsByID: groupsByID,
                        membership: membership,
                        nodePositions: nodePositions
                    )
                    let key = CollapsedEdgeKey(
                        groupID: childGroupID,
                        externalNodeID: parentHash,
                        direction: .leavingGroup
                    )
                    relations[key] = BoundaryRelation(
                        sourceRect: CommitGraphSceneGeometry
                            .collapsedGroupRect(childGroup),
                        targetRect: parentPosition.map {
                            CommitGraphSceneGeometry.nodeRect(center: $0)
                        }
                    )
                    if let parentGroupID,
                       let parentGroup = groupsByID[parentGroupID] {
                        let key = CollapsedEdgeKey(
                            groupID: childGroupID,
                            externalNodeID: "group:\(parentGroupID.uuidString)",
                            direction: .leavingGroup
                        )
                        relations[key] = BoundaryRelation(
                            sourceRect: CommitGraphSceneGeometry
                                .collapsedGroupRect(childGroup),
                            targetRect: CommitGraphSceneGeometry
                                .collapsedGroupRect(parentGroup)
                        )
                    }
                }
                if let parentGroupID,
                   let parentGroup = groupsByID[parentGroupID] {
                    let childPosition = position(
                        hash: commit.fullHash,
                        groupsByID: groupsByID,
                        membership: membership,
                        nodePositions: nodePositions
                    )
                    let key = CollapsedEdgeKey(
                        groupID: parentGroupID,
                        externalNodeID: commit.fullHash,
                        direction: .enteringGroup
                    )
                    relations[key] = BoundaryRelation(
                        sourceRect: childPosition.map {
                            CommitGraphSceneGeometry.nodeRect(center: $0)
                        },
                        targetRect: CommitGraphSceneGeometry
                            .collapsedGroupRect(parentGroup)
                    )
                }
            }
        }
        return relations
    }

    private static func position(
        hash: String,
        groupsByID: [UUID: CommitGraphGroup],
        membership: [String: UUID],
        nodePositions: [String: GraphPoint]
    ) -> GraphPoint? {
        if let groupID = membership[hash],
           let group = groupsByID[groupID] {
            return group.absolutePosition(for: hash)
        }
        return nodePositions[hash]
    }
}
