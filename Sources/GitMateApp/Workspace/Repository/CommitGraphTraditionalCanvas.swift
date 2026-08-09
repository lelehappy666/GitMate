import AppKit
import GitMateCore
import SwiftUI

enum CommitGraphTraditionalMetrics {
    static let rowHeight = 56.0
    static let avatarSize = 28.0
}

struct CommitGraphTraditionalCanvas: View {
    private struct Badge {
        let text: String
        let color: Color
    }

    private struct BadgePlan {
        let visible: [Badge]
        let hiddenCount: Int
        let totalWidth: Double
    }

    let layout: CommitGraphTraditionalLayoutResult
    let branchProjection: CommitGraphTraditionalBranchProjection
    let segmentProjection: CommitGraphTraditionalSegmentProjection
    let publicationIndex: CommitGraphTraditionalPublicationIndex
    let groupByHash: [String: CommitGraphTraditionalGroupBadge]
    let groupRevision: UInt64
    let visibleRows: Range<Int>
    let verticalOffset: Double
    let laneViewportWidth: Double
    let laneHorizontalOffset: Double
    let selectedHash: String?

    var body: some View {
        Canvas { context, size in
            drawRowBackgrounds(
                context: &context,
                size: size,
                laneWidth: laneViewportWidth
            )
            drawLanes(
                context: &context,
                size: size,
                laneWidth: laneViewportWidth
            )
            drawInformation(
                context: &context,
                size: size,
                laneWidth: laneViewportWidth
            )
            drawDivider(
                context: &context,
                size: size,
                laneWidth: laneViewportWidth
            )
        }
        .background(.white)
    }

    private func drawRowBackgrounds(
        context: inout GraphicsContext,
        size: CGSize,
        laneWidth: Double
    ) {
        for rowIndex in visibleRows {
            guard layout.rows.indices.contains(rowIndex) else { continue }
            let row = layout.rows[rowIndex]
            let rect = rowRect(rowIndex, width: Double(size.width))
            guard rect.maxY >= 0, rect.minY <= size.height else { continue }

            if row.commit.fullHash == selectedHash {
                context.fill(
                    Path(rect),
                    with: .color(GitMateTheme.accent.opacity(0.085))
                )
                let indicator = CGRect(
                    x: laneWidth,
                    y: rect.minY + 7,
                    width: 3,
                    height: rect.height - 14
                )
                context.fill(
                    Path(roundedRect: indicator, cornerRadius: 1.5),
                    with: .color(GitMateTheme.accent)
                )
            } else if rowIndex.isMultiple(of: 2) {
                context.fill(
                    Path(rect),
                    with: .color(GitMateTheme.panel.opacity(0.45))
                )
            }

            var separator = Path()
            separator.move(to: CGPoint(x: 0, y: rect.maxY))
            separator.addLine(to: CGPoint(x: size.width, y: rect.maxY))
            context.stroke(
                separator,
                with: .color(GitMateTheme.border.opacity(0.62)),
                lineWidth: 0.7
            )
        }
    }

