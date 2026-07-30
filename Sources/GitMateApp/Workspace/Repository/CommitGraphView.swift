import GitMateCore
import SwiftUI

struct CommitGraphView: View {
    @Bindable var viewModel: CommitGraphViewModel
    @State private var showsCreateGroup = false
    @State private var newGroupTitle = ""
    @State private var showsGroupSuggestions = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let message = viewModel.errorMessage {
                errorBanner(message)
            }
            if let message = viewModel.sceneWarningMessage {
                sceneWarningBanner(message)
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
        .sheet(isPresented: $showsGroupSuggestions) {
            CommitGraphGroupSuggestionSheet(
                suggestions: viewModel.groupSuggestions,
                confirm: { suggestionIDs in
                    for id in suggestionIDs {
                        _ = try? viewModel.confirmGroupSuggestion(id: id)
                    }
                    showsGroupSuggestions = false
                },
                cancel: {
                    showsGroupSuggestions = false
                }
            )
        }
        .alert("创建提交分组", isPresented: $showsCreateGroup) {
            TextField("分组名称", text: $newGroupTitle)
            Button("取消", role: .cancel) {}
            Button("创建") {
                _ = try? viewModel.createManualGroup(
                    title: newGroupTitle
                )
                newGroupTitle = ""
            }
        } message: {
            Text("将已选择的 \(viewModel.selectedHashes.count) 个连通提交组成一个分组。")
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
                newGroupTitle = ""
                showsCreateGroup = true
            } label: {
                Label(
                    "创建分组",
                    systemImage: "square.stack.3d.up.badge.a"
                )
            }
            .disabled(viewModel.selectedHashes.count < 2)

            Button {
                Task {
                    await viewModel.prepareGroupSuggestions()
                    showsGroupSuggestions = true
                }
            } label: {
                Label(
                    viewModel.isPreparingGroupSuggestions
                        ? "分析中"
                        : "自动分组",
                    systemImage: "sparkles.rectangle.stack"
                )
            }
            .disabled(viewModel.isPreparingGroupSuggestions)

            Picker(
                "连线",
                selection: Binding(
                    get: { viewModel.scene.lineStyle },
                    set: { style in
                        viewModel.setLineStyle(style)
                    }
                )
            ) {
                Label("曲线", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .tag(CommitGraphLineStyle.curve)
                Label("直角", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                    .tag(CommitGraphLineStyle.orthogonal)
            }
            .pickerStyle(.segmented)
            .frame(width: 130)

            Divider()
                .frame(height: 22)

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
            let screenSize = GraphSize(
                width: Double(geometry.size.width),
                height: Double(geometry.size.height)
            )
            ZStack {
                CommitGraphCanvas(
                    projection: viewModel.projection,
                    viewport: viewModel.viewport,
                    lineStyle: viewModel.scene.lineStyle,
                    selectedHashes: viewModel.selectedHashes,
                    selectedHash: viewModel.selectedHash
                )

                CommitGraphInteractionSurface(
                    projection: viewModel.projection,
                    viewport: viewModel.viewport,
                    onViewportChanges: { changes in
                        viewModel.applyViewportChanges(changes)
                        loadOlderIfNeeded()
                    },
                    onPointerChanges: { changes in
                        viewModel.applyPointerChanges(changes)
                    },
                    onNodeClick: { hash, modifiers, opensDetail in
                        viewModel.toggleSelection(
                            hash: hash,
                            modifiers: modifiers
                        )
                        if opensDetail {
                            Task {
                                await viewModel.select(hash: hash)
                            }
                        }
                    },
                    onGroupDoubleClick: { id, isCollapsed in
                        viewModel.setGroupCollapsed(
                            id: id,
                            isCollapsed: !isCollapsed
                        )
                    },
                    onDoubleClickBlank: {
                        viewModel.fitAll(in: screenSize)
                    },
                    onInteractionEnded: {
                        Task {
                            await viewModel.persistSceneImmediately()
                        }
                    }
                )
                .accessibilityLabel("无限画布提交图")
                .accessibilityHint("拖拽平移，滚轮或捏合缩放，双击空白适配全部提交")
                .accessibilityIdentifier("workspace.commitGraph.canvas")

                accessibilityNodes(screenSize: screenSize)

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
                    }
                }
                .padding(14)
                .allowsHitTesting(false)
            }
        }
    }

    private func accessibilityNodes(
        screenSize: GraphSize
    ) -> some View {
        let visibleNodes = viewModel.projection.nodes.filter {
            isVisible(
                position: $0.position,
                screenSize: screenSize,
                padding: 180
            )
        }

        return ForEach(visibleNodes) { visibleNode in
            let node = visibleNode.node
            let point = CommitGraphViewportProjector.screenPoint(
                canvasPoint: visibleNode.position,
                viewport: viewModel.viewport
            )
            Rectangle()
                .fill(.clear)
                .frame(
                    width: CGFloat(
                        CommitGraphViewportProjector.nodeWidth
                            * viewModel.viewport.scale
                    ),
                    height: CGFloat(
                        CommitGraphViewportProjector.nodeHeight
                            * viewModel.viewport.scale
                    )
                )
                .position(
                    x: CGFloat(point.x),
                    y: CGFloat(point.y)
                )
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(node.subject)，作者 \(node.authorName)，提交 \(node.shortHash)"
                )
                .accessibilityHint("打开提交详情")
                .accessibilityAddTraits(
                    viewModel.selectedHash == node.hash
                        ? [.isButton, .isSelected]
                        : .isButton
                )
                .accessibilityAction {
                    Task {
                        await viewModel.select(hash: node.hash)
                    }
                }
                .accessibilityIdentifier(
                    "workspace.commitGraph.node.\(node.hash)"
                )
        }
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

    private func sceneWarningBanner(_ message: String) -> some View {
        Label(message, systemImage: "externaldrive.badge.exclamationmark")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(GitMateTheme.textSecondary)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(GitMateTheme.panel)
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

    private func isVisible(
        position: GraphPoint,
        screenSize: GraphSize,
        padding: Double
    ) -> Bool {
        let point = CommitGraphViewportProjector.screenPoint(
            canvasPoint: position,
            viewport: viewModel.viewport
        )
        let width = CommitGraphViewportProjector.nodeWidth
            * viewModel.viewport.scale
        let height = CommitGraphViewportProjector.nodeHeight
            * viewModel.viewport.scale
        return point.x + width / 2 >= -padding
            && point.x - width / 2 <= screenSize.width + padding
            && point.y + height / 2 >= -padding
            && point.y - height / 2 <= screenSize.height + padding
    }
}
