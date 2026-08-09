import AppKit
import GitMateCore
import SwiftUI

struct CommitGraphTraditionalView: View {
    let layout: CommitGraphTraditionalLayoutResult
    let branchCatalog: CommitGraphBranchCatalog
    let branchProjection: CommitGraphTraditionalBranchProjection
    let pinnedBranchIDs: Set<String>
    let groupBadgeByHash: [String: CommitGraphTraditionalGroupBadge]
    let groupRevision: UInt64
    let selectedHash: String?
    let focusedHash: String?
    let localStatus: LocalRepositoryStatus?
    let currentUserLogin: String?
    let currentUserName: String?
    let currentUserAvatarURL: URL?
    let select: (String) -> Void
    let setViewportWidth: (Double) -> Void
    let selectBranch: (String) -> Void
    let togglePinnedBranch: (String) -> Void
    let consumeFocus: (String) -> Void

    @State private var verticalOffset = 0.0
    @State private var horizontalOffset = 0.0
    @State private var showsBranchPicker = false

    var body: some View {
        VStack(spacing: 0) {
            if let localStatus {
                let summary = CommitGraphWorkingTreeSummary(status: localStatus)
                if summary.hasChanges {
                    workingTreeRow(summary)
                    Divider()
                }
            }
            branchContextBar
            Divider()
            GeometryReader { geometry in
                let width = Double(geometry.size.width)
                let height = Double(geometry.size.height)
                let maximumLane = max(branchProjection.slots.count - 1, 0)
                let contentWidth = CommitGraphTraditionalContentViewport
                    .contentWidth(
                        viewportWidth: width,
                        maximumLane: maximumLane
                    )
                let laneWidth = CommitGraphTraditionalMetrics
                    .laneViewportWidth(
                        contentWidth,
                        maximumLane: maximumLane
                    )
                let canvasVisibleRows = CommitGraphTraditionalViewport
                    .visibleRows(
                        totalCount: layout.contentRowCount,
                        rowHeight: CommitGraphTraditionalMetrics.rowHeight,
                        verticalOffset: verticalOffset,
                        viewportHeight: height,
                        preloadScreens: 1.5
                    )
                let overlayVisibleRows = CommitGraphTraditionalContentViewport
                    .overlayRows(
                        totalCount: layout.contentRowCount,
                        rowHeight: CommitGraphTraditionalMetrics.rowHeight,
                        verticalOffset: verticalOffset,
                        viewportHeight: height
                    )

                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        CommitGraphTraditionalCanvas(
                            layout: layout,
                            branchCatalog: branchCatalog,
                            branchProjection: branchProjection,
                            groupByHash: groupBadgeByHash,
                            groupRevision: groupRevision,
                            visibleRows: canvasVisibleRows,
                            verticalOffset: verticalOffset,
                            selectedHash: selectedHash
                        )
                        .frame(width: contentWidth, height: height)

                        avatarLayer(
                            visibleRows: overlayVisibleRows,
                            laneWidth: laneWidth
                        )

                        accessibilityRows(
                            visibleRows: overlayVisibleRows,
                            width: contentWidth
                        )
                    }
                    .frame(
                        width: contentWidth,
                        height: height,
                        alignment: .topLeading
                    )
                    .offset(x: -horizontalOffset)

                    TraditionalInteractionSurface(
                        rowCount: layout.rows.count,
                        rowHeight: CommitGraphTraditionalMetrics.rowHeight,
                        verticalOffset: verticalOffset,
                        scroll: { verticalDelta, horizontalDelta in
                            verticalOffset = clampedVerticalOffset(
                                verticalOffset - verticalDelta,
                                viewportHeight: height
                            )
                            horizontalOffset = CommitGraphTraditionalContentViewport
                                .clampedHorizontalOffset(
                                    horizontalOffset - horizontalDelta,
                                    contentWidth: contentWidth,
                                    viewportWidth: width
                                )
                        },
                        selectRow: { row in
                            guard layout.rows.indices.contains(row) else { return }
                            select(layout.rows[row].commit.fullHash)
                        }
                    )
                    .frame(width: width, height: height)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("workspace.commitGraph.traditional")
                }
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: .topLeading
                )
                .clipped()
                .onAppear {
                    setViewportWidth(width)
                    clampOffsets(width: width, height: height)
                    applyFocusIfNeeded(viewportHeight: height)
                }
                .onChange(of: geometry.size) { _, newSize in
                    setViewportWidth(Double(newSize.width))
                    clampOffsets(
                        width: Double(newSize.width),
                        height: Double(newSize.height)
                    )
                }
                .onChange(of: layout.contentRowCount) { _, _ in
                    clampOffsets(width: width, height: height)
                    applyFocusIfNeeded(viewportHeight: height)
                }
                .onChange(of: branchProjection.slots.count) { _, _ in
                    clampOffsets(width: width, height: height)
                }
                .onChange(of: focusedHash) { _, _ in
                    applyFocusIfNeeded(viewportHeight: height)
                }
            }
        }
        .background(.white)
        .clipped()
    }

    private var branchContextBar: some View {
        HStack(spacing: 10) {
            Text("Git 提交历史")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(GitMateTheme.textPrimary)
            Divider().frame(height: 20)
            Label(
                "\(branchProjection.slots.count) / \(branchCatalog.branches.count) 分支",
                systemImage: "arrow.triangle.branch"
            )
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(GitMateTheme.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(branchProjection.slots) { slot in
                        branchSlot(slot)
                    }
                }
            }

            Button {
                showsBranchPicker = true
            } label: {
                Label("查找分支", systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .popover(isPresented: $showsBranchPicker, arrowEdge: .bottom) {
                CommitGraphBranchPicker(
                    catalog: branchCatalog,
                    projection: branchProjection,
                    pinnedBranchIDs: pinnedBranchIDs,
                    selectBranch: selectBranch,
                    togglePinned: togglePinnedBranch
                )
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(GitMateTheme.panel.opacity(0.34))
    }

    private func branchSlot(
        _ slot: CommitGraphTraditionalBranchSlot
    ) -> some View {
        Group {
            if let branchID = slot.branchID {
                Button {
                    selectBranch(branchID)
                } label: {
                    branchSlotLabel(slot)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showsBranchPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "ellipsis")
                        if slot.hiddenLocalCount > 0 {
                            Text("本地 +\(slot.hiddenLocalCount)")
                        }
                        if slot.hiddenRemoteCount > 0 {
                            Text("远程 +\(slot.hiddenRemoteCount)")
                        }
                    }
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(GitMateTheme.textSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 27)
                    .background(.white)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().stroke(GitMateTheme.border, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func branchSlotLabel(
        _ slot: CommitGraphTraditionalBranchSlot
    ) -> some View {
        let color = CommitGraphPalette.color(slot.lane)
        return HStack(spacing: 5) {
            Circle()
                .fill(slot.source == .remote ? .white : color)
                .overlay {
                    Circle().stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: 1.4,
                            dash: slot.source == .remote ? [2, 2] : []
                        )
                    )
                }
                .frame(width: 7, height: 7)
            Text(slot.title)
                .lineLimit(1)
        }
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(GitMateTheme.textPrimary)
        .padding(.horizontal, 9)
        .frame(height: 27)
        .background(.white)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(
                color.opacity(slot.source == .remote ? 0.8 : 0.3),
                style: StrokeStyle(
                    lineWidth: 1,
                    dash: slot.source == .remote ? [4, 3] : []
                )
            )
        }
    }

    private func workingTreeRow(
        _ summary: CommitGraphWorkingTreeSummary
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(GitMateTheme.warning.opacity(0.13))
                Image(systemName: "pencil.and.list.clipboard")
                    .foregroundStyle(GitMateTheme.warning)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("工作区变更")
                        .font(.system(size: 13, weight: .bold))
                    Text(summary.branch ?? "Detached HEAD")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(GitMateTheme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(GitMateTheme.accent.opacity(0.09))
                        .clipShape(Capsule())
                }
                Text("本地未提交 · 共 \(summary.totalCount) 项")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }

            Spacer(minLength: 12)
            worktreeCount("暂存", summary.stagedCount, color: GitMateTheme.accent)
            worktreeCount("修改", summary.unstagedCount, color: GitMateTheme.warning)
            worktreeCount("未跟踪", summary.untrackedCount, color: .secondary)
            if summary.conflictCount > 0 {
                worktreeCount("冲突", summary.conflictCount, color: .red)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(GitMateTheme.warning.opacity(0.035))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("工作区有 \(summary.totalCount) 项未提交变更")
    }

    private func worktreeCount(
        _ title: String,
        _ count: Int,
        color: Color
    ) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(count > 0 ? color : GitMateTheme.textSecondary)
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .frame(minWidth: 38)
    }

    private func accessibilityRows(
        visibleRows: Range<Int>,
        width: Double
    ) -> some View {
        ForEach(Array(visibleRows), id: \.self) { rowIndex in
            if layout.rows.indices.contains(rowIndex) {
                let row = layout.rows[rowIndex]
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: width,
                        height: CommitGraphTraditionalMetrics.rowHeight
                    )
                    .position(
                        x: width / 2,
                        y: Double(rowIndex)
                            * CommitGraphTraditionalMetrics.rowHeight
                            + CommitGraphTraditionalMetrics.rowHeight / 2
                            - verticalOffset
                    )
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(row.commit.subject)，作者 \(row.commit.authorName)，提交 \(row.commit.shortHash)"
                    )
                    .accessibilityHint("打开提交详情")
                    .accessibilityAddTraits(
                        row.commit.fullHash == selectedHash
                            ? [.isButton, .isSelected]
                            : .isButton
                    )
                    .accessibilityAction {
                        select(row.commit.fullHash)
                    }
                    .accessibilityIdentifier(
                        "workspace.commitGraph.traditional.row.\(row.commit.fullHash)"
                    )
            }
        }
    }

    private func avatarLayer(
        visibleRows: Range<Int>,
        laneWidth: Double
    ) -> some View {
        ForEach(Array(visibleRows), id: \.self) { rowIndex in
            if layout.rows.indices.contains(rowIndex) {
                let commit = layout.rows[rowIndex].commit
                let identity = CommitGraphAuthorAvatarIdentity.resolve(
                    authorName: commit.authorName,
                    authorEmail: commit.authorEmail,
                    currentUserLogin: currentUserLogin,
                    currentUserName: currentUserName,
                    currentUserAvatarURL: currentUserAvatarURL
                )
                GitMateAvatar(
                    url: identity.remoteURL,
                    size: CommitGraphTraditionalMetrics.avatarSize,
                    fallbackText: identity.fallbackInitials,
                    fallbackColorIndex: identity.fallbackColorIndex
                )
                .position(
                    x: laneWidth + 18
                        + CommitGraphTraditionalMetrics.avatarSize / 2,
                    y: Double(rowIndex)
                        * CommitGraphTraditionalMetrics.rowHeight
                        + CommitGraphTraditionalMetrics.rowHeight / 2
                        - verticalOffset
                )
                .allowsHitTesting(false)
            }
        }
    }

    private func applyFocusIfNeeded(viewportHeight: Double) {
        guard let focusedHash,
              let row = layout.row(hash: focusedHash)
        else { return }
        let desired = Double(row.row)
            * CommitGraphTraditionalMetrics.rowHeight
            + CommitGraphTraditionalMetrics.rowHeight / 2
            - viewportHeight / 2
        verticalOffset = clampedVerticalOffset(
            desired,
            viewportHeight: viewportHeight
        )
        consumeFocus(focusedHash)
    }

    private func clampOffsets(width: Double, height: Double) {
        verticalOffset = clampedVerticalOffset(
            verticalOffset,
            viewportHeight: height
        )
        let contentWidth = CommitGraphTraditionalContentViewport.contentWidth(
            viewportWidth: width,
            maximumLane: max(branchProjection.slots.count - 1, 0)
        )
        horizontalOffset = CommitGraphTraditionalContentViewport
            .clampedHorizontalOffset(
                horizontalOffset,
                contentWidth: contentWidth,
                viewportWidth: width
            )
    }

    private func clampedVerticalOffset(
        _ value: Double,
        viewportHeight: Double
    ) -> Double {
        let maximum = max(
            Double(layout.contentRowCount)
                * CommitGraphTraditionalMetrics.rowHeight - viewportHeight,
            0
        )
        return min(max(value.isFinite ? value : 0, 0), maximum)
    }

}

