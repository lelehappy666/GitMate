import AppKit
import GitMateCore
import SwiftUI

struct CommitGraphTraditionalView: View {
    let layout: CommitGraphTraditionalLayoutResult
    let branchCatalog: CommitGraphBranchCatalog
    let branchProjection: CommitGraphTraditionalBranchProjection
    let publicationIndex: CommitGraphTraditionalPublicationIndex
    let pinnedBranchIDs: Set<String>
    let groupBadgeByHash: [String: CommitGraphTraditionalGroupBadge]
    let groupRevision: UInt64
    let selectedHash: String?
    let focusedHash: String?
    let localStatus: LocalRepositoryStatus?
    let storedDividerWidth: Double?
    let currentUserLogin: String?
    let currentUserName: String?
    let currentUserAvatarURL: URL?
    let select: (String) -> Void
    let setViewportWidth: (Double) -> Void
    let commitDividerWidth: (Double) -> Void
    let selectBranch: (String) -> Void
    let togglePinnedBranch: (String) -> Void
    let consumeFocus: (String) -> Void

    @State private var verticalOffset = 0.0
    @State private var laneHorizontalOffset = 0.0
    @State private var dividerWidth = 0.0
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
                let splitWidth = resolvedDividerWidth(viewportWidth: width)
                let laneContentWidth = CommitGraphTraditionalLaneGeometry
                    .contentWidth(
                        maximumLane: max(branchProjection.slots.count - 1, 0)
                    ) + 12
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
                    CommitGraphTraditionalCanvas(
                        layout: layout,
                        branchCatalog: branchCatalog,
                        branchProjection: branchProjection,
                        publicationIndex: publicationIndex,
                        groupByHash: groupBadgeByHash,
                        groupRevision: groupRevision,
                        visibleRows: canvasVisibleRows,
                        verticalOffset: verticalOffset,
                        laneViewportWidth: splitWidth,
                        laneHorizontalOffset: laneHorizontalOffset,
                        selectedHash: selectedHash
                    )
                    .frame(width: width, height: height)

                    avatarLayer(
                        visibleRows: overlayVisibleRows,
                        dividerWidth: splitWidth
                    )

                    accessibilityRows(
                        visibleRows: overlayVisibleRows,
                        width: width
                    )

