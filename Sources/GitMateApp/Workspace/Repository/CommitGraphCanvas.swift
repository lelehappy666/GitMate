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

struct CommitGraphCanvas: View {
    let layout: CommitGraphLayoutResult
    let viewport: GraphViewport
    let selectedHash: String?

    var body: some View {
        Canvas { context, size in
            drawGrid(context: &context, size: size, viewport: viewport)
            drawVisibleEdges(
                context: &context,
                size: size,
                layout: layout,
                viewport: viewport
            )
            drawVisibleNodes(
                context: &context,
                size: size,
                layout: layout,
                viewport: viewport
            )
        }
        .background(.white)
    }

    private func drawGrid(
        context: inout GraphicsContext,
        size: CGSize,
        viewport: GraphViewport
    ) {
        let step = max(CGFloat(32 * viewport.scale), 18)
        let startX = CGFloat(viewport.offsetX).truncatingRemainder(
            dividingBy: step
        )
        let startY = CGFloat(viewport.offsetY).truncatingRemainder(
            dividingBy: step
        )
        var path = Path()
        var x = startX
        while x < size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        var y = startY
        while y < size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        context.stroke(
            path,
            with: .color(GitMateTheme.border.opacity(0.44)),
            lineWidth: 0.7
        )
    }

    private func drawVisibleEdges(
        context: inout GraphicsContext,
        size: CGSize,
        layout: CommitGraphLayoutResult,
        viewport: GraphViewport
    ) {
        let nodesByHash = Dictionary(
            uniqueKeysWithValues: layout.nodes.map { ($0.hash, $0) }
        )
        let padding: CGFloat = 180

        for edge in layout.edges {
            guard let child = nodesByHash[edge.childHash],
                  let parent = nodesByHash[edge.parentHash]
            else {
                continue
            }
            let start = screenPoint(for: child, viewport: viewport)
            let end = screenPoint(for: parent, viewport: viewport)
            guard edgeMayBeVisible(
                from: start,
                to: end,
                screenSize: size,
                padding: padding
            ) else {
                continue
            }

            let midpointY = (start.y + end.y) / 2
            var path = Path()
            path.move(to: start)
            path.addCurve(
                to: end,
                control1: CGPoint(x: start.x, y: midpointY),
                control2: CGPoint(x: end.x, y: midpointY)
            )
            context.stroke(
                path,
                with: .color(
                    CommitGraphPalette.color(edge.colorIndex).opacity(0.88)
                ),
                style: StrokeStyle(
                    lineWidth: edge.kind == .merge ? 2.3 : 2,
                    lineCap: .round,
                    dash: edge.kind == .merge ? [7, 4] : []
                )
            )
        }
    }

    private func drawVisibleNodes(
        context: inout GraphicsContext,
        size: CGSize,
        layout: CommitGraphLayoutResult,
        viewport: GraphViewport
    ) {
        let nodes = CommitGraphViewportProjector.visibleNodes(
            layout: layout,
            viewport: viewport,
            screenSize: GraphSize(
                width: Double(size.width),
                height: Double(size.height)
            ),
            padding: 180
        )
        for node in nodes {
            drawNode(
                node,
                isSelected: node.hash == selectedHash,
                context: &context,
                viewport: viewport
            )
        }
    }

