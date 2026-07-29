import GitMateCore
import SwiftUI

struct DiffHunkView: View {
    let hunk: GitDiffHunk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(GitMateTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(GitMateTheme.accentSoft)

            ForEach(hunk.lines) { line in
                Text(line.text.isEmpty ? " " : line.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(GitMateTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                    .background(background(for: line.kind))
                    .textSelection(.enabled)
            }
        }
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

    private func background(for kind: GitDiffLineKind) -> Color {
        switch kind {
        case .addition:
            return GitMateTheme.success.opacity(0.11)
        case .deletion:
            return GitMateTheme.danger.opacity(0.1)
        case .metadata:
            return GitMateTheme.panel
        case .context:
            return .white
        }
    }
}
