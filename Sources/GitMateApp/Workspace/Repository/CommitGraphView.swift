import GitMateCore
import SwiftUI

struct CommitGraphView: View {
    private struct BranchLegendEntry: Identifiable {
        var id: String { name }
        let name: String
        let colorIndex: Int
    }

    private enum RegionEditorTarget {
        case create(GraphRect)
        case edit(UUID)
    }

    @Bindable var viewModel: CommitGraphViewModel
    var currentUserLogin: String?
    var currentUserAvatarURL: URL?
    @State private var showsCreateGroup = false
    @State private var newGroupTitle = ""
    @State private var marqueePurpose =
        CommitGraphMarqueePurpose.createGroup
    @State private var renamingGroupID: UUID?
    @State private var groupEditorTitle = ""
    @State private var deletingGroupID: UUID?
    @State private var regionEditorTarget: RegionEditorTarget?
    @State private var regionEditorTitle = ""
    @State private var regionEditorColorHex = "#2F80ED"
    @State private var deletingRegionID: UUID?
    @State private var showsGroupSuggestions = false
    @State private var groupNoticeMessage: String?
    @State private var searchText = ""
    @State private var canvasSize = GraphSize(
        width: 1_040,
        height: 680
    )

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.scene.viewMode == .canvas {
                canvasActionBar
                Divider()
            }
            if let message = viewModel.errorMessage {
                errorBanner(message)
            }
            if let message = viewModel.sceneWarningMessage {
                sceneWarningBanner(message)
            }
            graphContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
        .sheet(isPresented: detailPresented) {
            if let detail = viewModel.selectedCommit {
                CommitDetailSheet(
                    detail: detail,
                    diff: viewModel.selectedDiff,
                    isDiffTruncated: viewModel.isSelectedDiffTruncated,
                    avatarURL: avatarURL(for: detail.commit),
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
            Button("取消", role: .cancel) {
                viewModel.clearCanvasSelection()
            }
            Button("创建") {
                do {
                    _ = try viewModel.createManualGroup(
                        title: newGroupTitle
                    )
                    newGroupTitle = ""
                    viewModel.clearCanvasSelection()
                } catch {
                    let message = groupMessage(for: error)
                    viewModel.clearCanvasSelection()
                    Task { @MainActor in
                        groupNoticeMessage = message
                    }
                }
            }
        } message: {
            Text("将已选择的 \(viewModel.selectedHashes.count) 个连通提交组成一个分组。")
        }
        .alert("重命名分组", isPresented: renameGroupPresented) {
            TextField("分组名称", text: $groupEditorTitle)
            Button("取消", role: .cancel) {
                renamingGroupID = nil
            }
            Button("保存") {
                guard let id = renamingGroupID else { return }
                do {
                    try viewModel.renameGroup(
                        id: id,
                        title: groupEditorTitle
                    )
                } catch {
                    groupNoticeMessage = groupMessage(for: error)
                }
                renamingGroupID = nil
            }
        } message: {
            Text("只修改名称，不会改变成员、坐标或连线。")
        }
        .alert("删除分组", isPresented: deleteGroupPresented) {
            Button("取消", role: .cancel) {
                deletingGroupID = nil
            }
            Button("删除", role: .destructive) {
                guard let id = deletingGroupID else { return }
                do {
                    try viewModel.deleteGroup(id: id)
                } catch {
                    groupNoticeMessage = groupMessage(for: error)
                }
                deletingGroupID = nil
            }
        } message: {
            Text("只会解散分组，所有提交和画布位置都会保留。")
        }
        .alert("删除区域标识", isPresented: deleteRegionPresented) {
            Button("取消", role: .cancel) {
                deletingRegionID = nil
            }
            Button("删除", role: .destructive) {
                if let id = deletingRegionID {
                    viewModel.deleteRegion(id: id)
                }
                deletingRegionID = nil
            }
        } message: {
            Text("只删除视觉标识，不会改变提交、分组或连线。")
        }
        .sheet(isPresented: regionEditorPresented) {
            CommitGraphRegionEditor(
                title: regionEditorTitle,
                colorHex: regionEditorColorHex,
                actionTitle: regionEditorActionTitle,
                confirm: saveRegionEditor,
                cancel: {
                    regionEditorTarget = nil
                }
            )
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
                Text(
                    viewModel.scene.viewMode == .traditional
                        ? "GitKraken 式泳道视图，最新提交在上"
                        : "在无限画布中查看分支、合并和提交详情"
                )
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
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(GitMateTheme.textSecondary)
                TextField("搜索提交、作者或哈希", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit(performSearch)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(GitMateTheme.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 230, height: 30)
            .background(GitMateTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(GitMateTheme.border, lineWidth: 1)
            }
            .accessibilityIdentifier("workspace.commitGraph.search")

            Picker(
                "布局",
                selection: Binding(
                    get: { viewModel.scene.viewMode },
                    set: { mode in
                        viewModel.setViewMode(mode)
                    }
                )
            ) {
                Text("传统布局").tag(CommitGraphViewMode.traditional)
                Text("画布布局").tag(CommitGraphViewMode.canvas)
            }
            .pickerStyle(.segmented)
            .frame(width: 188)
            .accessibilityIdentifier("workspace.commitGraph.viewMode")

            integrityBadge

            refreshStateBadge

            Button {
                Task {
                    await viewModel.refresh(source: .toolbar)
                }
            } label: {
                if viewModel.refreshState.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                } else {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.refreshState.isRefreshing)
            .accessibilityIdentifier("workspace.commitGraph.refresh")

            Text("\(viewModel.traditionalLayout.rows.count) 个提交")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(GitMateTheme.textSecondary)
        }
    }

    private var canvasActionBar: some View {
        HStack(spacing: 8) {
            Button {
                marqueePurpose = .createGroup
                viewModel.clearCanvasSelection()
            } label: {
                Label(
                    "右键框选分组",
                    systemImage: "rectangle.dashed.badge.record"
                )
            }
            .help("在画布空白处按住右键拖动，框选连通提交")

            Button {
                marqueePurpose = .createRegion
                viewModel.clearCanvasSelection()
            } label: {
                Label(
                    marqueePurpose == .createRegion
                        ? "框选版本区域"
                        : "创建区域标识",
                    systemImage: "rectangle.inset.filled.and.person.filled"
                )
            }
            .tint(
                marqueePurpose == .createRegion
                    ? GitMateTheme.accent
                    : nil
            )
            .help("下一次右键框选将创建大版本区域")

            if case let .addToGroup(id) = marqueePurpose,
               let group = viewModel.group(id: id) {
                Label(
                    "正在为「\(group.title)」添加提交",
                    systemImage: "plus.rectangle.on.folder"
                )
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(GitMateTheme.accent)
            }

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
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
        .background(.white)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.commitGraph.zoom")
    }

    @ViewBuilder
    private var graphContent: some View {
        if viewModel.scene.viewMode == .traditional {
            CommitGraphTraditionalView(
                layout: viewModel.traditionalLayout,
                branchCatalog: viewModel.branchCatalog,
                branchProjection: viewModel.traditionalBranchProjection,
                pinnedBranchIDs: viewModel.scene.pinnedTraditionalBranchIDs,
                groupBadgeByHash: viewModel.traditionalGroupBadgeByHash,
                groupRevision: viewModel.traditionalGroupRevision,
                selectedHash: viewModel.selectedHash,
                focusedHash: viewModel.focusedHash,
                localStatus: viewModel.localStatus,
                currentUserLogin: currentUserLogin,
                currentUserAvatarURL: currentUserAvatarURL,
                select: { hash in
                    viewModel.selectForNavigation(hash: hash)
                    Task {
                        await viewModel.select(hash: hash)
                    }
                },
                setViewportWidth: { width in
                    viewModel.setTraditionalViewportWidth(width)
                },
                selectBranch: { id in
                    viewModel.selectTraditionalBranch(id: id)
                },
                togglePinnedBranch: { id in
                    viewModel.togglePinnedTraditionalBranch(id: id)
                },
                consumeFocus: { hash in
                    viewModel.consumeFocusedHash(hash)
                }
            )
        } else {
            graphCanvas
        }
    }

    @ViewBuilder
    private var integrityBadge: some View {
        if let report = viewModel.integrityReport {
            switch report.status {
            case .valid:
                Label("关系完整", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(GitMateTheme.success)
            case .warning:
                Label("浅克隆边界", systemImage: "exclamationmark.shield.fill")
                    .foregroundStyle(GitMateTheme.warning)
            case .invalid:
                Label("关系异常", systemImage: "xmark.shield.fill")
                    .foregroundStyle(GitMateTheme.danger)
            }
        } else {
            Label("等待校验", systemImage: "shield")
                .foregroundStyle(GitMateTheme.textSecondary)
        }
    }

    private var graphCanvas: some View {
        GeometryReader { geometry in
            let screenSize = GraphSize(
                width: Double(geometry.size.width),
                height: Double(geometry.size.height)
            )
            let visibleScene = viewModel.visibleScene(
                screenSize: screenSize
            )
            let levelOfDetail = CommitGraphLevelOfDetail.forScale(
                viewModel.viewport.scale
            )
            let bundleViewport = canvasViewportRect(
                screenSize: screenSize,
                viewport: viewModel.viewport
            )
            let visibleBundles = levelOfDetail == .overview
                ? viewModel.visibleBranchBundles(in: bundleViewport)
                : []
            let hiddenBundleHashes = levelOfDetail == .overview
                ? viewModel.branchBundleProjection.hiddenMemberHashes
                : []
            let hiddenBundleEdges = levelOfDetail == .overview
                ? viewModel.branchBundleProjection.hiddenInternalEdgeIDs
                : []
            let navigatorHeight = min(geometry.size.height * 0.64, 480)
            let markerBins = viewModel.historyMarkerBins(
                pixelHeight: max(Double(navigatorHeight) - 76, 1)
            )
            ZStack {
                CommitGraphCanvas(
                    visibleScene: visibleScene,
                    regions: visibleScene.regions,
                    branchBundles: visibleBundles,
                    hiddenBundleMemberHashes: hiddenBundleHashes,
                    hiddenBundleEdgeIDs: hiddenBundleEdges,
                    viewport: viewModel.viewport,
                    levelOfDetail: levelOfDetail,
                    selectedHashes: viewModel.selectedHashes,
                    selectedHash: viewModel.selectedHash,
                    highlightedEdgeIDs: viewModel.highlightedEdgeIDs,
                    highlightedNodeHashes: viewModel.highlightedNodeHashes
                )

                CommitGraphInteractionSurface(
                    visibleScene: visibleScene,
                    regions: visibleScene.regions,
                    viewport: viewModel.viewport,
                    marqueePurpose: marqueePurpose,
                    hitTestCanvas: { point in
                        viewModel.hitTest(canvasPoint: point)
                    },
                    hitTestBranchBundle: { point in
                        guard levelOfDetail == .overview else { return nil }
                        return viewModel.branchBundle(at: point)?.id
                    },
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
                    onBranchBundleClick: { id in
                        viewModel.toggleBranchBundle(id: id)
                    },
                    onMarqueeSelectionCompleted: {
                        purpose,
                        hashes,
                        rect in
                        handleMarqueeCompletion(
                            purpose: purpose,
                            hashes: hashes,
                            rect: rect
                        )
                    },
                    onContextAction: { action in
                        handleContextAction(action)
                    },
                    onCancelMarqueeMode: {
                        cancelMarqueeMode()
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

                if levelOfDetail != .overview {
                    accessibilityNodes(
                        visibleNodes: visibleScene.nodes
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
                        branchLegend(visibleNodes: visibleScene.nodes)
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
                        if viewModel.historyCommitCount > 0 {
                            CommitGraphHistoryNavigator(
                                count: viewModel.historyCommitCount,
                                markerBins: markerBins,
                                viewportRange: viewModel.historyViewportRange(
                                    screenHeight: screenSize.height
                                ),
                                currentRow: viewModel.historyRow(
                                    hash: viewModel.selectedHash
                                ),
                                navigate: { progress in
                                    navigateHistory(
                                        progress: progress,
                                        screenSize: screenSize
                                    )
                                }
                            )
                            .frame(height: navigatorHeight)
                        }
                    }
                }
                .padding(14)
            }
            .onAppear {
                canvasSize = screenSize
                if let hash = viewModel.focusedHash {
                    viewModel.focusCommit(hash: hash, in: screenSize)
                    viewModel.consumeFocusedHash(hash)
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                canvasSize = GraphSize(
                    width: Double(newSize.width),
                    height: Double(newSize.height)
                )
            }
            .onChange(of: viewModel.focusedHash) { _, hash in
                guard let hash,
                      viewModel.scene.viewMode == .canvas
                else { return }
                viewModel.focusCommit(hash: hash, in: screenSize)
                viewModel.consumeFocusedHash(hash)
            }
            .onExitCommand {
                cancelMarqueeMode()
            }
        }
    }

    private func canvasViewportRect(
        screenSize: GraphSize,
        viewport: GraphViewport
    ) -> GraphRect {
        let first = CommitGraphViewportProjector.canvasPoint(
            screenPoint: .zero,
            viewport: viewport
        )
        let second = CommitGraphViewportProjector.canvasPoint(
            screenPoint: GraphPoint(
                x: screenSize.width,
                y: screenSize.height
            ),
            viewport: viewport
        )
        return GraphRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }

    private func accessibilityNodes(
        visibleNodes: [CommitGraphVisibleNode]
    ) -> some View {
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

    private func branchLegend(
        visibleNodes: [CommitGraphVisibleNode]
    ) -> some View {
        let entries = visibleBranchLegendEntries(
            visibleNodes: visibleNodes
        )
        return HStack(spacing: 7) {
            ForEach(Array(entries.prefix(3))) { entry in
                legendItem(
                    color: CommitGraphPalette.color(entry.colorIndex),
                    title: entry.name
                )
            }

            if entries.count > 3 {
                Menu {
                    ForEach(Array(entries.dropFirst(3))) { entry in
                        Label {
                            Text(entry.name)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(
                                    CommitGraphPalette.color(
                                        entry.colorIndex
                                    )
                                )
                        }
                    }
                } label: {
                    Label(
                        "更多 \(entries.count - 3)",
                        systemImage: "ellipsis"
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(GitMateTheme.panel.opacity(0.94))
                .clipShape(Capsule())
            }

            Label("合并", systemImage: "arrow.triangle.merge")
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(GitMateTheme.panel.opacity(0.94))
                .clipShape(Capsule())
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(GitMateTheme.textSecondary)
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(GitMateTheme.panel.opacity(0.94))
        .clipShape(Capsule())
    }

    private func visibleBranchLegendEntries(
        visibleNodes: [CommitGraphVisibleNode]
    ) -> [BranchLegendEntry] {
        var seen = Set<String>()
        var result: [BranchLegendEntry] = []
        for visibleNode in visibleNodes {
            for decoration in visibleNode.node.decorations {
                guard let name = branchName(from: decoration),
                      seen.insert(name).inserted
                else {
                    continue
                }
                result.append(
                    BranchLegendEntry(
                        name: name,
                        colorIndex: visibleNode.node.colorIndex
                    )
                )
            }
        }
        return result
    }

    @ViewBuilder
    private var refreshStateBadge: some View {
        switch viewModel.refreshState {
        case .idle:
            Label("未刷新", systemImage: "clock")
                .foregroundStyle(GitMateTheme.textSecondary)
        case let .refreshing(usingCachedSnapshot):
            Label(
                usingCachedSnapshot ? "刷新中·已显示缓存" : "刷新中",
                systemImage: "arrow.triangle.2.circlepath"
            )
            .foregroundStyle(GitMateTheme.accent)
        case .current:
            Label("已是最新", systemImage: "checkmark.circle.fill")
                .foregroundStyle(GitMateTheme.success)
        case .stale:
            Label("显示上次结果", systemImage: "clock.badge.exclamationmark")
                .foregroundStyle(GitMateTheme.warning)
        case .failed:
            Label("刷新失败", systemImage: "xmark.octagon.fill")
                .foregroundStyle(GitMateTheme.danger)
        }
    }

    private func performSearch() {
        guard viewModel.navigateToFirstMatch(searchText) else {
            groupNoticeMessage = "没有找到匹配的提交。"
            return
        }
        guard viewModel.scene.viewMode == .canvas,
              let hash = viewModel.focusedHash
        else { return }
        viewModel.focusCommit(hash: hash, in: canvasSize)
        viewModel.consumeFocusedHash(hash)
    }

    private func navigateHistory(
        progress: Double,
        screenSize: GraphSize
    ) {
        guard let hash = viewModel.hashAtHistoryProgress(progress) else {
            return
        }
        viewModel.selectForNavigation(hash: hash)
        viewModel.setHistoryViewportProgress(
            progress,
            screenHeight: screenSize.height
        )
        viewModel.consumeFocusedHash(hash)
    }

    private func branchName(from decoration: String) -> String? {
        var name = decoration.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !name.isEmpty,
              !name.hasPrefix("tag:")
        else {
            return nil
        }
        if name.hasPrefix("HEAD -> ") {
            name.removeFirst("HEAD -> ".count)
        }
        guard name != "HEAD", !name.isEmpty else {
            return nil
        }
        return name
    }

    private func avatarURL(for commit: GitCommit) -> URL? {
        let email = commit.authorEmail.lowercased()
        if email.hasSuffix("@users.noreply.github.com") {
            let local = String(
                email.split(separator: "@", maxSplits: 1)[0]
            )
            let login = local.split(
                separator: "+",
                maxSplits: 1
            ).last.map(String.init) ?? local
            if !login.isEmpty,
               login.allSatisfy({
                   $0.isLetter || $0.isNumber || $0 == "-"
               }) {
                return URL(
                    string: "https://github.com/\(login).png?size=128"
                )
            }
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

    private var renameGroupPresented: Binding<Bool> {
        Binding(
            get: { renamingGroupID != nil },
            set: {
                if !$0 {
                    renamingGroupID = nil
                }
            }
        )
    }

    private var deleteGroupPresented: Binding<Bool> {
        Binding(
            get: { deletingGroupID != nil },
            set: {
                if !$0 {
                    deletingGroupID = nil
                }
            }
        )
    }

    private var deleteRegionPresented: Binding<Bool> {
        Binding(
            get: { deletingRegionID != nil },
            set: {
                if !$0 {
                    deletingRegionID = nil
                }
            }
        )
    }

    private var regionEditorPresented: Binding<Bool> {
        Binding(
            get: { regionEditorTarget != nil },
            set: {
                if !$0 {
                    regionEditorTarget = nil
                }
            }
        )
    }

    private var regionEditorActionTitle: String {
        switch regionEditorTarget {
        case .create:
            "创建区域标识"
        case .edit:
            "编辑区域标识"
        case nil:
            "区域标识"
        }
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

    private func handleMarqueeCompletion(
        purpose: CommitGraphMarqueePurpose,
        hashes: Set<String>,
        rect: GraphRect
    ) {
        defer {
            marqueePurpose = .createGroup
        }
        switch purpose {
        case .createGroup:
            viewModel.replaceSelection(with: hashes)
            do {
                try viewModel.validateManualGroupSelection()
                newGroupTitle = ""
                showsCreateGroup = true
            } catch {
                viewModel.clearCanvasSelection()
                groupNoticeMessage = groupMessage(for: error)
            }
        case let .addToGroup(groupID):
            guard let group = viewModel.group(id: groupID) else {
                viewModel.clearCanvasSelection()
                groupNoticeMessage =
                    groupMessage(for: CommitGraphGroupingError.groupNotFound)
                return
            }
            let addedHashes = hashes.subtracting(group.memberHashes)
            guard !addedHashes.isEmpty else {
                viewModel.clearCanvasSelection()
                groupNoticeMessage = "请框选至少一个尚未加入该分组的提交。"
                return
            }
            viewModel.replaceSelection(with: addedHashes)
            do {
                try viewModel.addSelectedCommits(to: groupID)
            } catch {
                viewModel.clearCanvasSelection()
                groupNoticeMessage = groupMessage(for: error)
            }
        case .createRegion:
            viewModel.clearCanvasSelection()
            guard rect.width >= 120, rect.height >= 90 else {
                groupNoticeMessage =
                    "区域范围太小，请至少框选 120 × 90 的画布范围。"
                return
            }
            regionEditorTitle = ""
            regionEditorColorHex = "#2F80ED"
            regionEditorTarget = .create(rect)
        }
    }

    private func handleContextAction(
        _ action: CommitGraphContextAction
    ) {
        switch action {
        case let .renameGroup(id):
            guard let group = viewModel.group(id: id) else { return }
            groupEditorTitle = group.title
            renamingGroupID = id
        case let .addToGroup(id):
            guard viewModel.group(id: id) != nil else { return }
            viewModel.clearCanvasSelection()
            marqueePurpose = .addToGroup(id)
        case let .deleteGroup(id):
            deletingGroupID = id
        case let .editRegion(id):
            guard let region = viewModel.region(id: id) else { return }
            regionEditorTitle = region.title
            regionEditorColorHex = region.colorHex
            regionEditorTarget = .edit(id)
        case let .deleteRegion(id):
            deletingRegionID = id
        }
    }

    private func cancelMarqueeMode() {
        marqueePurpose = .createGroup
        viewModel.clearCanvasSelection()
    }

    private func saveRegionEditor(
        title: String,
        colorHex: String
    ) {
        guard let target = regionEditorTarget else { return }
        switch target {
        case let .create(rect):
            _ = viewModel.createRegion(
                title: title,
                colorHex: colorHex,
                rect: rect
            )
        case let .edit(id):
            viewModel.updateRegion(
                id: id,
                title: title,
                colorHex: colorHex,
                rect: nil
            )
        }
        regionEditorTarget = nil
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
