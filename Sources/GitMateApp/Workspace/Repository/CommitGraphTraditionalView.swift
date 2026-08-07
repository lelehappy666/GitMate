import AppKit
import GitMateCore
import SwiftUI

struct CommitGraphTraditionalView: View {
    let layout: CommitGraphTraditionalLayoutResult
    let groupBadgeByHash: [String: CommitGraphTraditionalGroupBadge]
    let groupRevision: UInt64
    let selectedHash: String?
    let focusedHash: String?
    let currentUserLogin: String?
    let currentUserAvatarURL: URL?
    let select: (String) -> Void
    let consumeFocus: (String) -> Void

    @State private var verticalOffset = 0.0
    @State private var laneHorizontalOffset = 0.0

    var body: some View {
        GeometryReader { geometry in
            let width = Double(geometry.size.width)
            let height = Double(geometry.size.height)
            let laneWidth = CommitGraphTraditionalMetrics
                .laneViewportWidth(width)
            let visibleRows = CommitGraphTraditionalViewport.visibleRows(
                totalCount: layout.contentRowCount,
                rowHeight: CommitGraphTraditionalMetrics.rowHeight,
                verticalOffset: verticalOffset,
                viewportHeight: height,
                preloadScreens: 1.5
            )

            ZStack(alignment: .topLeading) {
                CommitGraphTraditionalCanvas(
                    layout: layout,
                    groupByHash: groupBadgeByHash,
                    groupRevision: groupRevision,
                    visibleRows: visibleRows,
                    verticalOffset: verticalOffset,
                    laneHorizontalOffset: laneHorizontalOffset,
                    selectedHash: selectedHash
                )

                avatarLayer(
                    visibleRows: visibleRows,
                    laneWidth: laneWidth
                )

                TraditionalInteractionSurface(
                    rowCount: layout.rows.count,
                    rowHeight: CommitGraphTraditionalMetrics.rowHeight,
                    verticalOffset: verticalOffset,
                    laneViewportWidth: laneWidth,
                    scroll: { verticalDelta, horizontalDelta in
                        verticalOffset = clampedVerticalOffset(
                            verticalOffset - verticalDelta,
                            viewportHeight: height
                        )
                        if horizontalDelta != 0 {
                            laneHorizontalOffset = clampedLaneOffset(
                                laneHorizontalOffset - horizontalDelta,
                                laneViewportWidth: laneWidth
                            )
                        }
                    },
                    selectRow: { row in
                        guard layout.rows.indices.contains(row) else { return }
                        select(layout.rows[row].commit.fullHash)
                    }
                )
                .accessibilityHidden(true)
                .accessibilityIdentifier("workspace.commitGraph.traditional")

                accessibilityRows(
                    visibleRows: visibleRows,
                    width: width
                )
            }
            .onAppear {
                clampOffsets(width: width, height: height)
                applyFocusIfNeeded(viewportHeight: height)
            }
            .onChange(of: geometry.size) { _, newSize in
                clampOffsets(
                    width: Double(newSize.width),
                    height: Double(newSize.height)
                )
            }
            .onChange(of: layout.contentRowCount) { _, _ in
                clampOffsets(width: width, height: height)
                applyFocusIfNeeded(viewportHeight: height)
            }
            .onChange(of: focusedHash) { _, _ in
                applyFocusIfNeeded(viewportHeight: height)
            }
        }
        .background(.white)
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
                GitMateAvatar(
                    url: avatarURL(for: commit),
                    size: CommitGraphTraditionalMetrics.avatarSize
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

    private func avatarURL(for commit: GitCommit) -> URL? {
        if let login = githubLogin(from: commit.authorEmail) {
            return URL(string: "https://github.com/\(login).png?size=96")
        }
        if let currentUserLogin,
           commit.authorName.compare(
                currentUserLogin,
                options: [.caseInsensitive, .diacriticInsensitive]
           ) == .orderedSame {
            return currentUserAvatarURL
        }
        return nil
    }

    private func githubLogin(from email: String) -> String? {
        let normalized = email.lowercased()
        guard normalized.hasSuffix("@users.noreply.github.com") else {
            return nil
        }
        let local = String(normalized.split(separator: "@", maxSplits: 1)[0])
        let candidate = local.split(separator: "+", maxSplits: 1).last.map(String.init)
            ?? local
        guard !candidate.isEmpty,
              candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
        else {
            return nil
        }
        return candidate
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
        laneHorizontalOffset = clampedLaneOffset(
            laneHorizontalOffset,
            laneViewportWidth: CommitGraphTraditionalMetrics
                .laneViewportWidth(width)
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

    private func clampedLaneOffset(
        _ value: Double,
        laneViewportWidth: Double
    ) -> Double {
        let maximum = max(
            CommitGraphTraditionalMetrics.laneContentWidth(
                maximumLane: layout.maximumLane
            ) - laneViewportWidth + 20,
            0
        )
        return min(max(value.isFinite ? value : 0, 0), maximum)
    }
}

private struct TraditionalInteractionSurface: NSViewRepresentable {
    let rowCount: Int
    let rowHeight: Double
    let verticalOffset: Double
    let laneViewportWidth: Double
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
        view.laneViewportWidth = laneViewportWidth
        return view
    }

    func updateNSView(_ view: InteractionView, context: Context) {
        context.coordinator.scroll = scroll
        context.coordinator.selectRow = selectRow
        view.rowCount = rowCount
        view.rowHeight = rowHeight
        view.verticalOffset = verticalOffset
        view.laneViewportWidth = laneViewportWidth
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
        var laneViewportWidth = 220.0

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
            let horizontal = point.x <= laneViewportWidth
                ? Double(event.scrollingDeltaX) * horizontalScale
                : 0
            coordinator?.scroll(
                Double(event.scrollingDeltaY) * verticalScale,
                horizontal
            )
        }

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            guard rowHeight > 0 else { return }
            let row = Int(floor((Double(point.y) + verticalOffset) / rowHeight))
            guard row >= 0, row < rowCount else { return }
            coordinator?.selectRow(row)
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}
