import AppKit
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
        colors[abs(index) % colors.count]
    }

    static func color(groupID: UUID) -> Color {
        let index = groupID.uuidString.utf8.reduce(0) {
            ($0 + Int($1)) % colors.count
        }
        return color(index)
    }
}

struct CommitGraphCanvas: View {
    let visibleScene: CommitGraphVisibleScene
    let regions: [CommitGraphRegionMarker]
    let branchBundles: [CommitGraphBranchBundle]
    let hiddenBundleMemberHashes: Set<String>
    let hiddenBundleEdgeIDs: Set<String>
    let viewport: GraphViewport
    let levelOfDetail: CommitGraphLevelOfDetail
    let selectedHashes: Set<String>
    let selectedHash: String?
    let highlightedEdgeIDs: Set<String>
    let highlightedNodeHashes: Set<String>

    var body: some View {
        Canvas { context, size in
            drawGrid(context: &context, size: size)
            drawRegions(context: &context, size: size)
            drawExpandedGroups(context: &context, size: size)
            drawVisibleEdges(context: &context, size: size)
            drawBranchBundles(context: &context, size: size)
            drawShallowBoundaryEndpoints(context: &context, size: size)
            drawVisibleNodes(context: &context, size: size)
            drawCollapsedGroups(context: &context, size: size)
        }
        .background(.white)
    }