    private func drawNode(
        _ node: CommitGraphNode,
        isSelected: Bool,
        context: inout GraphicsContext,
        viewport: GraphViewport
    ) {
        let scale = CGFloat(viewport.scale)
        let center = screenPoint(for: node, viewport: viewport)
        let width = CGFloat(CommitGraphViewportProjector.nodeWidth) * scale
        let height = CGFloat(CommitGraphViewportProjector.nodeHeight) * scale
        let rect = CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
        let card = Path(
            roundedRect: rect,
            cornerRadius: 11 * scale
        )
        let branchColor = CommitGraphPalette.color(node.colorIndex)

        context.fill(card, with: .color(.white))
        context.stroke(
            card,
            with: .color(isSelected ? GitMateTheme.accent : branchColor),
            lineWidth: (isSelected ? 2.5 : 1.35) * scale
        )

        let avatarSize = 32 * scale
        let avatarCenter = CGPoint(
            x: rect.minX + 11 * scale + avatarSize / 2,
            y: rect.minY + 11 * scale + avatarSize / 2
        )
        let avatarRect = CGRect(
            x: avatarCenter.x - avatarSize / 2,
            y: avatarCenter.y - avatarSize / 2,
            width: avatarSize,
            height: avatarSize
        )
        context.fill(
            Path(ellipseIn: avatarRect),
            with: .color(branchColor.opacity(0.14))
        )
        context.draw(
            Text(authorInitials(node.authorName))
                .font(.system(size: 11 * scale, weight: .bold))
                .foregroundStyle(branchColor),
            at: avatarCenter,
            anchor: .center
        )

        let textX = avatarRect.maxX + 10 * scale
        let subjectY = rect.minY + 10 * scale
        context.draw(
            Text(truncated(node.subject, limit: 34))
                .font(.system(size: 12.5 * scale, weight: .semibold))
                .foregroundStyle(GitMateTheme.textPrimary),
            at: CGPoint(x: textX, y: subjectY),
            anchor: .topLeading
        )

        let metadataY = rect.maxY - 16 * scale
        context.draw(
            Text(truncated(node.authorName, limit: 14))
                .font(.system(size: 10.5 * scale, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary),
            at: CGPoint(x: textX, y: metadataY),
            anchor: .leading
        )
        context.draw(
            Text(node.shortHash)
                .font(
                    .system(
                        size: 10.5 * scale,
                        weight: .medium,
                        design: .monospaced
                    )
                )
                .foregroundStyle(GitMateTheme.textSecondary),
            at: CGPoint(x: textX + 72 * scale, y: metadataY),
            anchor: .leading
        )

        if let decoration = node.decorations.first {
            drawDecoration(
                truncated(decoration, limit: 16),
                color: branchColor,
                at: CGPoint(
                    x: rect.maxX - 9 * scale,
                    y: metadataY
                ),
                context: &context,
                scale: scale
            )
        }
    }

    private func drawDecoration(
        _ decoration: String,
        color: Color,
        at trailingPoint: CGPoint,
        context: inout GraphicsContext,
        scale: CGFloat
    ) {
        let width = min(
            max(CGFloat(decoration.count) * 5.8 + 10, 28),
            88
        ) * scale
        let height = 17 * scale
        let rect = CGRect(
            x: trailingPoint.x - width,
            y: trailingPoint.y - height / 2,
            width: width,
            height: height
        )
        context.fill(
            Path(roundedRect: rect, cornerRadius: height / 2),
            with: .color(color.opacity(0.11))
        )
        context.draw(
            Text(decoration)
                .font(.system(size: 9.5 * scale, weight: .medium))
                .foregroundStyle(color),
            at: CGPoint(x: rect.midX, y: rect.midY),
            anchor: .center
        )
    }

    private func screenPoint(
        for node: CommitGraphNode,
        viewport: GraphViewport
    ) -> CGPoint {
        let point = CommitGraphViewportProjector.screenPoint(
            canvasPoint: GraphPoint(x: node.x, y: node.y),
            viewport: viewport
        )
        return CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
    }

    private func edgeMayBeVisible(
        from start: CGPoint,
        to end: CGPoint,
        screenSize: CGSize,
        padding: CGFloat
    ) -> Bool {
        max(start.x, end.x) >= -padding
            && min(start.x, end.x) <= screenSize.width + padding
            && max(start.y, end.y) >= -padding
            && min(start.y, end.y) <= screenSize.height + padding
    }

    private func authorInitials(_ author: String) -> String {
        let parts = author.split(separator: " ")
        let initials = parts.prefix(2).compactMap(\.first)
        return initials.isEmpty
            ? "?"
            : String(initials).uppercased()
    }

    private func truncated(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(max(limit - 1, 1))) + "…"
    }
}
