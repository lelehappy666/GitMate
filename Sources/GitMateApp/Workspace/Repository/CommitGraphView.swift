import GitMateCore
import SwiftUI

struct CommitGraphView: View {
    @Bindable var viewModel: CommitGraphViewModel

    @State private var previousDrag = CGSize.zero
    @State private var previousMagnification: CGFloat = 1
    @State private var pointerAnchor = GraphPoint.zero

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let message = viewModel.errorMessage {
                errorBanner(message)
            }
            graphCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: detailPresented) {
            if let detail = viewModel.selectedCommit {
                CommitDetailSheet(
                    detail: detail,
                    diff: viewModel.selectedDiff,
                    isDiffTruncated: viewModel.isSelectedDiffTruncated,
                    dismiss: viewModel.dismissDetail
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("提交历史与提交图")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(GitMateTheme.textPrimary)
                Text("在无限画布中查看分支、合并和提交详情")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(GitMateTheme.textSecondary)
            }

            Spacer()

            graphToolbar
        }
        .padding(.horizontal, 24)
        .frame(height: 78)
        .background(.white)
    }

    private var graphToolbar: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.resetLayout()
            } label: {
                Label("自动布局", systemImage: "wand.and.stars")
            }

            Button {
                viewModel.focusCurrentBranch()
            } label: {
                Label("聚焦主分支", systemImage: "scope")
            }
            .accessibilityIdentifier("workspace.commitGraph.focus")

            Divider()
                .frame(height: 22)

            Button {
                viewModel.zoom(
                    by: 0.8,
                    anchor: GraphPoint(x: 520, y: 340)
                )
            } label: {
                Image(systemName: "minus")
            }
            .accessibilityLabel("缩小提交图")

            Text("\(Int(viewModel.viewport.scale * 100))%")
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(GitMateTheme.textPrimary)
                .frame(width: 50)

            Button {
                viewModel.zoom(
                    by: 1.25,
                    anchor: GraphPoint(x: 520, y: 340)
                )
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("放大提交图")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.commitGraph.zoom")
    }

    private var graphCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    drawGrid(context: &context, size: size)
                    drawEdges(context: &context)
                }
                .background(.white)

                ForEach(viewModel.layout.nodes) { node in
                    CommitGraphNodeView(
                        node: node,
                        isSelected: viewModel.selectedHash == node.hash
                    ) {
                        Task {
                            await viewModel.select(hash: node.hash)
                        }
                    }
                    .scaleEffect(viewModel.viewport.scale)
                    .position(
                        x: node.x * viewModel.viewport.scale
                            + viewModel.viewport.offsetX,
                        y: node.y * viewModel.viewport.scale
                            + viewModel.viewport.offsetY
                    )
                }

                if viewModel.isLoading && viewModel.layout.nodes.isEmpty {
                    loadingState
                } else if !viewModel.isLoading
                    && viewModel.layout.nodes.isEmpty {
                    emptyState
                }

                VStack {
                    HStack {
                        branchLegend
                        Spacer()
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        if viewModel.isLoadingMore {
                            Label("正在加载更早提交", systemImage: "clock.arrow.circlepath")
                                .font(.system(size: 11.5, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.white)
                                .clipShape(Capsule())
                                .overlay {
                                    Capsule().stroke(
                                        GitMateTheme.border,
                                        lineWidth: 1
                                    )
                                }
                        }
                        Spacer()
                        minimap
                    }
                }
                .padding(14)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(magnificationGesture)
            .onContinuousHover { phase in
                if case let .active(location) = phase {
                    pointerAnchor = GraphPoint(
                        x: location.x,
                        y: location.y
                    )
                }
            }
            .onChange(of: geometry.size) { _, size in
                if pointerAnchor == .zero {
                    pointerAnchor = GraphPoint(
                        x: size.width / 2,
                        y: size.height / 2
                    )
                }
            }
            .accessibilityLabel("无限画布提交图")
            .accessibilityHint("拖拽平移，悬停后捏合或滚动缩放")
            .accessibilityIdentifier("workspace.commitGraph.canvas")
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - previousDrag.width,
                    height: value.translation.height - previousDrag.height
                )
                previousDrag = value.translation
                viewModel.pan(
                    by: GraphPoint(x: delta.width, y: delta.height)
                )
            }
            .onEnded { _ in
                previousDrag = .zero
                loadOlderIfNeeded()
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let multiplier = value.magnification
                    / previousMagnification
                previousMagnification = value.magnification
                viewModel.zoom(
                    by: multiplier,
                    anchor: pointerAnchor
                )
            }
            .onEnded { _ in
                previousMagnification = 1
            }
    }

    private func drawGrid(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let step = max(32 * viewModel.viewport.scale, 18)
        let startX = viewModel.viewport.offsetX
            .truncatingRemainder(dividingBy: step)
        let startY = viewModel.viewport.offsetY
            .truncatingRemainder(dividingBy: step)
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

    private func drawEdges(context: inout GraphicsContext) {
        let nodesByHash = Dictionary(
            uniqueKeysWithValues: viewModel.layout.nodes.map {
                ($0.hash, $0)
            }
        )
        for edge in viewModel.layout.edges {
            guard let child = nodesByHash[edge.childHash],
                  let parent = nodesByHash[edge.parentHash]
            else {
                continue
            }
            let start = screenPoint(child)
            let end = screenPoint(parent)
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

    private func screenPoint(_ node: CommitGraphNode) -> CGPoint {
        CGPoint(
            x: node.x * viewModel.viewport.scale
                + viewModel.viewport.offsetX,
            y: node.y * viewModel.viewport.scale
                + viewModel.viewport.offsetY
        )
    }

    private var branchLegend: some View {
        HStack(spacing: 10) {
            legendItem(color: CommitGraphPalette.color(0), title: "主分支")
            legendItem(color: CommitGraphPalette.color(1), title: "功能分支")
            legendItem(color: CommitGraphPalette.color(2), title: "发布分支")
            HStack(spacing: 4) {
                Rectangle()
                    .fill(CommitGraphPalette.color(3))
                    .frame(width: 18, height: 2)
                Text("合并")
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(GitMateTheme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(GitMateTheme.border, lineWidth: 1)
        }
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
        }
    }

    private var minimap: some View {
        Canvas { context, size in
            let scaleX = size.width / max(viewModel.layout.contentWidth, 1)
            let scaleY = size.height / max(viewModel.layout.contentHeight, 1)
            for node in viewModel.layout.nodes {
                let rect = CGRect(
                    x: node.x * scaleX - 3,
                    y: node.y * scaleY - 2,
                    width: 6,
                    height: 4
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(
                        CommitGraphPalette.color(node.colorIndex)
                    )
                )
            }
        }
        .frame(width: 128, height: 82)
        .background(GitMateTheme.panel.opacity(0.96))
        .clipShape(
            RoundedRectangle(
                cornerRadius: 9,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 9,
                style: .continuous
            )
            .stroke(GitMateTheme.border, lineWidth: 1)
        }
        .accessibilityLabel("提交图缩略图")
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("正在建立提交关系")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
        .padding(20)
        .background(.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
        )
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "暂无提交历史",
            systemImage: "arrow.triangle.branch",
            description: Text("同步仓库后将在这里显示提交关系")
        )
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(GitMateTheme.textPrimary)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(GitMateTheme.warning.opacity(0.13))
    }

    private var detailPresented: Binding<Bool> {
        Binding(
            get: { viewModel.selectedCommit != nil },
            set: {
                if !$0 {
                    viewModel.dismissDetail()
                }
            }
        )
    }

    private func loadOlderIfNeeded() {
        guard viewModel.nextCursor != nil else { return }
        let loadedBottom = viewModel.layout.contentHeight
            * viewModel.viewport.scale
            + viewModel.viewport.offsetY
        guard loadedBottom < 920 else { return }
        Task {
            await viewModel.loadOlderCommits()
        }
    }
}
