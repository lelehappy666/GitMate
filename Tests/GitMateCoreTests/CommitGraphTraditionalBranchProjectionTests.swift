import Foundation
import GitMateCore

let commitGraphTraditionalBranchProjectionTests = [
    TestCase("传统布局根据窗口宽度稳定限制四到八条泳道") {
        try expectEqual(
            CommitGraphTraditionalLaneCapacity.visibleCount(totalWidth: 760),
            4,
            "窄窗口至少显示四条上下文泳道"
        )
        try expectEqual(
            CommitGraphTraditionalLaneCapacity.visibleCount(totalWidth: 1_520),
            8,
            "宽窗口最多显示八条上下文泳道"
        )
        try expectEqual(
            CommitGraphTraditionalLaneCapacity.visibleCount(totalWidth: 10_000),
            8,
            "分支再多也不得让图轨无限变宽"
        )
        try expectEqual(
            CommitGraphTraditionalLaneCapacity.visibleCount(totalWidth: .nan),
            4,
            "无效窗口宽度必须安全退化到最小泳道数"
        )
    },
    TestCase("传统分支投影按HEAD选择固定和相关关系排序") {
        let catalog = traditionalProjectionCatalog()

        let projection = CommitGraphTraditionalBranchProjector.project(
            CommitGraphTraditionalBranchProjectionInput(
                catalog: catalog,
                totalWidth: 760,
                selectedHash: "selected-hash",
                pinnedBranchIDs: ["local:pinned"],
                lastSelectedBranchID: nil
            )
        )

        try expectEqual(
            Array(projection.visibleBranches.prefix(3).map(\.id)),
            ["local:main", "local:selected", "local:pinned"],
            "HEAD、当前选择和固定分支必须依次占据最高优先级"
        )
        try expect(
            projection.hiddenLocalCount > 0,
            "超出容量的本地分支必须进入本地聚合入口"
        )
        try expect(
            projection.hiddenRemoteCount > 0,
            "超出容量的远程分支必须进入远程聚合入口"
        )
        try expect(
            projection.slots.count <= projection.capacity + 2,
            "真实分支容量之外最多只能增加本地与远程两个聚合入口"
        )
    },
    TestCase("选择隐藏分支只替换临时泳道并保留本地远程来源") {
        let catalog = traditionalProjectionCatalog()
        let projection = CommitGraphTraditionalBranchProjector.project(
            CommitGraphTraditionalBranchProjectionInput(
                catalog: catalog,
                totalWidth: 760,
                selectedHash: nil,
                pinnedBranchIDs: ["local:pinned"],
                lastSelectedBranchID: "remote:origin/hidden"
            )
        )

        try expect(
            projection.visibleBranches.contains {
                $0.id == "remote:origin/hidden"
            },
            "用户从浮层选择的隐藏远程分支必须立即进入可见槽"
        )
        try expect(
            projection.visibleBranches.contains { $0.id == "local:main" },
            "临时替换不得移除 HEAD 主干"
        )
        try expect(
            projection.visibleBranches.contains { $0.id == "local:pinned" },
            "临时替换不得移除仍有容量的固定分支"
        )
        try expectEqual(
            projection.slot(forBranchID: "remote:origin/hidden")?.source,
            .remote,
            "显示槽必须保留远程来源供 UI 使用虚线"
        )
        try expect(
            projection.displayLane(for: "local:old") != nil,
            "隐藏分支必须映射到本地聚合槽，不能从拓扑中消失"
        )
    },
    TestCase("固定分支超过容量时按最近活跃时间稳定选择") {
        let catalog = traditionalProjectionCatalog()
        let projection = CommitGraphTraditionalBranchProjector.project(
            CommitGraphTraditionalBranchProjectionInput(
                catalog: catalog,
                totalWidth: 760,
                selectedHash: nil,
                pinnedBranchIDs: [
                    "local:pinned",
                    "local:old",
                    "remote:origin/recent",
                    "remote:origin/hidden"
                ],
                lastSelectedBranchID: nil
            )
        )

        let visiblePinned = projection.visibleBranches
            .filter {
                [
                    "local:pinned",
                    "local:old",
                    "remote:origin/recent",
                    "remote:origin/hidden"
                ].contains($0.id)
            }
            .map(\.id)
        try expect(
            visiblePinned.first == "remote:origin/recent",
            "固定分支超量时必须优先最近活跃分支"
        )
    },
    TestCase("浮层选择隐藏分支优先于已选提交上下文") {
        let projection = CommitGraphTraditionalBranchProjector.project(
            CommitGraphTraditionalBranchProjectionInput(
                catalog: traditionalProjectionCatalog(),
                totalWidth: 760,
                selectedHash: "selected-hash",
                pinnedBranchIDs: [],
                lastSelectedBranchID: "remote:origin/hidden"
            )
        )

        try expect(
            projection.visibleBranches.contains {
                $0.id == "remote:origin/hidden"
            },
            "用户显式选择隐藏分支后必须立即替换临时槽"
        )
    },
    TestCase("可见分支容量与本地远程聚合槽分别计算") {
        let projection = CommitGraphTraditionalBranchProjector.project(
            CommitGraphTraditionalBranchProjectionInput(
                catalog: traditionalProjectionCatalog(),
                totalWidth: 760,
                selectedHash: nil,
                pinnedBranchIDs: [],
                lastSelectedBranchID: nil
            )
        )

        try expectEqual(
            projection.visibleBranches.count,
            projection.capacity,
            "四到八条容量应完整用于真实可见分支"
        )
        try expect(
            projection.slots.contains { $0.kind == .hiddenLocalBranches },
            "本地隐藏分支必须拥有独立聚合槽"
        )
        try expect(
            projection.slots.contains { $0.kind == .hiddenRemoteBranches },
            "远程隐藏分支必须拥有独立聚合槽"
        )
    }
]

