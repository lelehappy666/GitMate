import GitMateCore
import SwiftUI

struct RepositorySidebarView: View {
    @Bindable var viewModel: RepositoryWorkspaceViewModel
    var onReturnToWorkspace: (() -> Void)? = nil
    var onSettingsRequested: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            accountHeader
            repositoryCard

            if let onReturnToWorkspace {
                Button(action: onReturnToWorkspace) {
                    Label("返回仓库工作区", systemImage: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(GitMateTheme.accent)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    navigationGroup("代码", items: codeItems)
                    navigationGroup("协作", items: issueItems)
                    navigationGroup("发布与运行", items: releaseItems)
                }
                .padding(.horizontal, 12)
                .padding(.top, 18)
            }

            Spacer(minLength: 10)
            syncStatus
            settingsButton
        }
        .background(GitMateTheme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(GitMateTheme.border)
                .frame(width: 1)
        }
    }

    private var accountHeader: some View {
        HStack(spacing: 11) {
            GitMateAvatar(
                url: viewModel.context.account.avatarURL,
                size: 40
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("GitMate")
                    .font(.system(size: 16, weight: .bold))
                Text("@\(viewModel.context.account.login)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 70)
    }

    private var repositoryCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(GitMateTheme.accent)
                Text(viewModel.context.repository.fullName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(GitMateTheme.textTertiary)
            }
            Text(viewModel.context.repository.isPrivate ? "私有仓库" : "公开仓库")
                .font(.system(size: 10))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .padding(12)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(GitMateTheme.border, lineWidth: 1)
        }
        .padding(.horizontal, 12)
    }

    private var codeItems: [SidebarItem] {
        [
            SidebarItem(
                title: "总览",
                icon: "house",
                route: .overview,
                accessibilityID: "workspace.sidebar.overview"
            ),
            SidebarItem(
                title: "介绍",
                icon: "doc.richtext",
                route: .readme,
                accessibilityID: "workspace.sidebar.readme"
            ),
            SidebarItem(
                title: "分支",
                icon: "arrow.triangle.branch",
                route: .branches,
                accessibilityID: "workspace.sidebar.branches"
            ),
            SidebarItem(title: "标签", icon: "tag", route: .tags),
            SidebarItem(title: "分支规则", icon: "shield.lefthalf.filled", route: .branchRules)
        ]
    }

    private var issueItems: [SidebarItem] {
        [
            SidebarItem(
                title: "议题",
                icon: "circle.circle",
                route: .issues,
                accessibilityID: "workspace.sidebar.issues"
            ),
            SidebarItem(title: "里程碑", icon: "signpost.right", route: .milestones),
            SidebarItem(title: "议题标签", icon: "swatchpalette", route: .issueLabels)
        ]
    }

    private var releaseItems: [SidebarItem] {
        [
            SidebarItem(title: "Actions", icon: "play.fill", route: nil),
            SidebarItem(title: "Releases", icon: "shippingbox", route: nil),
            SidebarItem(title: "Packages", icon: "cube.box", route: nil)
        ]
    }

    private func navigationGroup(
        _ title: String,
        items: [SidebarItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(GitMateTheme.textTertiary)
                .padding(.horizontal, 10)

            ForEach(items) { item in
                Button {
                    if let route = item.route {
                        viewModel.navigate(to: route)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 18)
                        Text(item.title)
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(
                        item.isSelected(route: viewModel.state.route)
                            ? GitMateTheme.accent
                            : GitMateTheme.textPrimary
                    )
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(
                        item.isSelected(route: viewModel.state.route)
                            ? GitMateTheme.selection
                            : .clear
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(item.route == nil)
                .opacity(item.route == nil ? 0.65 : 1)
                .accessibilityIdentifier(item.accessibilityID ?? "")
            }
        }
    }

    private var syncStatus: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(
                    viewModel.context.localDirectory == nil
                        ? GitMateTheme.warning
                        : GitMateTheme.success
                )
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    viewModel.context.localDirectory == nil
                        ? "仅远端模式"
                        : "本地仓库已连接"
                )
                .font(.system(size: 11, weight: .semibold))
                Text(
                    viewModel.context.localDirectory?.path(percentEncoded: false)
                        ?? "尚未同步到本机"
                )
                .font(.system(size: 9))
                .foregroundStyle(GitMateTheme.textSecondary)
                .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(GitMateTheme.border, lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var settingsButton: some View {
        Group {
            if let onSettingsRequested {
                Button(action: onSettingsRequested) {
                    settingsLabel
                }
                .buttonStyle(.plain)
            } else {
                settingsLabel
            }
        }
        .accessibilityIdentifier("repositoryWorkspace.sidebar.settings")
    }

    private var settingsLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "gearshape")
            Text("仓库设置")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 22)
        .frame(height: 44)
        .foregroundStyle(GitMateTheme.textSecondary)
    }
}

private struct SidebarItem: Identifiable {
    let title: String
    let icon: String
    let route: RepositoryWorkspaceRoute?
    var accessibilityID: String?

    var id: String { title }

    func isSelected(route current: RepositoryWorkspaceRoute) -> Bool {
        guard let route else {
            return false
        }
        switch (route, current) {
        case (.issues, .issueDetail), (.issues, .newIssue):
            return true
        default:
            return route == current
        }
    }
}
