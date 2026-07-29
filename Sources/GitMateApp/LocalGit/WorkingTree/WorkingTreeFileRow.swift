import GitMateCore
import SwiftUI

struct WorkingTreeFileRow: View {
    let file: WorkingTreeFile
    let isSelected: Bool
    let onToggle: () -> Void
    let onOpenDiff: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(
                    systemName: isSelected
                        ? "checkmark.square.fill"
                        : "square"
                )
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    isSelected
                        ? GitMateTheme.accent
                        : GitMateTheme.textTertiary
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "取消选择" : "选择")

            Button(action: onOpenDiff) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(statusColor.opacity(0.12))
                        Image(systemName: statusIcon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(statusColor)
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.path)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(GitMateTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let originalPath = file.originalPath {
                            Text("原路径：\(originalPath)")
                                .font(.system(size: 10))
                                .foregroundStyle(GitMateTheme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(statusText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.1))
                        .clipShape(Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isSelected
                ? GitMateTheme.accentSoft.opacity(0.7)
                : Color.clear
        )
    }

    private var statusText: String {
        switch file.category {
        case .conflicted: return "冲突"
        case .staged: return "已暂存"
        case .unstaged: return "未暂存"
        case .untracked: return "未跟踪"
        }
    }

    private var statusIcon: String {
        switch file.category {
        case .conflicted: return "exclamationmark.triangle.fill"
        case .staged: return "checkmark"
        case .unstaged: return "pencil"
        case .untracked: return "plus"
        }
    }

    private var statusColor: Color {
        switch file.category {
        case .conflicted: return GitMateTheme.danger
        case .staged: return GitMateTheme.success
        case .unstaged: return GitMateTheme.warning
        case .untracked: return GitMateTheme.accent
        }
    }
}