                    TraditionalInteractionSurface(
                        rowCount: layout.rows.count,
                        rowHeight: CommitGraphTraditionalMetrics.rowHeight,
                        verticalOffset: verticalOffset,
                        dividerWidth: splitWidth,
                        scroll: { verticalDelta, horizontalDelta in
                            verticalOffset = clampedVerticalOffset(
                                verticalOffset - verticalDelta,
                                viewportHeight: height
                            )
                            laneHorizontalOffset =
                                CommitGraphTraditionalSplitLayout
                                .clampedLaneOffset(
                                    laneHorizontalOffset - horizontalDelta,
                                    laneContentWidth: laneContentWidth,
                                    dividerWidth: splitWidth
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

                    CommitGraphTraditionalDividerHandle(
                        currentWidth: splitWidth,
                        viewportWidth: width,
                        onChange: { proposed in
                            dividerWidth = CommitGraphTraditionalSplitLayout
                                .clampedDividerWidth(
                                    proposed,
                                    viewportWidth: width
                                )
                            laneHorizontalOffset =
                                CommitGraphTraditionalSplitLayout
                                .clampedLaneOffset(
                                    laneHorizontalOffset,
                                    laneContentWidth: laneContentWidth,
                                    dividerWidth: dividerWidth
                                )
                        },
                        onCommit: { proposed in
                            let finalWidth = CommitGraphTraditionalSplitLayout
                                .clampedDividerWidth(
                                    proposed,
                                    viewportWidth: width
                                )
                            dividerWidth = finalWidth
                            commitDividerWidth(finalWidth)
                        }
                    )
                    .frame(width: 10, height: height)
                    .offset(x: splitWidth - 5)
                    .accessibilityLabel("调整分支图宽度")
                    .accessibilityIdentifier(
                        "workspace.commitGraph.traditional.divider"
                    )
                }
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: .topLeading
                )
                .clipped()
                .onAppear {
                    setViewportWidth(width)
                    dividerWidth = CommitGraphTraditionalSplitLayout
                        .clampedDividerWidth(
                            storedDividerWidth,
                            viewportWidth: width
                        )
                    clampOffsets(
                        viewportWidth: width,
                        viewportHeight: height
                    )
                    applyFocusIfNeeded(viewportHeight: height)
                }
                .onChange(of: geometry.size) { _, newSize in
                    let newWidth = Double(newSize.width)
                    setViewportWidth(newWidth)
                    dividerWidth = CommitGraphTraditionalSplitLayout
                        .clampedDividerWidth(
                            dividerWidth > 0 ? dividerWidth : storedDividerWidth,
                            viewportWidth: newWidth
                        )
                    clampOffsets(
                        viewportWidth: newWidth,
                        viewportHeight: Double(newSize.height)
                    )
                }
                .onChange(of: storedDividerWidth) { _, newWidth in
                    dividerWidth = CommitGraphTraditionalSplitLayout
                        .clampedDividerWidth(
                            newWidth,
                            viewportWidth: width
                        )
                    clampLaneOffset(dividerWidth: dividerWidth)
                }
                .onChange(of: layout.contentRowCount) { _, _ in
                    clampOffsets(
                        viewportWidth: width,
                        viewportHeight: height
                    )
                    applyFocusIfNeeded(viewportHeight: height)
                }
                .onChange(of: branchProjection.slots.count) { _, _ in
                    laneHorizontalOffset = 0
                    clampLaneOffset(dividerWidth: splitWidth)
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
                "\(branchProjection.slots.count) 条逻辑分支 · \(branchCatalog.branches.count) 个引用",
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
        Button {
            if let branchID = slot.branchID {
                selectBranch(branchID)
            }
        } label: {
            let color = CommitGraphPalette.color(slot.lane)
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(slot.title)
                    .lineLimit(1)
                if slot.referenceTitles.count > 1 {
                    Text("+\(slot.referenceTitles.count - 1)")
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
                if slot.branchIDs.allSatisfy({ $0.hasPrefix("remote:") }) {
                    Image(systemName: "icloud")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(GitMateTheme.textSecondary)
                }
            }
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(GitMateTheme.textPrimary)
            .padding(.horizontal, 9)
            .frame(height: 27)
            .background(.white)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(color.opacity(0.34), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(slot.referenceTitles.joined(separator: " · "))
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
                Text("工作区未提交 · 共 \(summary.totalCount) 项")
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
        dividerWidth: Double
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
                    x: CommitGraphTraditionalContentViewport
                        .informationOriginX(dividerWidth: dividerWidth)
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

    private func resolvedDividerWidth(
        viewportWidth: Double
    ) -> Double {
        CommitGraphTraditionalSplitLayout.clampedDividerWidth(
            dividerWidth > 0 ? dividerWidth : storedDividerWidth,
            viewportWidth: viewportWidth
        )
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

    private func clampOffsets(
        viewportWidth: Double,
        viewportHeight: Double
    ) {
        verticalOffset = clampedVerticalOffset(
            verticalOffset,
            viewportHeight: viewportHeight
        )
        let splitWidth = resolvedDividerWidth(viewportWidth: viewportWidth)
        laneHorizontalOffset = CommitGraphTraditionalSplitLayout
            .clampedLaneOffset(
                laneHorizontalOffset,
                laneContentWidth: laneContentWidth,
                dividerWidth: splitWidth
            )
    }

    private func clampLaneOffset(dividerWidth: Double) {
        laneHorizontalOffset = CommitGraphTraditionalSplitLayout
            .clampedLaneOffset(
                laneHorizontalOffset,
                laneContentWidth: laneContentWidth,
                dividerWidth: dividerWidth
            )
    }

    private var laneContentWidth: Double {
        CommitGraphTraditionalLaneGeometry.contentWidth(
            maximumLane: max(branchProjection.slots.count - 1, 0)
        ) + 12
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
    let dividerWidth: Double
    let scroll: (Double, Double) -> Void
    let selectRow: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(scroll: scroll, selectRow: selectRow)
    }

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.coordinator = context.coordinator
        update(view)
        return view
    }

    func updateNSView(_ view: InteractionView, context: Context) {
        context.coordinator.scroll = scroll
        context.coordinator.selectRow = selectRow
        update(view)
    }

    private func update(_ view: InteractionView) {
        view.rowCount = rowCount
        view.rowHeight = rowHeight
        view.verticalOffset = verticalOffset
        view.dividerWidth = dividerWidth
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
        var dividerWidth = 0.0
        private var mouseDownRow: Int?

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            let verticalScale: Double = event.hasPreciseScrollingDeltas
                ? 1
                : rowHeight * 3
            let horizontalScale: Double = event.hasPreciseScrollingDeltas
                ? 1
                : 48
            let shiftScroll = event.modifierFlags.contains(.shift)
            let isInsideLaneViewport = Double(point.x) <= dividerWidth
            let horizontal = isInsideLaneViewport
                ? Double(
                    shiftScroll
                        ? event.scrollingDeltaY
                        : event.scrollingDeltaX
                ) * horizontalScale
                : 0
            coordinator?.scroll(
                shiftScroll
                    ? 0
                    : Double(event.scrollingDeltaY) * verticalScale,
                horizontal
            )
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownRow = row(
                at: convert(event.locationInWindow, from: nil)
            )
        }

        override func mouseUp(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if let mouseDownRow,
               row(at: point) == mouseDownRow {
                coordinator?.selectRow(mouseDownRow)
            }
            mouseDownRow = nil
        }

        private func row(at point: NSPoint) -> Int? {
            guard rowHeight.isFinite, rowHeight > 0 else { return nil }
            let row = Int(
                floor((Double(point.y) + verticalOffset) / rowHeight)
            )
            return row >= 0 && row < rowCount ? row : nil
        }
    }
}
