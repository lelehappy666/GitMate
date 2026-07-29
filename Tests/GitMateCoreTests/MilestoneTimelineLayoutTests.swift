import Foundation
import GitMateCore

let milestoneTimelineLayoutTests = [
    TestCase("里程碑画布按截止日期排序且未排期节点最后显示") {
        let milestones = [
            testMilestone(id: 1, title: "未排期", dueOn: nil),
            testMilestone(
                id: 2,
                title: "九月版本",
                dueOn: Date(timeIntervalSince1970: 1_788_192_000)
            ),
            testMilestone(
                id: 3,
                title: "八月版本",
                dueOn: Date(timeIntervalSince1970: 1_785_513_600)
            )
        ]

        let layout = MilestoneTimelineLayout().makeLayout(
            milestones: milestones
        )

        try expectEqual(
            layout.nodes.map(\.milestoneID),
            [3, 2, 1],
            "画布时间线应保持稳定的时间顺序"
        )
    },
    TestCase("里程碑画布节点保持水平间距并交错分布") {
        let milestones = (1...5).map {
            testMilestone(
                id: Int64($0),
                title: "版本 \($0)",
                dueOn: Date(timeIntervalSince1970: Double($0) * 86_400)
            )
        }

        let layout = MilestoneTimelineLayout(
            horizontalSpacing: 260,
            verticalSpacing: 150
        ).makeLayout(milestones: milestones)

        for index in 1..<layout.nodes.count {
            let distance = layout.nodes[index].position.x
                - layout.nodes[index - 1].position.x
            try expect(
                distance >= 260,
                "相邻里程碑不得发生水平遮挡"
            )
        }
        try expect(
            Set(layout.nodes.map(\.position.y)).count > 1,
            "节点应交错分布以形成清晰的视觉节奏"
        )
    },
    TestCase("里程碑横向距离体现真实日期间隔") {
        let day: TimeInterval = 86_400
        let milestones = [
            testMilestone(
                id: 1,
                title: "起点",
                dueOn: Date(timeIntervalSince1970: 0)
            ),
            testMilestone(
                id: 2,
                title: "一天后",
                dueOn: Date(timeIntervalSince1970: day)
            ),
            testMilestone(
                id: 3,
                title: "一年后",
                dueOn: Date(timeIntervalSince1970: day * 365)
            )
        ]

        let nodes = MilestoneTimelineLayout(
            horizontalSpacing: 240
        ).makeLayout(milestones: milestones).nodes
        let shortGap = nodes[1].position.x - nodes[0].position.x
        let longGap = nodes[2].position.x - nodes[1].position.x

        try expect(longGap > shortGap * 2, "一年间隔必须显著大于一天间隔")
    },
    TestCase("里程碑画布边界完整包含全部节点") {
        let milestones = (1...4).map {
            testMilestone(
                id: Int64($0),
                title: "版本 \($0)",
                dueOn: Date(timeIntervalSince1970: Double($0) * 86_400)
            )
        }

        let layout = MilestoneTimelineLayout().makeLayout(
            milestones: milestones
        )

        for node in layout.nodes {
            try expect(
                layout.bounds.contains(node.position),
                "自动聚焦边界必须包含每个里程碑节点"
            )
        }
        try expect(
            layout.bounds.width > 0 && layout.bounds.height > 0,
            "非空画布必须具有可缩放边界"
        )
    }
]

private func testMilestone(
    id: Int64,
    title: String,
    dueOn: Date?
) -> IssueMilestone {
    IssueMilestone(
        id: id,
        number: Int(id),
        title: title,
        state: .open,
        openIssues: 2,
        closedIssues: 3,
        dueOn: dueOn
    )
}
