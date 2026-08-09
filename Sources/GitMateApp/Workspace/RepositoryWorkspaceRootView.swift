import GitMateCore
import SwiftUI

struct RepositoryWorkspaceRootView: View {
    @Bindable var viewModel: RepositoryWorkspaceViewModel
    var onReturnToWorkspace: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            RepositorySidebarView(
                viewModel: viewModel,
                onReturnToWorkspace: onReturnToWorkspace
            )
                .frame(width: GitMateTheme.workspaceSidebarWidth)

            VStack(spacing: 0) {
                WorkspaceHeaderView(viewModel: viewModel)
                statusBanner

                routeContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(18)
            }
            .background(GitMateTheme.canvas)
        }
        .frame(
            minWidth: 1_040,
            idealWidth: 1_180,
            minHeight: 680,
            idealHeight: 760
        )
        .background(.white)
        .foregroundStyle(GitMateTheme.textPrimary)
        .overlay(alignment: .top) {
            WorkspaceLoadingOverlay(status: viewModel.state.status)
                .padding(.top, 74)
        }
        .sheet(
            item: Binding(
                get: { viewModel.pendingDangerousOperation },
                set: { value in
                    if value == nil {
                        viewModel.cancelDangerousOperation()
                    }
                }
            )
        ) { request in
            DangerousOperationConfirmationView(
                request: request,
                onCancel: viewModel.cancelDangerousOperation,
                onConfirm: {
                    Task {
                        await viewModel.confirmDangerousOperation()
                    }
                }
            )
        }
        .task(id: viewModel.state.route.id) {
            await viewModel.loadCurrentRoute()
        }
    }

    @ViewBuilder
    private var routeContent: some View {
        switch viewModel.state.route {
        case .branches:
            BranchesView(viewModel: viewModel)
        case .tags:
            TagsView(viewModel: viewModel)
        case .branchRules:
            BranchRulesView(viewModel: viewModel)
        case .issues:
            IssuesOverviewView(viewModel: viewModel)
        case .issueDetail:
            IssueDetailView(viewModel: viewModel)
        case .newIssue:
            NewIssueView(viewModel: viewModel)
        case .milestones:
            MilestonesCanvasView(viewModel: viewModel)
        case .issueLabels:
            IssueLabelsView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch viewModel.state.status {
        case .offline:
            banner(
                icon: "wifi.slash",
                text: "网络已中断，当前页面继续显示最近一次成功读取的数据。",
                color: GitMateTheme.warning
            )
        case .authorizationExpired:
            banner(
                icon: "key.slash",
                text: "GitHub 授权已失效，请返回账户设置重新登录。",
                color: GitMateTheme.danger
            )
        case .failed:
            banner(
                icon: "exclamationmark.triangle",
                text: viewModel.state.errorMessage ?? "操作未完成。",
                color: GitMateTheme.danger
            )
        default:
            EmptyView()
        }
    }

    private func banner(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(2)
            Spacer()
            Button("重试") {
                Task {
                    await viewModel.loadCurrentRoute()
                }
            }
            .buttonStyle(.borderless)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 18)
        .frame(minHeight: 38)
        .background(color.opacity(0.09))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(color.opacity(0.22))
                .frame(height: 1)
        }
    }
}
