import GitMateCore
import SwiftUI

struct WorkspaceHeaderView: View {
    @Bindable var viewModel: RepositoryWorkspaceViewModel

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }

            Spacer()

            Text(String(format: "%02d", viewModel.state.route.pageNumber))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(GitMateTheme.accent)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(GitMateTheme.accentSoft)
                .clipShape(Capsule())

            Button {
                Task {
                    await viewModel.loadCurrentRoute()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(GitMateTheme.border, lineWidth: 1)
            }
            .help("刷新当前页面")
        }
        .padding(.horizontal, 20)
        .frame(height: GitMateTheme.workspaceHeaderHeight)
        .background(.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GitMateTheme.border)
                .frame(height: 1)
        }
    }

    private var title: String {
        switch viewModel.state.route {
        case .branches:
            "分支"
        case .tags:
            "标签"
        case .branchRules:
            "分支规则"
        case .issues:
            "议题"
        case let .issueDetail(number):
            "议题 #\(number)"
        case .newIssue:
            "新建议题"
        case .milestones:
            "里程碑"
        case .issueLabels:
            "议题标签"
        }
    }

    private var subtitle: String {
        switch viewModel.state.route {
        case .branches:
            "统一查看本地、远端、跟踪关系与保护状态"
        case .tags:
            "管理版本标签、目标提交和 GitHub Release"
        case .branchRules:
            "GitHub Ruleset、匹配条件和组织继承规则"
        case .issues:
            "筛选、搜索并处理仓库议题"
        case .issueDetail:
            "时间线、评论和元数据"
        case .newIssue:
            "Markdown、模板和发布设置"
        case .milestones:
            "可视化版本节奏与议题进度"
        case .issueLabels:
            "标签库、使用分析与安全合并"
        }
    }
}
