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
    }
]

private func performanceCommitGraphSnapshot(
    count: Int
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
    return CommitGraphSnapshot(
        repositoryPath: "/performance",
        fingerprint: CommitGraphReferenceFingerprint(
            references: [
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
            ],
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
