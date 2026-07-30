import GitMateCore
import SwiftUI

struct CommitGraphView: View {
    @Bindable var viewModel: CommitGraphViewModel
    @State private var showsCreateGroup = false
    @State private var newGroupTitle = ""
    @State private var showsGroupSuggestions = false
    @State private var groupNoticeMessage: String?
    @State private var canvasSize = GraphSize(
        width: 1_040,
        height: 680
    )

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
                do {
                    _ = try viewModel.createManualGroup(
                        title: newGroupTitle
                    )
                    newGroupTitle = ""
                } catch {
                    let message = groupMessage(for: error)
                    Task { @MainActor in
                        groupNoticeMessage = message
                    }
                }
            }
        } message: {
            Text("将已选择的 \(viewModel.selectedHashes.count) 个连通提交组成一个分组。")
        }
        .alert("提交分组", isPresented: groupNoticePresented) {
            Button("知道了") {}
        } message: {
            Text(groupNoticeMessage ?? "")
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
                groupNoticeMessage =
                    "在画布空白处按住鼠标右键拖动即可框选提交；靠近画布边缘会自动滚动。"
            } label: {
                Label(
                    "右键框选创建",
                    systemImage: "rectangle.dashed.badge.record"
                )
            }
            .help("在画布空白处按住右键拖动，框选连通提交")

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
            .help("重新排列未分组提交，保留现有分组、折叠状态和分组位置")

            Button {
                viewModel.focusCurrentBranch(
                    canvasWidth: canvasSize.width,
                    canvasHeight: canvasSize.height
                )
            } label: {
                Label("聚焦主分支", systemImage: "scope")
            }
            .help("只移动画布视口，不改变分组和折叠状态")
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
                    onMarqueeSelectionCompleted: { hashes in
                        viewModel.replaceSelection(with: hashes)
                        do {
                            try viewModel.validateManualGroupSelection()
                            newGroupTitle = ""
                            showsCreateGroup = true
                        } catch {
                            groupNoticeMessage =
                                groupMessage(for: error)
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
                .accessibilityHint("左键拖拽平移，右键拖拽框选分组，滚轮或捏合缩放")
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
                        groupSelectionHint
                    }
                }
                .padding(14)
                .allowsHitTesting(false)
            }
            .onAppear {
                canvasSize = screenSize
            }
            .onChange(of: geometry.size) { _, newSize in
                canvasSize = GraphSize(
                    width: Double(newSize.width),
                    height: Double(newSize.height)
                )
            }
        }
    }

    private var groupSelectionHint: some View {
        Label(
            groupSelectionHintText,
            systemImage: viewModel.selectedHashes.isEmpty
                ? "rectangle.dashed"
                : "checkmark.circle.fill"
        )
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(
            viewModel.selectedHashes.count >= 2
                ? GitMateTheme.success
                : GitMateTheme.textSecondary
        )
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.white.opacity(0.94))
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(GitMateTheme.border, lineWidth: 1)
        }
    }

    private var groupSelectionHintText: String {
        switch viewModel.selectedHashes.count {
        case 0:
            "空白处按住右键框选，靠近边缘自动滚动"
        case 1:
            "已框选 1 个，请扩大范围选择相邻提交"
        default:
            "已框选 \(viewModel.selectedHashes.count) 个提交"
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

    private var groupNoticePresented: Binding<Bool> {
        Binding(
            get: { groupNoticeMessage != nil },
            set: {
                if !$0 {
                    groupNoticeMessage = nil
                }
            }
        )
    }

    private func groupMessage(for error: Error) -> String {
        guard let error = error as? CommitGraphGroupingError else {
            return "暂时无法创建提交分组。"
        }
        switch error {
        case .insufficientMembers:
            return "请先选择至少 2 个提交。"
        case .disconnectedSelection:
            return "所选提交必须处在同一个连通的提交关系中，可以包含分叉和合并。"
        case .membersAlreadyGrouped:
            return "所选提交中已有提交属于其他分组，请调整选择后重试。"
        case .unknownMembers:
            return "部分提交已经不在当前画布中，请重新选择。"
        case .groupNotFound:
            return "目标分组已经不存在。"
        }
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
