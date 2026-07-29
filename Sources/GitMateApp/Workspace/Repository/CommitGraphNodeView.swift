import GitMateCore
import SwiftUI

enum CommitGraphPalette {
    static let colors: [Color] = [
        Color(red: 0.08, green: 0.38, blue: 0.75),
        Color(red: 0.37, green: 0.20, blue: 0.68),
        Color(red: 0.10, green: 0.47, blue: 0.33),
        Color(red: 0.68, green: 0.31, blue: 0.08),
        Color(red: 0.62, green: 0.16, blue: 0.34),
        Color(red: 0.18, green: 0.43, blue: 0.52)
    ]

    static func color(_ index: Int) -> Color {
        colors[index % colors.count]
    }
}

struct CommitGraphNodeView: View {
    let node: CommitGraphNode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                GitMateAvatar(url: nil, size: 32)

                VStack(alignment: .leading, spacing: 6) {
                    Text(node.subject)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(GitMateTheme.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 7) {
                        Text(node.authorName)
                        Text(node.shortHash)
                            .fontDesign(.monospaced)
                        if let decoration = node.decorations.first {
                            Text(decoration)
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    CommitGraphPalette.color(node.colorIndex)
                                        .opacity(0.11)
                                )
                                .clipShape(Capsule())
                        }
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
                }
            }
            .padding(11)
            .frame(width: 224, alignment: .leading)
            .frame(minHeight: 74)
            .background(.white)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
                .stroke(
                    isSelected
                        ? GitMateTheme.accent
                        : CommitGraphPalette.color(node.colorIndex),
                    lineWidth: isSelected ? 2.5 : 1.35
                )
            }
            .shadow(
                color: Color.black.opacity(isSelected ? 0.13 : 0.07),
                radius: isSelected ? 9 : 5,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(node.subject)，作者 \(node.authorName)，提交 \(node.shortHash)"
        )
        .accessibilityHint("打开提交详情")
        .accessibilityIdentifier("workspace.commitGraph.node.\(node.hash)")
    }
}