    private func drawRegions(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        for region in regions {
            let rect = screenRect(region.rect)
            guard isVisible(rect, in: size, padding: 120) else {
                continue
            }
            let color = CommitGraphRegionColor.color(
                hex: region.colorHex
            )
            let shape = Path(
                roundedRect: rect,
                cornerRadius: max(15 * viewport.scale, 7)
            )
            context.fill(shape, with: .color(color.opacity(0.045)))
            context.stroke(
                shape,
                with: .color(color.opacity(0.62)),
                style: StrokeStyle(
                    lineWidth: max(1.4 * viewport.scale, 1),
                    dash: [10 * viewport.scale, 5 * viewport.scale]
                )
            )

            let headerHeight = min(
                36 * viewport.scale,
                rect.height
            )
            let headerRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: headerHeight
            )
            context.fill(
                Path(
                    roundedRect: headerRect,
                    cornerRadius: max(15 * viewport.scale, 7)
                ),
                with: .color(color.opacity(0.13))
            )
            drawFittedText(
                region.title,
                in: headerRect.insetBy(
                    dx: 13 * viewport.scale,
                    dy: 4 * viewport.scale
                ),
                font: .systemFont(
                    ofSize: max(12 * viewport.scale, 7),
                    weight: .bold
                ),
                color: NSColor.labelColor,
                context: &context
            )

            let handleSize = max(10 * viewport.scale, 7)
            let handleRect = CGRect(
                x: rect.maxX - handleSize - 5 * viewport.scale,
                y: rect.maxY - handleSize - 5 * viewport.scale,
                width: handleSize,
                height: handleSize
            )
            context.fill(
                Path(
                    roundedRect: handleRect,
                    cornerRadius: max(3 * viewport.scale, 2)
                ),
                with: .color(color.opacity(0.75))
            )
        }
    }

    private func drawGrid(
        context: inout GraphicsContext,
        size: CGSize
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

    private func drawExpandedGroups(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        for group in visibleScene.groups where !group.isCollapsed {
            let rect = screenRect(group.rect)
            guard isVisible(rect, in: size) else { continue }
            let color = CommitGraphPalette.color(groupID: group.id)
            let shape = Path(
                roundedRect: rect,
                cornerRadius: max(12 * viewport.scale, 6)
            )
            context.fill(shape, with: .color(color.opacity(0.055)))
            context.stroke(
                shape,
                with: .color(color.opacity(0.58)),
                style: StrokeStyle(
                    lineWidth: max(1.2 * viewport.scale, 1),
                    dash: [7 * viewport.scale, 5 * viewport.scale]
                )
            )

            let headerHeight = 34 * viewport.scale
            let headerRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: headerHeight
            )
            context.fill(
                Path(
                    roundedRect: headerRect,
                    cornerRadius: max(12 * viewport.scale, 6)
                ),
                with: .color(color.opacity(0.095))
            )
            let titleRect = CGRect(
                x: headerRect.minX + 13 * viewport.scale,
                y: headerRect.minY,
                width: max(
                    headerRect.width - 120 * viewport.scale,
                    20
                ),
                height: headerRect.height
            )
            if levelOfDetail != .overview {
                drawFittedText(
                    group.title,
                    in: titleRect,
                    font: .systemFont(
                        ofSize: max(11.5 * viewport.scale, 7),
                        weight: .semibold
                    ),
                    color: NSColor.labelColor,
                    context: &context
                )
                if levelOfDetail == .full {
                    context.draw(
                        Text("\(group.memberCount) 个提交 · 双击折叠")
                            .font(
                                .system(
                                    size: max(9.5 * viewport.scale, 6),
                                    weight: .medium
                                )
                            )
                            .foregroundStyle(color),
                        at: CGPoint(
                            x: headerRect.maxX - 12 * viewport.scale,
                            y: headerRect.midY
                        ),
                        anchor: .trailing
                    )
                }
            }
        }
    }

    private func drawVisibleEdges(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        for edge in visibleScene.edges {
            guard !hiddenBundleEdgeIDs.contains(edge.id) else { continue }
            guard let generated = edge.path else { continue }
            var path = Path()
            switch generated {
            case let .curve(start, control1, control2, end):
                path.move(to: screenPoint(start))
                path.addCurve(
                    to: screenPoint(end),
                    control1: screenPoint(control1),
                    control2: screenPoint(control2)
                )
            case let .polyline(points):
                guard let first = points.first else { continue }
                path.move(to: screenPoint(first))
                for point in points.dropFirst() {
                    path.addLine(to: screenPoint(point))
                }
            case let .roundedPolyline(points, radius):
                addRoundedPolyline(
                    points,
                    radius: radius,
                    to: &path
                )
            }

            let color = edge.kind == .shallowBoundary
                ? GitMateTheme.warning
                : CommitGraphPalette.color(edge.colorIndex)
            let isRelated = highlightedEdgeIDs.contains(edge.id)
            context.stroke(
                path,
                with: .color(color.opacity(isRelated ? 1 : 0.72)),
                style: StrokeStyle(
                    lineWidth: max(
                        (edge.kind == .merge ? 2.3 : 2)
                            * (isRelated ? 1.65 : 1)
                            * viewport.scale,
                        1
                    ),
                    lineCap: .round,
                    lineJoin: .round,
                    dash: edge.publicationState.isDashed
                        ? [7 * viewport.scale, 5 * viewport.scale]
                        : (edge.kind == .shallowBoundary
                            ? [5 * viewport.scale, 4 * viewport.scale]
                            : [])
                )
            )
            if edge.aggregateCount > 1 && levelOfDetail != .overview {
                drawAggregateCount(
                    edge.aggregateCount,
                    path: generated,
                    color: color,
                    context: &context
                )
            }
        }
    }

    private func addRoundedPolyline(
        _ points: [GraphPoint],
        radius: Double,
        to path: inout Path
    ) {
        guard let first = points.first else { return }
        path.move(to: screenPoint(first))
        guard points.count > 2 else {
            for point in points.dropFirst() {
                path.addLine(to: screenPoint(point))
            }
            return
        }
        for index in 1..<(points.count - 1) {
            let previous = points[index - 1]
            let corner = points[index]
            let next = points[index + 1]
            let incoming = hypot(corner.x - previous.x, corner.y - previous.y)
            let outgoing = hypot(next.x - corner.x, next.y - corner.y)
            let safeRadius = min(max(radius, 0), incoming / 2, outgoing / 2)
            guard safeRadius > 0 else {
                path.addLine(to: screenPoint(corner))
                continue
            }
            let entry = GraphPoint(
                x: corner.x + (previous.x - corner.x) * safeRadius / incoming,
                y: corner.y + (previous.y - corner.y) * safeRadius / incoming
            )
            let exit = GraphPoint(
                x: corner.x + (next.x - corner.x) * safeRadius / outgoing,
                y: corner.y + (next.y - corner.y) * safeRadius / outgoing
            )
            path.addLine(to: screenPoint(entry))
            path.addQuadCurve(
                to: screenPoint(exit),
                control: screenPoint(corner)
            )
        }
        if let last = points.last {
            path.addLine(to: screenPoint(last))
        }
    }

    private func drawBranchBundles(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        guard levelOfDetail == .overview else { return }
        for bundle in branchBundles {
            let rect = screenRect(bundle.rect)
            guard isVisible(rect, in: size, padding: 80) else { continue }
            let color = CommitGraphPalette.color(bundle.colorIndex)
            let centerX = rect.midX
            let startY = rect.minY + min(18 * viewport.scale, rect.height / 3)
            let endY = rect.maxY - min(18 * viewport.scale, rect.height / 3)
            var branch = Path()
            branch.move(to: CGPoint(x: centerX, y: startY))
            branch.addCurve(
                to: CGPoint(x: centerX, y: endY),
                control1: CGPoint(
                    x: centerX - 11 * viewport.scale,
                    y: startY + (endY - startY) * 0.34
                ),
                control2: CGPoint(
                    x: centerX + 11 * viewport.scale,
                    y: startY + (endY - startY) * 0.66
                )
            )
            context.stroke(
                branch,
                with: .color(color.opacity(0.28)),
                style: StrokeStyle(
                    lineWidth: max(13 * viewport.scale, 5),
                    lineCap: .round
                )
            )
            context.stroke(
                branch,
                with: .color(color.opacity(0.96)),
                style: StrokeStyle(
                    lineWidth: max(3.2 * viewport.scale, 1.6),
                    lineCap: .round
                )
            )

            let cardWidth = max(138 * viewport.scale, 90)
            let cardHeight = max(40 * viewport.scale, 30)
            let cardCenterY = min(
                max(rect.midY, cardHeight / 2 + 12),
                max(Double(size.height) - cardHeight / 2 - 12, cardHeight / 2)
            )
            let cardRect = CGRect(
                x: centerX - cardWidth / 2,
                y: cardCenterY - cardHeight / 2,
                width: cardWidth,
                height: cardHeight
            )
            let card = Path(
                roundedRect: cardRect,
                cornerRadius: max(12 * viewport.scale, 8)
            )
            context.fill(card, with: .color(.white.opacity(0.96)))
            context.stroke(
                card,
                with: .color(color.opacity(0.9)),
                lineWidth: max(1.4 * viewport.scale, 1)
            )
            drawFittedText(
                bundle.branchName,
                in: CGRect(
                    x: cardRect.minX + 10 * viewport.scale,
                    y: cardRect.minY + 3 * viewport.scale,
                    width: cardRect.width - 20 * viewport.scale,
                    height: cardRect.height * 0.5
                ),
                font: .systemFont(
                    ofSize: max(11 * viewport.scale, 8),
                    weight: .bold
                ),
                color: NSColor.labelColor,
                context: &context
            )
            drawFittedText(
                "\(bundle.commitCount) 个提交 · \(bundleTimeRange(bundle))",
                in: CGRect(
                    x: cardRect.minX + 10 * viewport.scale,
                    y: cardRect.midY,
                    width: cardRect.width - 20 * viewport.scale,
                    height: cardRect.height * 0.42
                ),
                font: .systemFont(
                    ofSize: max(9 * viewport.scale, 7),
                    weight: .medium
                ),
                color: NSColor.secondaryLabelColor,
                context: &context
            )
        }
    }

    private func bundleTimeRange(
        _ bundle: CommitGraphBranchBundle
    ) -> String {
        let format = Date.FormatStyle(date: .numeric, time: .omitted)
        return "\(bundle.timeRange.lowerBound.formatted(format))–\(bundle.timeRange.upperBound.formatted(format))"
    }

    private func drawShallowBoundaryEndpoints(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        for visibleEndpoint in visibleScene.shallowBoundaryEndpoints {
            let endpoint = visibleEndpoint.endpoint
            let center = screenPoint(visibleEndpoint.position)
            let markerSize = max(8 * viewport.scale, 5)
            let marker = CGRect(
                x: center.x - markerSize / 2,
                y: center.y - markerSize / 2,
                width: markerSize,
                height: markerSize
            )
            guard isVisible(marker, in: size, padding: 80)
            else {
                continue
            }
            var diamond = Path()
            diamond.move(to: CGPoint(x: marker.midX, y: marker.minY))
            diamond.addLine(to: CGPoint(x: marker.maxX, y: marker.midY))
            diamond.addLine(to: CGPoint(x: marker.midX, y: marker.maxY))
            diamond.addLine(to: CGPoint(x: marker.minX, y: marker.midY))
            diamond.closeSubpath()
            context.fill(diamond, with: .color(GitMateTheme.warning.opacity(0.2)))
            context.stroke(
                diamond,
                with: .color(GitMateTheme.warning),
                lineWidth: max(1.4 * viewport.scale, 1)
            )
            if levelOfDetail != .overview {
                context.draw(
                    Text("浅克隆边界 · \(endpoint.missingParentHash)")
                        .font(
                            .system(
                                size: max(9 * viewport.scale, 6),
                                weight: .medium,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(GitMateTheme.warning),
                    at: CGPoint(
                        x: center.x,
                        y: center.y - 20 * viewport.scale
                    ),
                    anchor: .center
                )
            }
        }
    }

    private func drawAggregateCount(
        _ count: Int,
        path: CommitGraphGeneratedPath,
        color: Color,
        context: inout GraphicsContext
    ) {
        let center = screenPoint(
            CommitGraphPathGeometry.labelPoint(for: path)
        )
        let scale = CGFloat(viewport.scale)
        let width = CGFloat(34) * scale
        let height = CGFloat(20) * scale
        let originX = center.x - width / 2
        let originY = center.y - height / 2
        let rect = CGRect(
            x: originX,
            y: originY,
            width: width,
            height: height
        )
        context.fill(
            Path(roundedRect: rect, cornerRadius: rect.height / 2),
            with: .color(.white)
        )
        context.stroke(
            Path(roundedRect: rect, cornerRadius: rect.height / 2),
            with: .color(color),
            lineWidth: max(scale, 1)
        )
        context.draw(
            Text("×\(count)")
                .font(
                    .system(
                        size: max(9.5 * scale, 7),
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(color),
            at: center,
            anchor: .center
        )
    }

    private func drawVisibleNodes(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        for visibleNode in visibleScene.nodes {
            if levelOfDetail == .overview,
               hiddenBundleMemberHashes.contains(visibleNode.node.hash) {
                continue
            }
            let rect = screenRect(nodeRect(visibleNode.position))
            guard isVisible(rect, in: size) else { continue }
            drawNode(
                visibleNode.node,
                rect: rect,
                publicationState: visibleNode.publicationState,
                isSelected: selectedHashes.contains(visibleNode.node.hash)
                    || visibleNode.node.hash == selectedHash,
                isRelated: highlightedNodeHashes.contains(
                    visibleNode.node.hash
                ),
                context: &context
            )
        }
    }

    private func drawNode(
        _ node: CommitGraphNode,
        rect: CGRect,
        publicationState: CommitGraphPublicationState,
        isSelected: Bool,
        isRelated: Bool,
        context: inout GraphicsContext
    ) {
        let scale = CGFloat(viewport.scale)
        let branchColor = CommitGraphPalette.color(node.colorIndex)
        if levelOfDetail == .overview {
            let dot = CGRect(
                x: rect.midX - 5 * scale,
                y: rect.midY - 5 * scale,
                width: 10 * scale,
                height: 10 * scale
            )
            context.fill(
                Path(ellipseIn: dot),
                with: .color(
                    isSelected ? GitMateTheme.accent : branchColor
                )
            )
            return
        }
        let card = Path(
            roundedRect: rect,
            cornerRadius: max(11 * scale, 5)
        )
        context.fill(card, with: .color(.white))
        context.stroke(
            card,
            with: .color(
                isSelected
                    ? GitMateTheme.accent
                    : (isRelated ? branchColor : branchColor.opacity(0.88))
            ),
            style: StrokeStyle(
                lineWidth: max(
                    (isSelected ? 2.7 : (isRelated ? 2 : 1.35)) * scale,
                    1
                ),
                lineCap: .round,
                lineJoin: .round,
                dash: publicationState.isDashed
                    ? [7 * scale, 5 * scale]
                    : []
            )
        )

        var clipped = context
        clipped.clip(to: card)

        let avatarSize = levelOfDetail == .full ? 32 * scale : 22 * scale
        let avatarRect = CGRect(
            x: rect.minX + 11 * scale,
            y: rect.minY + 10 * scale,
            width: avatarSize,
            height: avatarSize
        )
        clipped.fill(
            Path(ellipseIn: avatarRect),
            with: .color(branchColor.opacity(0.14))
        )
        clipped.draw(
            Text(authorInitials(node.authorName))
                .font(.system(size: max(11 * scale, 7), weight: .bold))
                .foregroundStyle(branchColor),
            at: CGPoint(x: avatarRect.midX, y: avatarRect.midY),
            anchor: .center
        )

        let cloudWidth = publicationState.showsCloud ? 25 * scale : 0
        let subjectRect = CGRect(
            x: avatarRect.maxX + 10 * scale,
            y: rect.minY + 7 * scale,
            width: max(
                rect.maxX - avatarRect.maxX - 20 * scale - cloudWidth,
                1
            ),
            height: 25 * scale
        )
        drawFittedText(
            node.subject,
            in: subjectRect,
            font: .systemFont(
                ofSize: max(12.5 * scale, 7),
                weight: .semibold
            ),
            color: NSColor.labelColor,
            context: &clipped
        )
        if publicationState.showsCloud {
            var cloud = clipped.resolve(Image(systemName: "icloud.fill"))
            cloud.shading = .color(GitMateTheme.accent)
            clipped.draw(
                cloud,
                at: CGPoint(
                    x: rect.maxX - 13 * scale,
                    y: subjectRect.midY
                ),
                anchor: .center
            )
        }

        let decoration = levelOfDetail == .full
            ? node.decorations.first
            : nil
        let decorationWidth = decoration.map {
            min(
                max(
                    measuredWidth(
                        $0,
                        font: .systemFont(
                            ofSize: max(9.5 * scale, 6),
                            weight: .medium
                        )
                    ) + 12 * scale,
                    28 * scale
                ),
                88 * scale
            )
        } ?? 0
        if let decoration {
            drawDecoration(
                decoration,
                width: decorationWidth,
                color: branchColor,
                at: CGPoint(
                    x: rect.maxX - 9 * scale,
                    y: rect.maxY - 16 * scale
                ),
                context: &clipped,
                scale: scale
            )
        }

        let metadataY = rect.maxY - 16 * scale
        let hashWidth = measuredWidth(
            node.shortHash,
            font: .monospacedSystemFont(
                ofSize: max(10.5 * scale, 6),
                weight: .medium
            )
        )
        let hashX = rect.maxX
            - 10 * scale
            - decorationWidth
            - (decorationWidth > 0 ? 8 * scale : 0)
            - hashWidth
        let authorRect = CGRect(
            x: subjectRect.minX,
            y: metadataY - 9 * scale,
            width: max(hashX - subjectRect.minX - 10 * scale, 1),
            height: 18 * scale
        )
        if levelOfDetail == .full {
            drawFittedText(
                node.authorName,
                in: authorRect,
                font: .systemFont(
                    ofSize: max(10.5 * scale, 6),
                    weight: .medium
                ),
                color: NSColor.secondaryLabelColor,
                context: &clipped
            )
        }
        clipped.draw(
            Text(node.shortHash)
                .font(
                    .system(
                        size: max(10.5 * scale, 6),
                        weight: .medium,
                        design: .monospaced
                    )
                )
                .foregroundStyle(GitMateTheme.textSecondary),
            at: CGPoint(x: hashX, y: metadataY),
            anchor: .leading
        )
    }

    private func drawCollapsedGroups(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        for group in visibleScene.groups where group.isCollapsed {
            let rect = screenRect(group.rect)
            guard isVisible(rect, in: size) else { continue }
            let color = CommitGraphPalette.color(groupID: group.id)
            let card = Path(
                roundedRect: rect,
                cornerRadius: max(13 * viewport.scale, 6)
            )
            context.fill(card, with: .color(.white))
            context.stroke(
                card,
                with: .color(color),
                lineWidth: max(1.8 * viewport.scale, 1)
            )
            var clipped = context
            clipped.clip(to: card)
            let scale = CGFloat(viewport.scale)
            let iconRect = CGRect(
                x: rect.minX + 13 * scale,
                y: rect.minY + 14 * scale,
                width: 36 * scale,
                height: 36 * scale
            )
            clipped.fill(
                Path(
                    roundedRect: iconRect,
                    cornerRadius: 10 * scale
                ),
                with: .color(color.opacity(0.14))
            )
            clipped.draw(
                Image(systemName: "square.stack.3d.up.fill"),
                at: CGPoint(x: iconRect.midX, y: iconRect.midY),
                anchor: .center
            )
            guard levelOfDetail != .overview else { continue }
            let titleRect = CGRect(
                x: iconRect.maxX + 10 * scale,
                y: rect.minY + 11 * scale,
                width: max(
                    rect.maxX - iconRect.maxX - 22 * scale,
                    1
                ),
                height: 23 * scale
            )
            drawFittedText(
                group.title,
                in: titleRect,
                font: .systemFont(
                    ofSize: max(12.5 * scale, 7),
                    weight: .semibold
                ),
                color: NSColor.labelColor,
                context: &clipped
            )
            if levelOfDetail == .full {
                clipped.draw(
                Text("\(group.memberCount) 个提交 · 双击展开")
                    .font(
                        .system(
                            size: max(10 * scale, 6),
                            weight: .medium
                        )
                    )
                    .foregroundStyle(color),
                at: CGPoint(
                    x: titleRect.minX,
                    y: rect.maxY - 21 * scale
                ),
                anchor: .leading
            )
            }
        }
    }

    private func drawDecoration(
        _ decoration: String,
        width: CGFloat,
        color: Color,
        at trailingPoint: CGPoint,
        context: inout GraphicsContext,
        scale: CGFloat
    ) {
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
        let fitted = fittedText(
            decoration,
            font: .systemFont(
                ofSize: max(9.5 * scale, 6),
                weight: .medium
            ),
            maximumWidth: max(width - 10 * scale, 1)
        )
        context.draw(
            Text(fitted)
                .font(
                    .system(
                        size: max(9.5 * scale, 6),
                        weight: .medium
                    )
                )
                .foregroundStyle(color),
            at: CGPoint(x: rect.midX, y: rect.midY),
            anchor: .center
        )
    }

    private func drawFittedText(
        _ value: String,
        in rect: CGRect,
        font: NSFont,
        color: NSColor,
        context: inout GraphicsContext
    ) {
        let fitted = fittedText(
            value,
            font: font,
            maximumWidth: max(rect.width, 1)
        )
        context.draw(
            Text(fitted)
                .font(.init(font))
                .foregroundStyle(Color(nsColor: color)),
            at: CGPoint(x: rect.minX, y: rect.midY),
            anchor: .leading
        )
    }

    private func fittedText(
        _ value: String,
        font: NSFont,
        maximumWidth: CGFloat
    ) -> String {
        CommitGraphTextFitter.truncated(
            value,
            maximumWidth: Double(maximumWidth),
            measure: { measuredWidth($0, font: font) }
        )
    }

    private func measuredWidth(_ value: String, font: NSFont) -> Double {
        Double(
            ceil(
                NSAttributedString(
                    string: value,
                    attributes: [.font: font]
                ).size().width
            )
        )
    }

    private func nodeRect(_ center: GraphPoint) -> GraphRect {
        GraphRect(
            x: center.x - CommitGraphViewportProjector.nodeWidth / 2,
            y: center.y - CommitGraphViewportProjector.nodeHeight / 2,
            width: CommitGraphViewportProjector.nodeWidth,
            height: CommitGraphViewportProjector.nodeHeight
        )
    }

    private func screenPoint(_ point: GraphPoint) -> CGPoint {
        let result = CommitGraphViewportProjector.screenPoint(
            canvasPoint: point,
            viewport: viewport
        )
        return CGPoint(x: result.x, y: result.y)
    }

    private func screenRect(_ rect: GraphRect) -> CGRect {
        let origin = screenPoint(
            GraphPoint(x: rect.x, y: rect.y)
        )
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: rect.width * viewport.scale,
            height: rect.height * viewport.scale
        )
    }

    private func isVisible(
        _ rect: CGRect,
        in size: CGSize,
        padding: CGFloat = 180
    ) -> Bool {
        rect.intersects(
            CGRect(origin: .zero, size: size).insetBy(
                dx: -padding,
                dy: -padding
            )
        )
    }

    private func authorInitials(_ author: String) -> String {
        let initials = author
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        return initials.isEmpty ? "?" : String(initials).uppercased()
    }
}
