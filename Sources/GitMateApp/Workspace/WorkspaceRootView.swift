import GitMateCore
import SwiftUI

struct WorkspaceRootView: View {
    @State private var session: WorkspaceSession
    @State private var selection: WorkspaceSelection

    init(session: WorkspaceSession) {
        _session = State(initialValue: session)
        _selection = State(initialValue: WorkspaceSelection(route: session.route))
    }

    var body: some View {
        NavigationSplitView {
            WorkspaceSidebar(
                selection: $selection,
                repositories: session.repositories,
                account: session.account
            )
        } detail: {
            WorkspacePlaceholderView(route: session.route)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(
            minWidth: 1_040,
            idealWidth: 1_180,
            minHeight: 680,
            idealHeight: 760
        )
        .background(GitMateTheme.background)
        .onChange(of: selection) { _, selection in
            session.route = selection.route
        }
    }
}

private struct WorkspacePlaceholderView: View {
    let route: WorkspaceRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(GitMateTheme.textPrimary)
            Text("此页面内容将在后续任务中实现。")
                .font(.system(size: 15))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(GitMateTheme.canvas)
    }

    private var title: String {
        switch route {
        case .dashboard:
            "全局工作台"
        case .repositories:
            "全部仓库"
        case .repositoryOverview:
            "总览"
        case .readme:
            "README"
        case .filesAndCommits:
            "文件与提交"
        case .commitGraph:
            "提交图"
        }
    }
}
