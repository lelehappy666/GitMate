import Foundation
import GitMateCore

let commitGraphBranchBundleTests = [
    TestCase("画布只把连续普通提交建立为稳定分支束") {
        let fixture = branchBundleFixture()

        let projection = CommitGraphBranchBundleBuilder.build(
            input: CommitGraphBranchBundleInput(
                catalog: fixture.catalog,
                layout: fixture.layout,
                edges: fixture.layout.edges,
                forcedVisibleHashes: ["root", "head"],
                groupBoundaryHashes: [],
                regionBoundaryHashes: [],
                shallowBoundaryHashes: [],
                expandedBundleIDs: [],
                alwaysExpandedBranchIDs: []
            )
        )

        try expectEqual(projection.bundles.count, 1, "线性普通段只生成一个束")
        try expectEqual(
            projection.bundles[0].memberHashes,
            (1...13).map { "c\($0)" },
            "分支束成员必须保持最早到最新的连续顺序"
        )
        try expectEqual(
            projection.bundle(containing: "c7")?.id,
            projection.bundles[0].id,
            "必须能用提交哈希定位所属分支束"
        )
        try expectEqual(
            projection.hiddenInternalEdgeIDs.count,
            12,
            "束内真实边必须从概览绘制中隐藏"
        )
    },
    TestCase("分支束不得吞掉用户场景和浅克隆边界锚点") {
        let fixture = branchBundleFixture()

        let projection = CommitGraphBranchBundleBuilder.build(
            input: CommitGraphBranchBundleInput(
                catalog: fixture.catalog,
                layout: fixture.layout,
                edges: fixture.layout.edges,
                forcedVisibleHashes: ["root", "head"],
                groupBoundaryHashes: Set((1...5).map { "c\($0)" }),
                regionBoundaryHashes: Set((6...9).map { "c\($0)" }),
                shallowBoundaryHashes: Set((10...13).map { "c\($0)" }),
                expandedBundleIDs: [],
                alwaysExpandedBranchIDs: []
            )
        )

        try expectEqual(projection.bundles, [], "每个普通提交成为锚点后不得再聚合")
        try expectEqual(
            projection.hiddenMemberHashes,
            [],
            "Group、区域和浅边界提交必须继续作为真实节点显示"
        )
    },
    TestCase("展开分支束恢复成员且局部查询不扫描全历史") {
        let fixture = branchBundleFixture()
        let collapsed = CommitGraphBranchBundleBuilder.build(
            input: CommitGraphBranchBundleInput(
                catalog: fixture.catalog,
                layout: fixture.layout,
                edges: fixture.layout.edges,
                forcedVisibleHashes: ["root", "head"],
                groupBoundaryHashes: [],
                regionBoundaryHashes: [],
                shallowBoundaryHashes: [],
                expandedBundleIDs: [],
                alwaysExpandedBranchIDs: []
            )
        )
        let bundle = try requiredBranchBundle(collapsed.bundles.first)

        let expanded = CommitGraphBranchBundleBuilder.build(
            input: CommitGraphBranchBundleInput(
                catalog: fixture.catalog,
                layout: fixture.layout,
                edges: fixture.layout.edges,
                forcedVisibleHashes: ["root", "head"],
                groupBoundaryHashes: [],
                regionBoundaryHashes: [],
                shallowBoundaryHashes: [],
                expandedBundleIDs: [bundle.id],
                alwaysExpandedBranchIDs: []
            )
        )

        try expectEqual(expanded.bundle(containing: "c7"), nil, "展开后必须恢复成员")
        try expectEqual(expanded.hiddenMemberHashes, [], "展开后不得继续隐藏提交")
        try expectEqual(
            collapsed.visibleBundles(in: bundle.rect).map(\.id),
            [bundle.id],
            "视口索引必须返回相交分支束"
        )
        try expectEqual(
            collapsed.visibleBundles(
                in: GraphRect(x: 10_000, y: 10_000, width: 100, height: 100)
            ),
            [],
            "远离分支束的视口不得返回候选"
        )
    },
    TestCase("十二个连续提交不生成分支摘要") {
        let fixture = branchBundleFixture(intermediateCount: 12)
        let projection = CommitGraphBranchBundleBuilder.build(
            input: CommitGraphBranchBundleInput(
                catalog: fixture.catalog,
                layout: fixture.layout,
                edges: fixture.layout.edges,
                forcedVisibleHashes: ["root", "head"],
                groupBoundaryHashes: [],
                regionBoundaryHashes: [],
                shallowBoundaryHashes: [],
                expandedBundleIDs: [],
                alwaysExpandedBranchIDs: []
            )
        )

        try expectEqual(projection.bundles, [], "少于十三条不得过早折叠")
    },
    TestCase("当前与主分支始终保持展开") {
        let fixture = branchBundleFixture()
        let branchID = try requiredBranchBundle(
            fixture.catalog.branches.first?.id
        )
        let projection = CommitGraphBranchBundleBuilder.build(
            input: CommitGraphBranchBundleInput(
                catalog: fixture.catalog,
                layout: fixture.layout,
                edges: fixture.layout.edges,
                forcedVisibleHashes: ["root", "head"],
                groupBoundaryHashes: [],
                regionBoundaryHashes: [],
                shallowBoundaryHashes: [],
                expandedBundleIDs: [],
                alwaysExpandedBranchIDs: [branchID]
            )
        )

        try expectEqual(projection.bundles, [], "始终展开分支不得生成摘要")
    }
]