    private func drawLanes(
        context: inout GraphicsContext,
        size: CGSize,
        laneWidth: Double
    ) {
        context.drawLayer { layer in
            layer.clip(to: Path(CGRect(
                x: 0,
                y: 0,
                width: laneWidth,
                height: Double(size.height)
            )))

            for span in layout.connectionSpans(
                intersecting: visibleRows
            ) {
                let rawConnection = span.connection
                let connection = segmentProjection.connection(
                    childHash: rawConnection.childHash,
                    parentHash: rawConnection.parentHash
                ) ?? rawConnection
                let source = lanePoint(
                    row: span.sourceRow,
                    lane: connection.sourceLane,
                    laneWidth: laneWidth
                )
                let target = lanePoint(
                    row: span.targetRow,
                    lane: connection.targetLane,
                    laneWidth: laneWidth
                )
                guard laneSpanIntersectsViewport(
                    sourceX: source.x,
                    targetX: target.x,
                    laneWidth: laneWidth
                ) else { continue }
                let isLocalUnpushed = publicationIndex.isDashed(
                    childHash: connection.childHash
                )
                var path = Path()
                path.move(to: source)
                appendRoute(
                    CommitGraphTraditionalRoute.segments(
                        source: GraphPoint(x: source.x, y: source.y),
                        target: GraphPoint(x: target.x, y: target.y),
                        kind: connection.kind,
                        rowHeight: CommitGraphTraditionalMetrics.rowHeight
                    ),
                    to: &path
                )
                layer.stroke(
                    path,
                    with: .color(
                        CommitGraphPalette.color(
                            connection.colorIndex
                        ).opacity(connection.kind == .merge ? 0.78 : 0.9)
                    ),
                    style: StrokeStyle(
                        lineWidth: connection.kind == .merge ? 2.2 : 2,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: isLocalUnpushed ? [6, 4] : []
                    )
                )
            }

            for endpoint in layout.shallowBoundaryEndpoints {
                guard visibleRows.contains(endpoint.row),
                      let child = layout.row(hash: endpoint.childHash)
                else {
                    continue
                }
                let source = lanePoint(
                    row: child.row,
                    lane: segmentProjection.lane(
                        for: endpoint.childHash
                    ) ?? child.lane,
                    laneWidth: laneWidth
                )
                let target = lanePoint(
                    row: endpoint.row,
                    lane: segmentProjection.lane(
                        for: endpoint.childHash
                    ) ?? endpoint.lane,
                    laneWidth: laneWidth
                )
                var path = Path()
                path.move(to: source)
                let middleY = source.y + (target.y - source.y) * 0.5
                path.addCurve(
                    to: target,
                    control1: CGPoint(x: source.x, y: middleY),
                    control2: CGPoint(x: target.x, y: middleY)
                )
                layer.stroke(
                    path,
                    with: .color(GitMateTheme.warning),
                    style: StrokeStyle(
                        lineWidth: 2,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [5, 4]
                    )
                )
                let marker = CGRect(
                    x: target.x - 4,
                    y: target.y - 4,
                    width: 8,
                    height: 8
                )
                var diamond = Path()
                diamond.move(to: CGPoint(x: marker.midX, y: marker.minY))
                diamond.addLine(to: CGPoint(x: marker.maxX, y: marker.midY))
                diamond.addLine(to: CGPoint(x: marker.midX, y: marker.maxY))
                diamond.addLine(to: CGPoint(x: marker.minX, y: marker.midY))
                diamond.closeSubpath()
                layer.fill(
                    diamond,
                    with: .color(GitMateTheme.warning.opacity(0.2))
                )
                layer.stroke(
                    diamond,
                    with: .color(GitMateTheme.warning),
                    lineWidth: 1.4
                )
            }

            for rowIndex in visibleRows {
                guard layout.rows.indices.contains(rowIndex) else { continue }
                let row = layout.rows[rowIndex]
                let source = lanePoint(
                    row: rowIndex,
                    lane: segmentProjection.lane(
                        for: row.commit.fullHash
                    ) ?? row.lane,
                    laneWidth: laneWidth
                )

                let color = CommitGraphPalette.color(
                    segmentProjection.colorIndex(
                        for: row.commit.fullHash
                    ) ?? row.colorIndex
                )
                guard source.x >= -12, source.x <= laneWidth + 12 else {
                    continue
                }
                let isLocalUnpushed = publicationIndex.isDashed(
                    childHash: row.commit.fullHash
                )
                let outer = CGRect(
                    x: source.x - 6,
                    y: source.y - 6,
                    width: 12,
                    height: 12
                )
                layer.fill(Path(ellipseIn: outer), with: .color(.white))
                layer.stroke(
                    Path(ellipseIn: outer),
                    with: .color(color),
                    style: StrokeStyle(
                        lineWidth: 2.4,
                        dash: isLocalUnpushed ? [3, 2] : []
                    )
                )
                if row.commit.fullHash == selectedHash {
                    layer.fill(
                        Path(ellipseIn: outer.insetBy(dx: 3.3, dy: 3.3)),
                        with: .color(color)
                    )
                }
            }

        }

        for endpoint in layout.shallowBoundaryEndpoints
        where visibleRows.contains(endpoint.row) {
            let rect = rowRect(endpoint.row, width: Double(size.width))
            guard rect.maxY >= 0, rect.minY <= size.height else { continue }
            context.draw(
                Text("浅克隆边界 · \(endpoint.missingParentHash)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(GitMateTheme.warning),
                at: CGPoint(x: laneWidth + 18, y: rect.midY),
                anchor: .leading
            )
        }
    }

    private func drawInformation(
        context: inout GraphicsContext,
        size: CGSize,
        laneWidth: Double
    ) {
        for rowIndex in visibleRows {
            guard layout.rows.indices.contains(rowIndex) else { continue }
            let row = layout.rows[rowIndex]
            let rowRect = rowRect(rowIndex, width: Double(size.width))
            guard rowRect.maxY >= 0, rowRect.minY <= size.height else { continue }

            context.drawLayer { layer in
                let clippedRect = CGRect(
                    x: laneWidth + 1,
                    y: rowRect.minY,
                    width: max(Double(size.width) - laneWidth - 1, 0),
                    height: rowRect.height
                )
                layer.clip(to: Path(
                    roundedRect: clippedRect.insetBy(dx: 5, dy: 4),
                    cornerRadius: 8
                ))

                let avatarX = laneWidth + 18
                let textX = avatarX
                    + CommitGraphTraditionalMetrics.avatarSize + 12
                let hashRect = CGRect(
                    x: Double(size.width) - 80,
                    y: rowRect.minY + 8,
                    width: 66,
                    height: 18
                )
                let headerTrailingX = hashRect.minX - 8
                let badgePlan = badgePlan(
                    badges: badges(for: row),
                    maximumWidth: max(
                        headerTrailingX - textX - 140,
                        0
                    )
                )
                drawBadgePlan(
                    badgePlan,
                    trailingX: headerTrailingX,
                    centerY: rowRect.minY + 18,
                    context: &layer
                )
                let textWidth = max(
                    headerTrailingX - textX
                        - badgePlan.totalWidth
                        - (badgePlan.totalWidth > 0 ? 8 : 0),
                    1
                )
                drawFittedText(
                    row.commit.subject,
                    in: CGRect(
                        x: textX,
                        y: rowRect.minY + 8,
                        width: textWidth,
                        height: 20
                    ),
                    font: .systemFont(ofSize: 13, weight: .semibold),
                    color: NSColor.labelColor,
                    context: &layer
                )
                drawFittedText(
                    row.commit.authorName,
                    in: CGRect(
                        x: textX,
                        y: rowRect.minY + 30,
                        width: max(
                            Double(size.width) - textX - 124,
                            1
                        ),
                        height: 16
                    ),
                    font: .systemFont(ofSize: 10.5, weight: .medium),
                    color: NSColor.secondaryLabelColor,
                    context: &layer
                )

                drawFittedText(
                    row.commit.shortHash,
                    in: hashRect,
                    font: .monospacedSystemFont(
                        ofSize: 10.5,
                        weight: .medium
                    ),
                    color: NSColor.secondaryLabelColor,
                    context: &layer
                )

                let relativeDate = row.commit.authoredAt.formatted(
                    .relative(presentation: .named)
                )
                drawTrailingText(
                    relativeDate,
                    x: Double(size.width) - 14,
                    y: rowRect.minY + 39,
                    context: &layer
                )

            }
        }
    }

    private func badges(
        for row: CommitGraphTraditionalRow
    ) -> [Badge] {
        var result: [Badge] = []
        if publicationIndex.state(for: row.commit.fullHash)
            == .localUnpushed {
            result.append(
                Badge(
                    text: "未推送",
                    color: GitMateTheme.warning
                )
            )
        }
        if let group = groupByHash[row.commit.fullHash] {
            result.append(
                Badge(
                    text: group.isCollapsed
                        ? "分组·已折叠"
                        : "分组·\(group.title)",
                    color: CommitGraphPalette.color(
                        groupID: group.groupID
                    )
                )
            )
        }
        result.append(
            contentsOf: layout.references(
                hash: row.commit.fullHash
            ).map { reference in
                switch reference.kind {
                case .head:
                    Badge(
                        text: reference.name,
                        color: GitMateTheme.accent
                    )
                case .localBranch:
                    Badge(
                        text: reference.name,
                        color: CommitGraphPalette.color(
                            segmentProjection.colorIndex(
                                for: row.commit.fullHash
                            ) ?? row.colorIndex
                        )
                    )
                case .remoteBranch:
                    Badge(
                        text: "远程·\(reference.name)",
                        color: Color(red: 0.37, green: 0.20, blue: 0.68)
                    )
                case .tag:
                    Badge(
                        text: "标签·\(reference.name)",
                        color: GitMateTheme.warning
                    )
                }
            }
        )
        return result
    }

    private func badgePlan(
        badges: [Badge],
        maximumWidth: Double
    ) -> BadgePlan {
        guard !badges.isEmpty, maximumWidth > 0 else {
            return BadgePlan(
                visible: [],
                hiddenCount: 0,
                totalWidth: 0
            )
        }
        let gap = 5.0
        let allWidth = badges.enumerated().reduce(0.0) { partial, item in
            partial + badgeWidth(item.element.text)
                + (item.offset == 0 ? 0 : gap)
        }
        if allWidth <= maximumWidth {
            return BadgePlan(
                visible: badges,
                hiddenCount: 0,
                totalWidth: allWidth
            )
        }

        for visibleCount in stride(
            from: badges.count - 1,
            through: 0,
            by: -1
        ) {
            let hiddenCount = badges.count - visibleCount
            let visible = Array(badges.prefix(visibleCount))
            let visibleWidth = visible.enumerated().reduce(0.0) {
                partial,
                item in
                partial + badgeWidth(item.element.text)
                    + (item.offset == 0 ? 0 : gap)
            }
            let hiddenWidth = badgeWidth("+\(hiddenCount)")
            let totalWidth = visibleWidth
                + (visible.isEmpty ? 0 : gap)
                + hiddenWidth
            if totalWidth <= maximumWidth {
                return BadgePlan(
                    visible: visible,
                    hiddenCount: hiddenCount,
                    totalWidth: totalWidth
                )
            }
        }
        return BadgePlan(
            visible: [],
            hiddenCount: 0,
            totalWidth: 0
        )
    }

    private func drawBadgePlan(
        _ plan: BadgePlan,
        trailingX: Double,
        centerY: Double,
        context: inout GraphicsContext
    ) {
        var x = trailingX
        if plan.hiddenCount > 0 {
            x = drawBadge(
                "+\(plan.hiddenCount)",
                color: GitMateTheme.textSecondary,
                trailingX: x,
                centerY: centerY,
                context: &context
            ) - 5
        }
        for badge in plan.visible.reversed() {
            x = drawBadge(
                badge.text,
                color: badge.color,
                trailingX: x,
                centerY: centerY,
                context: &context
            ) - 5
        }
    }

    private func drawBadge(
        _ text: String,
        color: Color,
        trailingX: Double,
        centerY: Double,
        context: inout GraphicsContext
    ) -> Double {
        let font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        let width = badgeWidth(text)
        let rect = CGRect(
            x: trailingX - width,
            y: centerY - 9,
            width: width,
            height: 18
        )
        context.fill(
            Path(roundedRect: rect, cornerRadius: 9),
            with: .color(color.opacity(0.1))
        )
        drawFittedText(
            text,
            in: rect.insetBy(dx: 7, dy: 1),
            font: font,
            color: NSColor(color),
            context: &context
        )
        return rect.minX
    }

    private func badgeWidth(_ text: String) -> Double {
        let font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        return min(max(measuredWidth(text, font: font) + 14, 34), 118)
    }

    private func drawTrailingText(
        _ text: String,
        x: Double,
        y: Double,
        context: inout GraphicsContext
    ) {
        context.draw(
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary),
            at: CGPoint(x: x, y: y),
            anchor: .trailing
        )
    }

