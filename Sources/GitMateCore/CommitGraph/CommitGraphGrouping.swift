import Foundation

public enum CommitGraphGrouping {
    public static func validateGroupMembership(
        _ memberHashes: Set<String>,
        layout: CommitGraphLayoutResult,
        scene: CommitGraphSceneState
    ) throws {
        try validateMembership(
            memberHashes,
            excludingGroupID: nil,
            layout: layout,
            scene: scene
        )
    }

    public static func validateConnectedSelection(
        hashes: [String],
        layout: CommitGraphLayoutResult
    ) -> CommitGraphConnectivityResult {
        var seenHashes = Set<String>()
        let orderedHashes = hashes.filter {
            seenHashes.insert($0).inserted
        }
        guard orderedHashes.count >= 2 else {
            return CommitGraphConnectivityResult(
                isConnected: false,
                disconnectedHashes: orderedHashes
            )
        }

        let availableHashes = Set(layout.nodes.map(\.hash))
        let unknownHashes = orderedHashes.filter {
            !availableHashes.contains($0)
        }
        guard unknownHashes.isEmpty else {
            return CommitGraphConnectivityResult(
                isConnected: false,
                disconnectedHashes: unknownHashes
            )
        }

        let selected = Set(orderedHashes)
        var adjacency: [String: Set<String>] = [:]
        for edge in layout.edges
            where selected.contains(edge.childHash)
                && selected.contains(edge.parentHash) {
            adjacency[edge.childHash, default: []].insert(edge.parentHash)
            adjacency[edge.parentHash, default: []].insert(edge.childHash)
        }

        var visited: Set<String> = []
        var queue = [orderedHashes[0]]
        while let current = queue.first {
            queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            queue.append(
                contentsOf: (adjacency[current] ?? [])
                    .filter { !visited.contains($0) }
                    .sorted()
            )
        }

        let disconnected = orderedHashes.filter { !visited.contains($0) }
        return CommitGraphConnectivityResult(
            isConnected: disconnected.isEmpty,
            disconnectedHashes: disconnected
        )
    }

    public static func branchSuggestions(
        layout: CommitGraphLayoutResult,
        occupiedHashes: Set<String>
    ) -> [CommitGraphGroupSuggestion] {
        let parentHashesByChild = Dictionary(
            grouping: layout.edges,
            by: \.childHash
        ).mapValues { $0.map(\.parentHash) }

        var tipByBranch: [String: CommitGraphNode] = [:]
        for node in layout.nodes {
            for branch in branchNames(node.decorations) {
                if let existing = tipByBranch[branch],
                   existing.row >= node.row {
                    continue
                }
                tipByBranch[branch] = node
            }
        }

        var reachableByBranch: [String: Set<String>] = [:]
        for (branch, tip) in tipByBranch {
            reachableByBranch[branch] = reachableHashes(
                from: tip.hash,
                parentHashesByChild: parentHashesByChild
            )
        }

        var reachCount: [String: Int] = [:]
        for reachable in reachableByBranch.values {
            for hash in reachable {
                reachCount[hash, default: 0] += 1
            }
        }

        return reachableByBranch.compactMap { branch, reachable in
            let exclusive = reachable.filter {
                reachCount[$0] == 1 && !occupiedHashes.contains($0)
            }
            guard exclusive.count >= 2 else { return nil }
            let validation = validateConnectedSelection(
                hashes: exclusive.sorted(),
                layout: layout
            )
            guard validation.isConnected else { return nil }
            return CommitGraphGroupSuggestion(
                branchName: branch,
                memberHashes: exclusive
            )
        }
        .sorted { $0.branchName.localizedStandardCompare($1.branchName)
            == .orderedAscending
        }
    }