private struct BranchBundleFixture {
    let catalog: CommitGraphBranchCatalog
    let layout: CommitGraphLayoutResult
}

private func branchBundleFixture(
    intermediateCount: Int = 13
) -> BranchBundleFixture {
    let safeCount = max(intermediateCount, 1)
    var commits = [branchBundleCommit(
        hash: "head",
        parents: ["c\(safeCount)"],
        time: TimeInterval(safeCount + 2)
    )]
    for index in stride(from: safeCount, through: 1, by: -1) {
        commits.append(
            branchBundleCommit(
                hash: "c\(index)",
                parents: [index == 1 ? "root" : "c\(index - 1)"],
                time: TimeInterval(index + 1)
            )
        )
    }
    commits.append(branchBundleCommit(hash: "root", time: 1))
    let snapshot = CommitGraphSnapshot(
        repositoryPath: "/repo",
        fingerprint: CommitGraphReferenceFingerprint(
            references: [CommitGraphReference(
                name: "refs/heads/main",
                targetHash: "head",
                kind: .localBranch
            )],
            headName: "main",
            headHash: "head",
            isShallow: false
        ),
        commitsNewestFirst: commits,
        expectedCommitCount: commits.count,
        shallowBoundaryParentHashes: [],
        generatedAt: Date(timeIntervalSince1970: 10)
    )
    let topology = CommitGraphLaneTopology.build(snapshot: snapshot)
    return BranchBundleFixture(
        catalog: CommitGraphBranchCatalog.build(
            topology: topology,
            fingerprint: snapshot.fingerprint
        ),
        layout: CommitGraphLayout().layout(topology: topology)
    )
}

private func branchBundleCommit(
    hash: String,
    parents: [String] = [],
    time: TimeInterval
) -> GitCommit {
    GitCommit(
        shortHash: String(hash.prefix(7)),
        fullHash: hash,
        subject: "提交 \(hash)",
        authorName: "Lele",
        authorEmail: "lele@example.com",
        authoredAt: Date(timeIntervalSince1970: time),
        parentHashes: parents,
        decorations: []
    )
}

private func requiredBranchBundle<T>(_ value: T?) throws -> T {
    guard let value else {
        throw TestFailure(description: "必须生成可测试的分支束")
    }
    return value
}