    private func drawDivider(
        context: inout GraphicsContext,
        size: CGSize,
        laneWidth: Double
    ) {
        var path = Path()
        path.move(to: CGPoint(x: laneWidth, y: 0))
        path.addLine(to: CGPoint(x: laneWidth, y: size.height))
        context.stroke(path, with: .color(GitMateTheme.border), lineWidth: 1)
    }

    private func lanePoint(
        row: Int,
        lane: Int,
        laneWidth: Double
    ) -> CGPoint {
        let slotCount = max(branchProjection.slots.count, 1)
        return CGPoint(
            x: CommitGraphTraditionalLaneGeometry.leadingPadding
                + Double(min(max(lane, 0), slotCount - 1))
                    * CommitGraphTraditionalLaneGeometry.spacing
                - laneHorizontalOffset,
            y: Double(row) * CommitGraphTraditionalMetrics.rowHeight
                + CommitGraphTraditionalMetrics.rowHeight / 2
                - verticalOffset
        )
    }

    private func laneSpanIntersectsViewport(
        sourceX: Double,
        targetX: Double,
        laneWidth: Double
    ) -> Bool {
        let padding = CommitGraphTraditionalLaneGeometry.spacing
        let minimum = min(sourceX, targetX)
        let maximum = max(sourceX, targetX)
        return maximum >= -padding && minimum <= laneWidth + padding
    }

