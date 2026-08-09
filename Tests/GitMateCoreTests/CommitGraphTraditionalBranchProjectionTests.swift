import Foundation
import GitMateCore

let commitGraphTraditionalBranchProjectionTests = [
    TestCase("传统投影把本地main与origin main合并为第零泳道") {
        let projection = CommitGraphTraditionalBranchProjector.project(
            CommitGraphTraditionalBranchProjectionInput(
                catalog: projectionCatalog(
                    headBranchID: "local:main",
                    branches: [
                        projectionBranch("local:main", "main", .local, 100, "local-main", true),
                        projectionBranch("remote:origin/main", "origin/main", .remote, 90, "remote-main"),
                        projectionBranch("local:feature/ui", "feature/ui", .local, 80, "feature")
                    ]
                ),
                totalWidth: 620,
                selectedHash: nil,
                pinnedBranchIDs: [],
                lastSelectedBranchID: nil
            )
        )

        try expectEqual(projection.slots.count, 2, "同名本地与远程分支不得重复占泳道")
        try expectEqual(projection.slots.first?.lane, 0, "main 必须位于最左侧零号泳道")
        try expectEqual(
            projection.slots.first?.branchIDs,
            ["local:main", "remote:origin/main"],
            "main 逻辑泳道必须保留本地与远程两个真实身份"
        )
        try expectEqual(
            projection.slots.first?.referenceTitles,
            ["main", "origin/main"],
            "main 逻辑泳道必须保留全部可见标签"
        )
        try expectEqual(
            projection.displayLane(for: "remote:origin/main"),
            0,
            "远程 main 身份必须映射到同一逻辑泳道"
        )
    },
    TestCase("只有origin main时仍固定为第零泳道") {
        let projection = CommitGraphTraditionalBranchProjector.project(
            CommitGraphTraditionalBranchProjectionInput(
                catalog: projectionCatalog(
                    headBranchID: "local:feature/ui",
                    branches: [
                        projectionBranch("local:feature/ui", "feature/ui", .local, 200, "feature", true),
                        projectionBranch("remote:origin/main", "origin/main", .remote, 100, "main"),
                        projectionBranch("remote:upstream/docs", "upstream/docs", .remote, 300, "docs")
                    ]
                ),
                totalWidth: 400,
                selectedHash: nil,
                pinnedBranchIDs: [],
                lastSelectedBranchID: nil
            )
        )

        try expectEqual(
            projection.slots.first?.branchIDs,
            ["remote:origin/main"],
            "没有本地 main 时 origin/main 必须优先于当前 HEAD"
        )
        try expectEqual(
            projection.slots.dropFirst().first?.branchIDs,
            ["local:feature/ui"],
            "非 main 的当前 HEAD 必须紧随主分支"
        )
    },
    TestCase("没有main时当前HEAD作为默认最左泳道") {
        let projection = CommitGraphTraditionalBranchProjector.project(
            CommitGraphTraditionalBranchProjectionInput(
                catalog: projectionCatalog(
                    headBranchID: "local:develop",
                    branches: [
                        projectionBranch("local:feature/new", "feature/new", .local, 300, "feature"),
                        projectionBranch("local:develop", "develop", .local, 100, "develop", true),
                        projectionBranch("remote:origin/release", "origin/release", .remote, 400, "release")
                    ]
                ),
                totalWidth: 400,
                selectedHash: nil,
                pinnedBranchIDs: [],
                lastSelectedBranchID: nil
            )
        )

        try expectEqual(
            projection.slots.first?.branchIDs,
            ["local:develop"],
            "仓库没有 main 时必须使用真实 HEAD，不能虚构 main"
        )
    },
    TestCase("同名分支合并多个远端并优先origin标签") {
        let projection = CommitGraphTraditionalBranchProjector.project(
            CommitGraphTraditionalBranchProjectionInput(
                catalog: projectionCatalog(
                    headBranchID: "local:main",
                    branches: [
                        projectionBranch("local:main", "main", .local, 500, "main", true),
                        projectionBranch("local:release/v2", "release/v2", .local, 400, "local-release"),
                        projectionBranch("remote:upstream/release/v2", "upstream/release/v2", .remote, 300, "upstream-release"),
                        projectionBranch("remote:origin/release/v2", "origin/release/v2", .remote, 200, "origin-release")
                    ]
                ),
                totalWidth: 320,
                selectedHash: nil,
                pinnedBranchIDs: [],
                lastSelectedBranchID: nil
            )
        )

        guard let release = projection.slot(
            forBranchID: "local:release/v2"
        ) else {
            throw TestFailure(description: "release/v2 必须存在")
        }
        try expectEqual(
            release.branchIDs,
            [
                "local:release/v2",
                "remote:origin/release/v2",
                "remote:upstream/release/v2"
            ],
            "同名远端必须稳定合并且 origin 排在其他远端之前"
        )
        try expectEqual(
            projection.slot(forBranchID: "remote:upstream/release/v2")?.id,
            release.id,
            "任一远端标签都必须回到同一逻辑泳道"
        )
    },
    TestCase("所有本地远程独有分支均进入投影且无聚合槽") {
        var branches = [
            projectionBranch("local:main", "main", .local, 1_000, "main", true)
        ]
        for index in 0..<20 {
            branches.append(
                projectionBranch(
                    "local:feature/\(index)",
                    "feature/\(index)",
                    .local,
                    TimeInterval(900 - index),
                    "local-\(index)"
                )
            )
            branches.append(
                projectionBranch(
                    "remote:origin/remote-only-\(index)",
                    "origin/remote-only-\(index)",
                    .remote,
                    TimeInterval(500 - index),
                    "remote-\(index)"
                )
            )
        }
        let projection = CommitGraphTraditionalBranchProjector.project(
            CommitGraphTraditionalBranchProjectionInput(
                catalog: projectionCatalog(
                    headBranchID: "local:main",
                    branches: branches
                ),
                totalWidth: 260,
                selectedHash: nil,
                pinnedBranchIDs: [],
                lastSelectedBranchID: nil
            )
        )

        try expectEqual(projection.slots.count, 41, "窄窗口也必须保留全部逻辑分支")
        try expectEqual(projection.capacity, 41, "容量必须等于真实逻辑泳道数")
        try expectEqual(projection.hiddenLocalCount, 0, "不得再隐藏本地分支")
        try expectEqual(projection.hiddenRemoteCount, 0, "不得再隐藏远程分支")
        try expect(
            projection.slots.allSatisfy { $0.kind == .branch },
            "不得生成其他本地或其他远程聚合入口"
        )
        try expectEqual(
            projection.displayLane(for: "remote:origin/remote-only-19"),
            40,
            "最后一条远程分支也必须拥有可导航的真实泳道"
        )
    },
    TestCase("同名未命名分支仍保持各自独立身份") {
        let projection = CommitGraphTraditionalBranchProjector.project(
            CommitGraphTraditionalBranchProjectionInput(
                catalog: projectionCatalog(
                    headBranchID: "synthetic:a",
                    branches: [
                        projectionBranch("synthetic:a", "未命名分支", .synthetic, 20, "a", true),
                        projectionBranch("synthetic:b", "未命名分支", .synthetic, 10, "b")
                    ]
                ),
                totalWidth: 300,
                selectedHash: nil,
                pinnedBranchIDs: [],
                lastSelectedBranchID: nil
            )
        )

        try expectEqual(projection.slots.count, 2, "synthetic 分支不得因同名被错误合并")
        try expect(
            projection.displayLane(for: "synthetic:a")
                != projection.displayLane(for: "synthetic:b"),
            "每条未命名分支必须保留独立可导航泳道"
        )
    }
]

private func projectionCatalog(
    headBranchID: String?,
    branches: [CommitGraphBranchDescriptor]
) -> CommitGraphBranchCatalog {
    CommitGraphBranchCatalog(
        branches: branches,
        headBranchID: headBranchID,
        primaryBranchIDByHash: Dictionary(
            uniqueKeysWithValues: branches.map { ($0.tipHash, $0.id) }
        )
    )
}

private func projectionBranch(
    _ id: String,
    _ displayName: String,
    _ source: CommitGraphBranchSource,
    _ activity: TimeInterval,
    _ tipHash: String,
    _ isHead: Bool = false
) -> CommitGraphBranchDescriptor {
    CommitGraphBranchDescriptor(
        id: id,
        displayName: displayName,
        source: source,
        side: isHead ? .trunk : .right,
        lane: 0,
        tipHash: tipHash,
        latestActivity: Date(timeIntervalSince1970: activity),
        memberHashes: [tipHash],
        isHead: isHead,
        isMerged: false
    )
}