private struct TraditionalInteractionSurface: NSViewRepresentable {
    let rowCount: Int
    let rowHeight: Double
    let verticalOffset: Double
    let scroll: (Double, Double) -> Void
    let selectRow: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(scroll: scroll, selectRow: selectRow)
    }

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.coordinator = context.coordinator
        view.rowCount = rowCount
        view.rowHeight = rowHeight
        view.verticalOffset = verticalOffset
        return view
    }

    func updateNSView(_ view: InteractionView, context: Context) {
        context.coordinator.scroll = scroll
        context.coordinator.selectRow = selectRow
        view.rowCount = rowCount
        view.rowHeight = rowHeight
        view.verticalOffset = verticalOffset
    }

    @MainActor
    final class Coordinator {
        var scroll: (Double, Double) -> Void
        var selectRow: (Int) -> Void

        init(
            scroll: @escaping (Double, Double) -> Void,
            selectRow: @escaping (Int) -> Void
        ) {
            self.scroll = scroll
            self.selectRow = selectRow
        }
    }

    @MainActor
    final class InteractionView: NSView {
        weak var coordinator: Coordinator?
        var rowCount = 0
        var rowHeight = CommitGraphTraditionalMetrics.rowHeight
        var verticalOffset = 0.0
        private var mouseDownPoint: NSPoint?
        private var lastDragPoint: NSPoint?
        private var mouseDownRow: Int?
        private var isHorizontalDragging = false

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            let verticalScale: Double = event.hasPreciseScrollingDeltas
                ? 1
                : rowHeight * 3
            let horizontalScale: Double = event.hasPreciseScrollingDeltas
                ? 1
                : 48
            let shiftScroll = event.modifierFlags.contains(.shift)
            let horizontal = Double(
                shiftScroll
                    ? event.scrollingDeltaY
                    : event.scrollingDeltaX
            ) * horizontalScale
            coordinator?.scroll(
                shiftScroll
                    ? 0
                    : Double(event.scrollingDeltaY) * verticalScale,
                horizontal
            )
        }

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            mouseDownPoint = point
            lastDragPoint = point
            isHorizontalDragging = false
            mouseDownRow = row(at: point)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let mouseDownPoint,
                  let lastDragPoint
            else {
                return
            }
            let point = convert(event.locationInWindow, from: nil)
            if !isHorizontalDragging {
                isHorizontalDragging = CommitGraphTraditionalHorizontalDrag
                    .isDragging(
                        horizontalDistance: Double(point.x - mouseDownPoint.x)
                    )
            }
            if isHorizontalDragging {
                coordinator?.scroll(0, Double(point.x - lastDragPoint.x))
                NSCursor.closedHand.set()
            }
            self.lastDragPoint = point
        }

        override func mouseUp(with event: NSEvent) {
            if !isHorizontalDragging,
               let mouseDownRow {
                coordinator?.selectRow(mouseDownRow)
            }
            mouseDownPoint = nil
            lastDragPoint = nil
            mouseDownRow = nil
            isHorizontalDragging = false
            window?.invalidateCursorRects(for: self)
        }

        private func row(at point: NSPoint) -> Int? {
            guard rowHeight.isFinite, rowHeight > 0 else { return nil }
            let row = Int(
                floor((Double(point.y) + verticalOffset) / rowHeight)
            )
            return row >= 0 && row < rowCount ? row : nil
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}