    public static func creatingGroup(
        id: UUID = UUID(),
        title: String,
        memberHashes: Set<String>,
        source: CommitGraphGroupSource,
        layout: CommitGraphLayoutResult,
        scene: CommitGraphSceneState
    ) throws -> CommitGraphSceneState {
        try validateMembership(
            memberHashes,
            excludingGroupID: nil,
            layout: layout,
            scene: scene
        )
        let positions = try absolutePositions(
            for: memberHashes,
            layout: layout,
            scene: scene
        )
        let origin = groupOrigin(positions.values)
        let relativePositions = positions.mapValues {
            GraphPoint(x: $0.x - origin.x, y: $0.y - origin.y)
        }
        var updated = scene
        for hash in memberHashes {
            updated.nodePositions.removeValue(forKey: hash)
        }
        updated.groups.append(
            CommitGraphGroup(
                id: id,
                title: title,
                memberHashes: memberHashes,
                source: source,
                origin: origin,
                relativePositions: relativePositions,
                isCollapsed: false
            )
        )
        return rebuildingBoundaryPorts(layout: layout, scene: updated)
    }

    public static func updatingGroupMembers(
        groupID: UUID,
        memberHashes: Set<String>,
        layout: CommitGraphLayoutResult,
        scene: CommitGraphSceneState
    ) throws -> CommitGraphSceneState {
        guard let groupIndex = scene.groups.firstIndex(
            where: { $0.id == groupID }
        ) else {
            throw CommitGraphGroupingError.groupNotFound
        }
        try validateMembership(
            memberHashes,
            excludingGroupID: groupID,
            layout: layout,
            scene: scene
        )

        var updated = scene
        var group = updated.groups[groupIndex]
        let oldMembers = group.memberHashes

        for removedHash in oldMembers.subtracting(memberHashes) {
            if let absolute = group.absolutePosition(for: removedHash) {
                updated.nodePositions[removedHash] = absolute
            }
            group.relativePositions.removeValue(forKey: removedHash)
        }

        for addedHash in memberHashes.subtracting(oldMembers) {
            let absolute = updated.nodePositions[addedHash]
                ?? layout.node(hash: addedHash).map {
                    GraphPoint(x: $0.x, y: $0.y)
                }
            guard let absolute else {
                throw CommitGraphGroupingError.unknownMembers([addedHash])
            }
            group.relativePositions[addedHash] = GraphPoint(
                x: absolute.x - group.origin.x,
                y: absolute.y - group.origin.y
            )
            updated.nodePositions.removeValue(forKey: addedHash)
        }

        group.memberHashes = memberHashes
        updated.groups[groupIndex] = group
        return rebuildingBoundaryPorts(layout: layout, scene: updated)
    }

    public static func renamingGroup(
        id: UUID,
        title: String,
        scene: CommitGraphSceneState
    ) throws -> CommitGraphSceneState {
        guard let index = scene.groups.firstIndex(where: { $0.id == id })
        else {
            throw CommitGraphGroupingError.groupNotFound
        }
        var updated = scene
        updated.groups[index].title = title
        return updated
    }

    public static func removingGroup(
        id: UUID,
        layout: CommitGraphLayoutResult,
        scene: CommitGraphSceneState
    ) throws -> CommitGraphSceneState {
        guard let index = scene.groups.firstIndex(where: { $0.id == id })
        else {
            throw CommitGraphGroupingError.groupNotFound
        }
        var updated = scene
        let group = updated.groups.remove(at: index)
        for hash in group.memberHashes {
            let position = group.absolutePosition(for: hash)
                ?? layout.node(hash: hash).map {
                    GraphPoint(x: $0.x, y: $0.y)
                }
            if let position {
                updated.nodePositions[hash] = position
            }
        }
        return rebuildingBoundaryPorts(layout: layout, scene: updated)
    }

    public static func movingGroup(
        id: UUID,
        translation: GraphPoint,
        scene: CommitGraphSceneState
    ) -> CommitGraphSceneState {
        guard translation.x.isFinite,
              translation.y.isFinite,
              let index = scene.groups.firstIndex(where: { $0.id == id })
        else {
            return scene
        }
        var updated = scene
        let origin = updated.groups[index].origin
        updated.groups[index].origin = GraphPoint(
            x: origin.x + translation.x,
            y: origin.y + translation.y
        )
        return updated
    }

