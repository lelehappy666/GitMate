import Foundation
import GitMateCore

let commitGraphPerformanceTests = [
    TestCase("五万提交双布局和可见查询保持局部工作量") {
        let snapshot = performanceCommitGraphSnapshot(count: 50_000)
        let clock = ContinuousClock()

        var topology: CommitGraphLaneTopology?
        let topologyDuration = clock.measure {
            topology = CommitGraphLaneTopology.build(snapshot: snapshot)
        }
        guard let topology else {
            throw TestFailure(description: "共享泳道拓扑未生成")
        }
        let relationshipCount = topology.rowsNewestFirst.reduce(0) {
            $0 + $1.connections.count
        }
        let expectedMergeCount = (1..<50_000).filter {
            $0 > 2 && $0.isMultiple(of: 997)
        }.count

        try expectEqual(
            topology.rowsNewestFirst.count,
            50_000,
            "共享泳道必须保留五万个提交"
        )
        try expectEqual(
            relationshipCount,
            49_999 + expectedMergeCount,
            "共享泳道必须保留线性父边和全部 Merge 父边"
        )

        var traditional: CommitGraphTraditionalLayoutResult?
        let traditionalDuration = clock.measure {
            traditional = CommitGraphTraditionalLayout().layout(
                topology: topology
            )
        }
        guard let traditional else {
            throw TestFailure(description: "传统布局未生成")
        }
        let visibleTraditionalRows = CommitGraphTraditionalViewport.visibleRows(
            totalCount: traditional.rows.count,
            rowHeight: 56,
            verticalOffset: 1_400_000,
            viewportHeight: 800,
            preloadScreens: 1.5
        )
        let visibleTraditionalEdges = traditional.connectionSpans(
            intersecting: visibleTraditionalRows
        )

        try expectEqual(
            traditional.rows.first?.commit.fullHash,
            "commit-49999",
            "传统布局必须保持最新提交在上"
        )
        try expect(
            visibleTraditionalRows.count < 100,
            "传统视口不得返回全部五万行"
        )
        try expect(
            visibleTraditionalEdges.count < 200,
            "传统视口连线候选必须与可见行相关"
        )

        var canvasLayout: CommitGraphLayoutResult?
        let canvasLayoutDuration = clock.measure {
            canvasLayout = CommitGraphLayout().layout(topology: topology)
        }
        guard let canvasLayout else {
            throw TestFailure(description: "画布布局未生成")
        }
        try expectEqual(
            canvasLayout.nodes.first?.hash,
            "commit-0",
            "画布布局必须保持最早提交在上"
        )
        try expectEqual(
            canvasLayout.edges.count,
            relationshipCount,
            "画布布局不得丢失 Merge 或父边"
        )

        var renderIndex: CommitGraphRenderIndex?
        let renderIndexDuration = clock.measure {
            let scene = CommitGraphSceneState.defaultState(
                layout: canvasLayout
            )
            let projection = CommitGraphSceneProjector.project(
                layout: canvasLayout,
                scene: scene
            )
            renderIndex = CommitGraphRenderIndex(projection: projection)
        }
        guard var renderIndex else {
            throw TestFailure(description: "画布空间索引未生成")
        }

        let middleRow = 25_000
        let middleY = 82 + Double(middleRow) * 126
        let viewport = GraphViewport(
            offsetX: 0,
            offsetY: 400 - middleY,
            scale: 1
        )
        let screenSize = GraphSize(width: 1_200, height: 800)
        var curveQuery: CommitGraphRenderQueryResult?
        let curveQueryDuration = clock.measure {
            curveQuery = renderIndex.queryWithDiagnostics(
                viewport: viewport,
                screenSize: screenSize,
                padding: 1_200
            )
        }
        guard let curveQuery else {
            throw TestFailure(description: "曲线可见查询未生成")
        }

        let lineStyleUpdate = renderIndex.setLineStyle(.orthogonal)
        var orthogonalQuery: CommitGraphRenderQueryResult?
        let orthogonalQueryDuration = clock.measure {
            orthogonalQuery = renderIndex.queryWithDiagnostics(
                viewport: viewport,
                screenSize: screenSize,
                padding: 1_200
            )
        }
        guard let orthogonalQuery else {
            throw TestFailure(description: "直角线可见查询未生成")
        }

        try expect(
            curveQuery.scene.nodes.count < 100,
            "画布可见查询不得返回全部节点"
        )
        try expect(
            curveQuery.diagnostics.nodeCandidates < 100,
            "画布节点候选必须保持局部规模"
        )
        try expect(
            curveQuery.diagnostics.edgeCandidates < 200,
            "曲线候选必须保持局部规模"
        )
        try expectEqual(
            lineStyleUpdate.processedEdgeCount,
            0,
            "切换线型不得全量处理五万条边"
        )
        try expect(
            orthogonalQuery.diagnostics.generatedEdgeGeometries < 200,
            "切换后只能生成可见候选边的几何"
        )
        try expectEqual(
            Set(orthogonalQuery.scene.edges.map(\.id)),
            Set(curveQuery.scene.edges.map(\.id)),
            "线型切换不得改变同一视口的 Git 边集合"
        )

        print(
            "  性能记录：50000 提交，Merge \(expectedMergeCount) 条；"
                + "拓扑 \(topologyDuration)，"
                + "传统布局 \(traditionalDuration)，"
                + "画布布局 \(canvasLayoutDuration)，"
                + "空间索引 \(renderIndexDuration)，"
                + "曲线查询 \(curveQueryDuration)，"
                + "直角查询 \(orthogonalQueryDuration)；"
                + "传统可见行 \(visibleTraditionalRows.count)，"
                + "曲线候选 \(curveQuery.diagnostics.edgeCandidates)，"
                + "直角几何 \(orthogonalQuery.diagnostics.generatedEdgeGeometries)"
        )
    },
    TestCase("五万提交与三百分支的投影仍保持局部工作量") {
        let snapshot = performanceCommitGraphSnapshot(
            count: 50_000,
            branchCount: 300
        )
        let clock = ContinuousClock()

        var topology: CommitGraphLaneTopology?
        let topologyDuration = clock.measure {
            topology = CommitGraphLaneTopology.build(snapshot: snapshot)
        }
        guard let topology else {
            throw TestFailure(description: "三百分支共享拓扑未生成")
        }
        let layout = CommitGraphLayout().layout(topology: topology)

        var catalog: CommitGraphBranchCatalog?
        let catalogDuration = clock.measure {
            catalog = CommitGraphBranchCatalog.build(
                topology: topology,
                fingerprint: snapshot.fingerprint
            )
        }
        guard let catalog else {
            throw TestFailure(description: "三百分支目录未生成")
        }

        var bundles: CommitGraphBranchBundleProjection?
        let bundleDuration = clock.measure {
            bundles = CommitGraphBranchBundleBuilder.build(
                input: CommitGraphBranchBundleInput(
                    catalog: catalog,
                    layout: layout,
                    edges: layout.edges,
                    forcedVisibleHashes: [],
                    groupBoundaryHashes: [],
                    regionBoundaryHashes: [],
                    shallowBoundaryHashes: [],
                    expandedBundleIDs: []
                )
            )
        }
        guard let bundles else {
            throw TestFailure(description: "三百分支束未生成")
        }

        let traditional = CommitGraphTraditionalBranchProjector.project(
            CommitGraphTraditionalBranchProjectionInput(
                catalog: catalog,
                topology: topology,
                totalWidth: 1_520,
                selectedHash: nil,
                pinnedBranchIDs: [],
                lastSelectedBranchID: nil
            )
        )
        var segmentProjection: CommitGraphTraditionalSegmentProjection?
        let segmentDuration = clock.measure {
            segmentProjection = CommitGraphTraditionalSegmentProjector.project(
                topology: topology,
                catalog: catalog,
                branchProjection: traditional
            )
        }
        guard let segmentProjection else {
            throw TestFailure(description: "三百分支传统区段投影未生成")
        }
        var publicationIndex: CommitGraphTraditionalPublicationIndex?
        let publicationDuration = clock.measure {
            publicationIndex = CommitGraphTraditionalPublicationIndex.build(
                snapshot: snapshot
            )
        }
        guard let publicationIndex else {
            throw TestFailure(description: "三百分支发布状态索引未生成")
        }
        let visibleLaneRange = CommitGraphTraditionalSplitLayout
            .visibleLaneRange(
                slotCount: traditional.slots.count,
                horizontalOffset: 2_800,
                dividerWidth: 380
            )
        let localBundles = bundles.visibleBundles(
            in: GraphRect(
                x: 0,
                y: 1_500_000,
                width: 1_200,
                height: 1_000
            )
        )

        try expectEqual(
            catalog.branches.count,
            300,
            "本地与远程引用都必须进入分支目录"
        )
        try expectEqual(
            traditional.slots.count,
            299,
            "main 本地远程成对合并后仍必须保留其余全部逻辑分支"
        )
        try expectEqual(
            traditional.capacity,
            traditional.slots.count,
            "传统分支容量必须等于真实逻辑泳道数"
        )
        try expectEqual(
            traditional.hiddenLocalCount + traditional.hiddenRemoteCount,
            0,
            "三百引用下也不得隐藏真实分支"
        )
        try expect(
            visibleLaneRange.count < 30,
            "左侧分支视口只应绘制当前窗口附近的泳道"
        )
        try expect(
            topology.rowsNewestFirst.allSatisfy {
                segmentProjection.lane(for: $0.commit.fullHash) != nil
            },
            "五万提交必须各自恰好获得一个可查询的最终泳道"
        )
        try expectEqual(
            segmentProjection.connections.count,
            topology.rowsNewestFirst.reduce(0) { $0 + $1.connections.count },
            "区段投影不得遗漏完整拓扑中的父边"
        )
        try expectEqual(
            publicationIndex.state(for: "commit-49999"),
            .remoteKnown,
            "远端 main 可达的最新提交必须保持实线状态"
        )
        try expect(
            localBundles.count < 500,
            "分支束局部查询不得返回全历史"
        )

        print(
            "  性能记录：50000 提交、300 分支；"
                + "拓扑 \(topologyDuration)，"
                + "分支目录 \(catalogDuration)，"
                + "分支束 \(bundleDuration)；"
                + "区段投影 \(segmentDuration)；"
                + "发布索引 \(publicationDuration)；"
                + "传统槽位 \(traditional.slots.count)，"
                + "局部分支束 \(localBundles.count)"
        )
    }
]

