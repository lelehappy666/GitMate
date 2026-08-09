import GitMateCore
import SwiftUI

/// 大型提交图的紧凑导航条。标记统一由 `Canvas` 绘制，不会为
/// 每个提交或标记创建 SwiftUI 元素。
struct CommitGraphHistoryNavigator: View {
    let count: Int
    let markerBins: [CommitGraphHistoryMarkerBin]
    let viewportRange: CommitGraphHistoryViewportRange
    let currentRow: Int?
    let navigate: (Double) -> Void

    @State private var previewProgress: Double?

    var body: some View {
        VStack(spacing: 7) {
            Label("\(count)", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(GitMateTheme.textPrimary)

            Text("最早")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(GitMateTheme.textSecondary)

            GeometryReader { geometry in
                let activeProgress = previewProgress
                    ?? currentRow.map {
                        CommitGraphHistoryNavigation.progress(
                            row: $0,
                            count: count
                        )
                    }
                Canvas { context, size in
                    let centerX = size.width / 2
                    var track = Path()
                    track.move(to: CGPoint(x: centerX, y: 5))
                    track.addLine(
                        to: CGPoint(x: centerX, y: size.height - 5)
                    )
                    context.stroke(
                        track,
                        with: .color(GitMateTheme.border),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )

                    let thumbStart = trackY(
                        viewportRange.start,
                        height: size.height
                    )
                    let thumbEnd = trackY(
                        viewportRange.end,
                        height: size.height
                    )
                    let trackMinimumY: CGFloat = 5
                    let trackMaximumY = max(
                        size.height - 5,
                        trackMinimumY
                    )
                    let availableHeight = max(
                        trackMaximumY - trackMinimumY,
                        0
                    )
                    let thumbHeight = min(
                        max(thumbEnd - thumbStart, 12),
                        availableHeight
                    )
                    let maximumThumbY = max(
                        trackMaximumY - thumbHeight,
                        trackMinimumY
                    )
                    let thumbY = min(
                        max(thumbStart, trackMinimumY),
                        maximumThumbY
                    )
                    let thumbRect = CGRect(
                        x: centerX - 7,
                        y: thumbY,
                        width: 14,
                        height: thumbHeight
                    )
                    context.fill(
                        Path(
                            roundedRect: thumbRect,
                            cornerRadius: 7
                        ),
                        with: .color(GitMateTheme.accent.opacity(0.17))
                    )
                    context.stroke(
                        Path(
                            roundedRect: thumbRect,
                            cornerRadius: 7
                        ),
                        with: .color(GitMateTheme.accent.opacity(0.8)),
                        lineWidth: 1.3
                    )

                    for marker in markerBins {
                        let y = trackY(
                            marker.progress,
                            height: size.height
                        )
                        let color = markerColor(marker)
                        let width: CGFloat = marker.kind == .head ? 18 : 12
                        let rect = CGRect(
                            x: centerX - width / 2,
                            y: y - 2,
                            width: width,
                            height: 4
                        )
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: 2),
                            with: .color(color)
                        )
                    }

                    if let activeProgress {
                        let y = 5 + CGFloat(activeProgress)
                            * max(size.height - 10, 0)
                        let circle = CGRect(
                            x: centerX - 6,
                            y: y - 6,
                            width: 12,
                            height: 12
                        )
                        context.fill(
                            Path(ellipseIn: circle),
                            with: .color(.white)
                        )
                        context.stroke(
                            Path(ellipseIn: circle),
                            with: .color(GitMateTheme.accent),
                            lineWidth: 2.5
                        )
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let value = progress(
                                y: value.location.y,
                                height: geometry.size.height
                            )
                            previewProgress = value
                            navigate(value)
                        }
                        .onEnded { value in
                            let value = progress(
                                y: value.location.y,
                                height: geometry.size.height
                            )
                            previewProgress = nil
                            navigate(value)
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("提交历史导航")
                .accessibilityValue(
                    currentRow.map { "第 \($0 + 1) 个，共 \(count) 个" }
                        ?? "未选择"
                )
                .accessibilityAdjustableAction { direction in
                    let current = currentRow ?? 0
                    let target = direction == .increment
                        ? min(current + 1, max(count - 1, 0))
                        : max(current - 1, 0)
                    navigate(
                        CommitGraphHistoryNavigation.progress(
                            row: target,
                            count: count
                        )
                    )
                }
            }

            Text("最新")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 7)
        .frame(width: 54)
        .background(.white.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(GitMateTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
        .accessibilityIdentifier("workspace.commitGraph.historyNavigator")
    }

    private func trackY(_ progress: Double, height: CGFloat) -> CGFloat {
        5 + CGFloat(progress) * max(height - 10, 0)
    }

    private func progress(y: CGFloat, height: CGFloat) -> Double {
        guard height > 10 else { return 0 }
        return min(max(Double((y - 5) / (height - 10)), 0), 1)
    }

    private func markerColor(_ marker: CommitGraphHistoryMarkerBin) -> Color {
        switch marker.kind {
        case .head:
            GitMateTheme.danger
        case .localBranch:
            GitMateTheme.accent
        case .remoteBranch:
            Color(red: 0.37, green: 0.20, blue: 0.68)
        case .tag:
            GitMateTheme.warning
        case .group:
            GitMateTheme.success
        case .region:
            marker.colorHex.map(CommitGraphRegionColor.color(hex:))
                ?? GitMateTheme.textSecondary
        }
    }
}
