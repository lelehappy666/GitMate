import GitMateCore
import SwiftUI

struct LocalGitSidebar: View {
    @Binding var route: LocalGitRoute
    let repositoryName: String
    let isPreview: Bool
    let conflictCount: Int
    let hasActiveOperation: Bool

    var body: some View {
        VStack(spacing: 0) {
            repositoryHeader
            Divider()
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(LocalGitRoute.allCases, id: \.pageNumber) {
                        item($0)
                    }
                }
                .padding(12)
            }
            Divider()
            modeCard
                .padding(12)
        }
        .frame(width: 236)
        .background(GitMateTheme.panel)
    }

    private var repositoryHeader: some View {
        HStack(spacing: 11) {
            GitMateAvatar(url: nil, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(repositoryName)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("本地 Git 工作区")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
    }

    private func item(_ itemRoute: LocalGitRoute) -> some View {
        Button {
            route = itemRoute
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon(itemRoute))
                    .frame(width: 17)
                Text(title(itemRoute))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if itemRoute == .conflicts, conflictCount > 0 {
                    badge("\(conflictCount)", danger: true)
                } else if itemRoute == .historyOperation,
                          hasActiveOperation {
                    badge("进行中", danger: false)
                } else {
                    Text("\(itemRoute.pageNumber)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(GitMateTheme.textTertiary)
                }
            }
            .foregroundStyle(
                route == itemRoute
                    ? GitMateTheme.accent
                    : GitMateTheme.textPrimary
            )
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(
                route == itemRoute
                    ? GitMateTheme.accentSoft
                    : .clear
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: GitMateTheme.compactCornerRadius
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var modeCard: some View {
        HStack(spacing: 9) {
            Image(
                systemName: isPreview
                    ? "eye.fill"
                    : "externaldrive.fill.badge.checkmark"
            )
            .foregroundStyle(
                isPreview ? GitMateTheme.accent : GitMateTheme.warning
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(isPreview ? "只读预览" : "真实仓库")
                    .font(.system(size: 10, weight: .bold))
                Text(
                    isPreview
                        ? "操作不会写入磁盘"
                        : "写操作作用于当前路径"
                )
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
            }
            Spacer()
        }
        .padding(11)
        .background(.white)
        .clipShape(
            RoundedRectangle(cornerRadius: GitMateTheme.compactCornerRadius)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: GitMateTheme.compactCornerRadius
            )
            .stroke(GitMateTheme.border, lineWidth: 1)
        }
    }

    private func badge(_ value: String, danger: Bool) -> some View {
        Text(value)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(danger ? GitMateTheme.danger : GitMateTheme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                danger
                    ? GitMateTheme.danger.opacity(0.1)
                    : GitMateTheme.accentSoft
            )
            .clipShape(Capsule())
    }

    private func title(_ route: LocalGitRoute) -> String {
        switch route {
        case .workingTree: "工作区变更"
        case .commit: "暂存与提交"
        case .diff: "文件差异"
        case .stash: "Stash 管理"
        case .historyOperation: "合并与变基"
        case .conflicts: "冲突解决"
        case .remotes: "远程仓库"
        case .transfer: "获取与推送"
        }
    }

    private func icon(_ route: LocalGitRoute) -> String {
        switch route {
        case .workingTree: "list.bullet.rectangle"
        case .commit: "checkmark.seal"
        case .diff: "doc.text.magnifyingglass"
        case .stash: "tray.full"
        case .historyOperation: "arrow.triangle.branch"
        case .conflicts: "arrow.triangle.merge"
        case .remotes: "network"
        case .transfer: "arrow.up.arrow.down.circle"
        }
    }
}