private func traditionalProjectionCatalog() -> CommitGraphBranchCatalog {
    let branches = [
        traditionalDescriptor(
            id: "local:main",
            source: .local,
            lane: 0,
            time: 100,
            hash: "head-hash",
            isHead: true
        ),
        traditionalDescriptor(
            id: "local:selected",
            source: .local,
            lane: 1,
            time: 90,
            hash: "selected-hash"
        ),
        traditionalDescriptor(
            id: "local:pinned",
            source: .local,
            lane: 2,
            time: 80,
            hash: "pinned-hash"
        ),
        traditionalDescriptor(
            id: "local:related",
            source: .local,
            lane: 3,
            time: 70,
            hash: "related-hash"
        ),
        traditionalDescriptor(
            id: "local:old",
            source: .local,
            lane: 4,
            time: 10,
            hash: "old-hash"
        ),
        traditionalDescriptor(
            id: "remote:origin/recent",
            source: .remote,
            lane: 5,
            time: 95,
            hash: "remote-recent-hash"
        ),
        traditionalDescriptor(
            id: "remote:origin/hidden",
            source: .remote,
            lane: 6,
            time: 20,
            hash: "remote-hidden-hash"
        )
    ]
    return CommitGraphBranchCatalog(
        branches: branches,
        headBranchID: "local:main",
        primaryBranchIDByHash: Dictionary(
            uniqueKeysWithValues: branches.map { ($0.tipHash, $0.id) }
        ),
        relatedBranchIDsByBranchID: [
            "local:selected": ["local:related"]
        ]
    )
}

private func traditionalDescriptor(
    id: String,
    source: CommitGraphBranchSource,
    lane: Int,
    time: TimeInterval,
    hash: String,
    isHead: Bool = false
) -> CommitGraphBranchDescriptor {
    CommitGraphBranchDescriptor(
        id: id,
        displayName: String(id.split(separator: ":").last ?? "branch"),
        source: source,
        side: lane == 0 ? .trunk : (lane.isMultiple(of: 2) ? .right : .left),
        lane: lane,
        tipHash: hash,
        latestActivity: Date(timeIntervalSince1970: time),
        memberHashes: [hash],
        isHead: isHead,
        isMerged: false
    )
}