    private func appendRoute(
        _ segments: [CommitGraphTraditionalRouteSegment],
        to path: inout Path
    ) {
        for segment in segments {
            switch segment {
            case let .line(point):
                path.addLine(to: CGPoint(x: point.x, y: point.y))
            case let .curve(end, control1, control2):
                path.addCurve(
                    to: CGPoint(x: end.x, y: end.y),
                    control1: CGPoint(x: control1.x, y: control1.y),
                    control2: CGPoint(x: control2.x, y: control2.y)
                )
            }
        }
    }

    private func rowRect(_ row: Int, width: Double) -> CGRect {
        CGRect(
            x: 0,
            y: Double(row) * CommitGraphTraditionalMetrics.rowHeight
                - verticalOffset,
            width: width,
            height: CommitGraphTraditionalMetrics.rowHeight
        )
    }

    private func drawFittedText(
        _ value: String,
        in rect: CGRect,
        font: NSFont,
        color: NSColor,
        context: inout GraphicsContext
    ) {
        let fitted = CommitGraphTextFitter.truncated(
            value,
            maximumWidth: Double(max(rect.width, 1)),
            measure: { measuredWidth($0, font: font) }
        )
        context.draw(
            Text(fitted)
                .font(.init(font))
                .foregroundStyle(Color(nsColor: color)),
            at: CGPoint(x: rect.minX, y: rect.midY),
            anchor: .leading
        )
    }

    private func measuredWidth(_ value: String, font: NSFont) -> Double {
        Double(ceil(NSAttributedString(
            string: value,
            attributes: [.font: font]
        ).size().width))
    }
}
