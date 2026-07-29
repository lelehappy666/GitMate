import GitMateCore
import SwiftUI

struct WorkspacePanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.white)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: GitMateTheme.compactCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: GitMateTheme.compactCornerRadius,
                    style: .continuous
                )
                .stroke(GitMateTheme.border, lineWidth: 1)
            }
    }
}

extension View {
    func workspacePanel() -> some View {
        modifier(WorkspacePanelModifier())
    }
}

struct WorkspaceStatusChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(color.opacity(0.11))
            .clipShape(Capsule())
    }
}

struct WorkspaceEmptyView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(GitMateTheme.textTertiary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(GitMateTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct WorkspaceLoadingOverlay: View {
    let status: RepositoryWorkspaceStatus

    var body: some View {
        if status == .loading {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text("正在读取仓库数据…")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
    }
}

func shortSHA(_ value: String?) -> String {
    guard let value else {
        return "—"
    }
    return String(value.prefix(8))
}