private func performanceCommitGraphSnapshot(
    count: Int,
    branchCount: Int = 3
) -> CommitGraphSnapshot {
    let commits = (0..<count).reversed().map { index in
        var parents = index == 0 ? [] : ["commit-\(index - 1)"]
        if index > 2, index.isMultiple(of: 997) {
            parents.append("commit-\(index - 2)")
        }
        var decorations: [String] = []
        if index == count - 1 {
            decorations = ["HEAD -> main", "origin/main"]
        } else if index == count - 10_000 {
            decorations = ["release/performance"]
        }
        return GitCommit(
            shortHash: "c\(index)",
            fullHash: "commit-\(index)",
            subject: "性能提交 \(index)",
            authorName: "性能测试",
            authorEmail: "performance@example.com",
            authoredAt: Date(timeIntervalSince1970: Double(index)),
            parentHashes: parents,
            decorations: decorations
        )
    }
    var references = [
        CommitGraphReference(
            name: "refs/heads/main",
            targetHash: "commit-\(count - 1)",
            kind: .localBranch
        ),
        CommitGraphReference(
            name: "refs/remotes/origin/main",
            targetHash: "commit-\(count - 1)",
            kind: .remoteBranch
        ),
        CommitGraphReference(
            name: "refs/heads/release/performance",
            targetHash: "commit-\(count - 10_000)",
            kind: .localBranch
        )
    ]
    if branchCount > references.count {
        references.append(
            contentsOf: (references.count..<branchCount).map { index in
                let isRemote = index.isMultiple(of: 2)
                let targetIndex = max(
                    count - 1 - index * max(count / branchCount, 1),
                    0
                )
                return CommitGraphReference(
                    name: isRemote
                        ? "refs/remotes/origin/performance-\(index)"
                        : "refs/heads/performance-\(index)",
                    targetHash: "commit-\(targetIndex)",
                    kind: isRemote ? .remoteBranch : .localBranch
                )
            }
        )
    }
    return CommitGraphSnapshot(
        repositoryPath: "/performance",
        fingerprint: CommitGraphReferenceFingerprint(
            references: references,
            headName: "main",
            headHash: "commit-\(count - 1)",
            isShallow: false
        ),
        commitsNewestFirst: commits,
        expectedCommitCount: count,
        shallowBoundaryParentHashes: [],
        generatedAt: Date(timeIntervalSince1970: 0)
    )
}