    public static func rebuildingBoundaryPorts(
        layout: CommitGraphLayoutResult,
        scene: CommitGraphSceneState
    ) -> CommitGraphSceneState {
        let relations = boundaryRelations(layout: layout, scene: scene)
        var updated = scene
        var ports: [CollapsedEdgeKey: CommitGraphEdgePorts] = [:]
        for (key, relation) in relations {
            ports[key] = scene.boundaryPorts[key]
                ?? CommitGraphPortAllocator.ports(
                    sourceRect: relation.sourceRect,
                    targetRect: relation.targetRect
                )
        }
        updated.boundaryPorts = ports
        return updated
    }

    private struct BoundaryRelation {
        let sourceRect: GraphRect
        let targetRect: GraphRect
    }

    private static func boundaryRelations(
        layout: CommitGraphLayoutResult,
        scene: CommitGraphSceneState
    ) -> [CollapsedEdgeKey: BoundaryRelation] {
        let membership = groupMembership(scene.groups)
        var result: [CollapsedEdgeKey: BoundaryRelation] = [:]

        for edge in layout.edges {
            let childGroupID = membership[edge.childHash]
            let parentGroupID = membership[edge.parentHash]
            guard childGroupID != parentGroupID else { continue }

            if let childGroupID,
               let childGroup = scene.groups.first(
                where: { $0.id == childGroupID }
               ) {
                if let parentGroupID,
                   let parentGroup = scene.groups.first(
                    where: { $0.id == parentGroupID }
                   ) {
                    let groupKey = CollapsedEdgeKey(
                        groupID: childGroupID,
                        externalNodeID: "group:\(parentGroupID.uuidString)",
                        direction: .leavingGroup
                    )
                    result[groupKey] = BoundaryRelation(
                        sourceRect: CommitGraphSceneGeometry
                            .collapsedGroupRect(childGroup),
                        targetRect: CommitGraphSceneGeometry
                            .collapsedGroupRect(parentGroup)
                    )
                }

                if let parentPosition = position(
                    hash: edge.parentHash,
                    layout: layout,
                    scene: scene
                ) {
                    let key = CollapsedEdgeKey(
                        groupID: childGroupID,
                        externalNodeID: edge.parentHash,
                        direction: .leavingGroup
                    )
                    result[key] = BoundaryRelation(
                        sourceRect: CommitGraphSceneGeometry
                            .collapsedGroupRect(childGroup),
                        targetRect: CommitGraphSceneGeometry.nodeRect(
                            center: parentPosition
                        )
                    )
                }
            }

            if let parentGroupID,
               let parentGroup = scene.groups.first(
                where: { $0.id == parentGroupID }
               ),
               let childPosition = position(
                hash: edge.childHash,
                layout: layout,
                scene: scene
               ) {
                let key = CollapsedEdgeKey(
                    groupID: parentGroupID,
                    externalNodeID: edge.childHash,
                    direction: .enteringGroup
                )
                result[key] = BoundaryRelation(
                    sourceRect: CommitGraphSceneGeometry.nodeRect(
                        center: childPosition
                    ),
                    targetRect: CommitGraphSceneGeometry
                        .collapsedGroupRect(parentGroup)
                )
            }
        }
        for endpoint in layout.shallowBoundaryEndpoints {
            guard let groupID = membership[endpoint.childHash],
                  let group = scene.groups.first(where: { $0.id == groupID }),
                  let endpointPosition = CommitGraphSceneGeometry
                    .shallowBoundaryPosition(
                        endpoint: endpoint,
                        layout: layout,
                        scene: scene
                    )
            else {
                continue
            }
            let key = CollapsedEdgeKey(
                groupID: groupID,
                externalNodeID: endpoint.relation.collapsedExternalNodeID,
                direction: .leavingGroup
            )
            result[key] = BoundaryRelation(
                sourceRect: CommitGraphSceneGeometry.collapsedGroupRect(group),
                targetRect: CommitGraphSceneGeometry.shallowBoundaryRect(
                    center: endpointPosition
                )
            )
        }
        return result
    }

