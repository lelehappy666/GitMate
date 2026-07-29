import Foundation
import GitMateCore

let repositoryWorkspaceModelTests = [
    TestCase("第 16–23 页路由编号保持稳定") {
        let routes: [(RepositoryWorkspaceRoute, Int)] = [
            (.branches, 16),
            (.tags, 17),
            (.branchRules, 18),
            (.issues, 19),
            (.issueDetail(number: 91), 20),
            (.newIssue, 21),
            (.milestones, 22),
            (.issueLabels, 23)
        ]

        for (route, expectedPage) in routes {
            try expectEqual(route.pageNumber, expectedPage, "仓库工作区页面编号不应漂移")
        }
    },
    TestCase("分支位置和同步状态由真实引用派生") {
        let localOnly = GitBranch(
            name: "draft",
            localSHA: "111",
            remoteSHA: nil,
            upstreamName: nil
        )
        let remoteOnly = GitBranch(
            name: "release",
            localSHA: nil,
            remoteSHA: "222",
            upstreamName: "origin/release"
        )
        let synchronized = GitBranch(
            name: "main",
            localSHA: "333",
            remoteSHA: "333",
            upstreamName: "origin/main"
        )
        let ahead = GitBranch(
            name: "feature",
            localSHA: "444",
            remoteSHA: "333",
            upstreamName: "origin/feature",
            comparison: BranchComparison(aheadBy: 2, behindBy: 0)
        )
        let behind = GitBranch(
            name: "develop",
            localSHA: "333",
            remoteSHA: "555",
            upstreamName: "origin/develop",
            comparison: BranchComparison(aheadBy: 0, behindBy: 3)
        )
        let diverged = GitBranch(
            name: "experiment",
            localSHA: "666",
            remoteSHA: "777",
            upstreamName: "origin/experiment",
            comparison: BranchComparison(aheadBy: 2, behindBy: 4)
        )

        try expectEqual(localOnly.location, .local, "仅有本地引用时应标记为本地")
        try expectEqual(localOnly.trackingStatus, .localOnly, "未推送分支应标记为仅本地")
        try expectEqual(remoteOnly.location, .remote, "仅有远端引用时应标记为远端")
        try expectEqual(remoteOnly.trackingStatus, .remoteOnly, "未签出远端分支应标记为仅远端")
        try expectEqual(synchronized.location, .localAndRemote, "两端都有引用时应合并展示")
        try expectEqual(synchronized.trackingStatus, .synchronized, "相同提交应视为已同步")
        try expectEqual(ahead.trackingStatus, .ahead(2), "本地新增提交应显示领先数量")
        try expectEqual(behind.trackingStatus, .behind(3), "远端新增提交应显示落后数量")
        try expectEqual(
            diverged.trackingStatus,
            .diverged(aheadBy: 2, behindBy: 4),
            "双向变化应显示分叉数量"
        )
    },
    TestCase("标签状态区分轻量标签和附注标签") {
        let lightweight = GitTag(
            name: "v1.0.0",
            objectSHA: "abc",
            kind: .lightweight,
            existsLocally: true,
            existsRemotely: false
        )
        let annotated = GitTag(
            name: "v2.0.0",
            objectSHA: "def",
            kind: .annotated,
            existsLocally: true,
            existsRemotely: true,
            message: "稳定版本"
        )

        try expectEqual(lightweight.remoteStatus, .localOnly, "未推送标签应标记为仅本地")
        try expectEqual(annotated.remoteStatus, .synchronized, "两端标签应标记为已同步")
        try expectEqual(annotated.message, "稳定版本", "附注标签应保留说明")
    },
    TestCase("组织继承规则只读而仓库规则可编辑") {
        let inherited = RepositoryRuleset(
            id: 88,
            name: "企业保护",
            enforcement: .active,
            source: .organization(login: "GitMate")
        )
        let repositoryRule = RepositoryRuleset(
            id: 89,
            name: "主分支保护",
            enforcement: .active,
            source: .repository
        )

        try expect(!inherited.isEditable, "继承的组织规则不得在仓库内编辑")
        try expect(repositoryRule.isEditable, "仓库规则应允许编辑")
    },
    TestCase("议题状态与里程碑进度覆盖边界") {
        let openIssue = GitHubIssue(
            id: 1,
            number: 91,
            title: "修复本地网络权限",
            body: nil,
            state: .open,
            author: IssueUser(login: "lele")
        )
        let closedIssue = GitHubIssue(
            id: 2,
            number: 79,
            title: "修复 SSO",
            body: nil,
            state: .closed,
            author: IssueUser(login: "lele")
        )
        let activeMilestone = IssueMilestone(
            id: 11,
            number: 2,
            title: "v2.5",
            state: .open,
            openIssues: 3,
            closedIssues: 7
        )
        let emptyMilestone = IssueMilestone(
            id: 12,
            number: 3,
            title: "未来版本",
            state: .open,
            openIssues: 0,
            closedIssues: 0
        )

        try expect(openIssue.isOpen, "打开议题应允许继续处理")
        try expect(!closedIssue.isOpen, "关闭议题不应显示为打开")
        try expectEqual(activeMilestone.progress, 0.7, "里程碑应按关闭议题占比计算")
        try expectEqual(emptyMilestone.progress, 0, "空里程碑进度应为零")
    },
    TestCase("议题标签颜色统一为六位十六进制") {
        let shortColor = IssueLabel(
            id: 1,
            name: "错误",
            color: "#f00"
        )
        let malformedColor = IssueLabel(
            id: 2,
            name: "未知",
            color: "not-a-color"
        )

        try expectEqual(shortColor.normalizedColorHex, "FF0000", "三位颜色应展开为六位")
        try expectEqual(malformedColor.normalizedColorHex, "D0D7DE", "无效颜色应使用可读回退色")
    }
]