    private static func validateMembership(
        _ memberHashes: Set<String>,
        excludingGroupID: UUID?,
        layout: CommitGraphLayoutResult,
        scene: CommitGraphSceneState
    ) throws {
        guard memberHashes.count >= 2 else {
            throw CommitGraphGroupingError.insufficientMembers
        }
        let available = Set(layout.nodes.map(\.hash))
        let unknown = memberHashes.subtracting(available).sorted()
        guard unknown.isEmpty else {
            throw CommitGraphGroupingError.unknownMembers(unknown)
        }
        let occupied = Set(
            scene.groups
                .filter { $0.id != excludingGroupID }
                .flatMap(\.memberHashes)
        )
        let duplicates = memberHashes.intersection(occupied).sorted()
        guard duplicates.isEmpty else {
            throw CommitGraphGroupingError.membersAlreadyGrouped(duplicates)
        }
        let validation = validateConnectedSelection(
            hashes: memberHashes.sorted(),
            layout: layout
        )
        guard validation.isConnected else {
            throw CommitGraphGroupingError.disconnectedSelection(
                validation.disconnectedHashes
            )
        }
    }

    private static func absolutePositions(
        for hashes: Set<String>,
        layout: CommitGraphLayoutResult,
        scene: CommitGraphSceneState
    ) throws -> [String: GraphPoint] {
        var result: [String: GraphPoint] = [:]
        for hash in hashes {
            guard let point = position(
                hash: hash,
                layout: layout,
                scene: scene
            ) else {
                throw CommitGraphGroupingError.unknownMembers([hash])
            }
            result[hash] = point
        }
        return result
    }

    private static func position(
        hash: String,
        layout: CommitGraphLayoutResult,
        scene: CommitGraphSceneState
    ) -> GraphPoint? {
        if let group = scene.groups.first(
            where: { $0.memberHashes.contains(hash) }
        ) {
            return group.absolutePosition(for: hash)
        }
        return scene.nodePositions[hash] ?? layout.node(hash: hash).map {
            GraphPoint(x: $0.x, y: $0.y)
        }
    }

    private static func groupOrigin(
        _ positions: Dictionary<String, GraphPoint>.Values
    ) -> GraphPoint {
        let minimumX = positions.map(\.x).min() ?? 0
        let minimumY = positions.map(\.y).min() ?? 0
        return GraphPoint(
            x: minimumX
                - CommitGraphSceneGeometry.nodeWidth / 2
                - CommitGraphSceneGeometry.groupPadding,
            y: minimumY
                - CommitGraphSceneGeometry.nodeHeight / 2
                - CommitGraphSceneGeometry.groupHeaderHeight
        )
    }

    private static func groupMembership(
        _ groups: [CommitGraphGroup]
    ) -> [String: UUID] {
        Dictionary(
            groups.flatMap { group in
                group.memberHashes.map { ($0, group.id) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func reachableHashes(
        from tip: String,
        parentHashesByChild: [String: [String]]
    ) -> Set<String> {
        var result: Set<String> = []
        var stack = [tip]
        while let hash = stack.popLast() {
            guard result.insert(hash).inserted else { continue }
            stack.append(
                contentsOf: parentHashesByChild[hash] ?? []
            )
        }
        return result
    }

    private static func branchNames(
        _ decorations: [String]
    ) -> [String] {
        decorations.compactMap { decoration in
            var value = decoration.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if let arrowRange = value.range(of: "->") {
                value = String(value[arrowRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !value.isEmpty,
                  !value.lowercased().hasPrefix("tag:")
            else {
                return nil
            }
            return value
        }
    }
}
