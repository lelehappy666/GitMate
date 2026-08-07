import Foundation
import Observation

public enum CommitGraphRefreshSource: Equatable, Sendable {
    case initial
    case sidebar
    case toolbar
}

public enum CommitGraphRefreshState: Equatable, Sendable {
    case idle
    case refreshing(usingCachedSnapshot: Bool)
    case current(Date)
    case stale(message: String)
    case failed(message: String)

    public var isRefreshing: Bool {
        if case .refreshing = self { return true }
        return false
    }
}

@MainActor
@Observable
public final class CommitGraphViewModel {
    public var viewport = GraphViewport()
    public private(set) var layout = CommitGraphLayoutResult()
    public private(set) var scene = CommitGraphSceneState()
    public private(set) var projection = CommitGraphSceneProjection(
        nodes: [],
        groups: [],
        edges: []
    )
    public private(set) var selectedHashes: Set<String> = []
    public private(set) var groupSuggestions:
        [CommitGraphGroupSuggestion] = []
    public private(set) var isPreparingGroupSuggestions = false
    public private(set) var sceneWarningMessage: String?
    public private(set) var pathRevision = 0
    public private(set) var selectedCommit: GitCommitDetail?
    public private(set) var selectedDiff: GitDiff?
    public private(set) var isSelectedDiffTruncated = false
    public private(set) var selectedHash: String?
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var nextCursor: String?
    public private(set) var errorMessage: String?
    public private(set) var traditionalLayout =
        CommitGraphTraditionalLayoutResult(rows: [], maximumLane: 0)
    public private(set) var integrityReport: CommitGraphIntegrityReport?
    public private(set) var refreshState: CommitGraphRefreshState = .idle
    public private(set) var focusedHash: String?

    @ObservationIgnored
    private let reader: any LocalGitReading

    @ObservationIgnored
    private let repositoryURL: URL

    @ObservationIgnored
    private let repositoryID: Int64?

    @ObservationIgnored
    private let sceneStore: (any CommitGraphSceneStoring)?

    @ObservationIgnored
    private let refreshCoordinator: CommitGraphRefreshCoordinator?

    @ObservationIgnored
    private let pageSize: Int

    @ObservationIgnored
    private let maximumPatchCharacters: Int

    @ObservationIgnored
    private let graphLayout: CommitGraphLayout

    @ObservationIgnored
    private let traditionalGraphLayout: CommitGraphTraditionalLayout

    @ObservationIgnored
    private var commits: [GitCommit] = []

    @ObservationIgnored
    private var graphTask: Task<CommitGraphPage, Error>?

    @ObservationIgnored
    private var detailTask: Task<GitCommitDetail, Error>?

    @ObservationIgnored
    private var diffTask: Task<GitDiff, Error>?

    @ObservationIgnored
    private var graphRequestID = UUID()

    @ObservationIgnored
    private var selectionRequestID = UUID()

    @ObservationIgnored
    private var sceneSaveTask: Task<Void, Never>?

    @ObservationIgnored
    private var didRestoreScene = false

    @ObservationIgnored
    private var currentSnapshot: CommitGraphSnapshot?

    @ObservationIgnored
    private var renderIndex: CommitGraphRenderIndex?

    @ObservationIgnored
    private var refreshRequestID: UInt64 = 0

    public init(
        reader: any LocalGitReading,
        repositoryURL: URL,
        repositoryID: Int64? = nil,
        sceneStore: (any CommitGraphSceneStoring)? = nil,
        refreshCoordinator: CommitGraphRefreshCoordinator? = nil,
        pageSize: Int = 200,
        maximumPatchCharacters: Int = 200_000,
        layout: CommitGraphLayout = CommitGraphLayout(),
        traditionalLayout: CommitGraphTraditionalLayout =
            CommitGraphTraditionalLayout()
    ) {
        self.reader = reader
        self.repositoryURL = repositoryURL
        self.repositoryID = repositoryID
        self.sceneStore = sceneStore
        self.refreshCoordinator = refreshCoordinator
        self.pageSize = min(max(pageSize, 1), 200)
        self.maximumPatchCharacters = max(maximumPatchCharacters, 1)
        graphLayout = layout
        traditionalGraphLayout = traditionalLayout
    }

    public func loadCachedSnapshot() async {
        guard let repositoryID, let refreshCoordinator else {
            await load()
            return
        }
        let requestID = beginRefreshRequest()
        guard let snapshot = await refreshCoordinator.cachedSnapshot(
            repositoryID: repositoryID
        ) else {
            guard isCurrentRefreshRequest(requestID) else { return }
            refreshState = .idle
            return
        }
        let report = CommitGraphIntegrityValidator.validate(snapshot)
        guard report.status != .invalid else {
            guard isCurrentRefreshRequest(requestID) else { return }
            integrityReport = report
            refreshState = .failed(message: "本地提交图缓存已损坏。")
            return
        }
        let derived = await deriveLayouts(for: snapshot)
        guard await installSnapshot(
            snapshot,
            integrity: report,
            derived: derived,
            requestID: requestID
        ) else { return }
        refreshState = .stale(message: "正在显示上次正确结果。")
    }

    public func refresh(source _: CommitGraphRefreshSource) async {
        guard let repositoryID, let refreshCoordinator else {
            await load()
            return
        }
        let requestID = beginRefreshRequest()
        let hadSnapshot = currentSnapshot != nil
        refreshState = .refreshing(usingCachedSnapshot: hadSnapshot)
        isLoading = !hadSnapshot
        errorMessage = nil

        do {
            let result = try await refreshCoordinator.refresh(
                repositoryID: repositoryID,
                repositoryURL: repositoryURL
            )
            guard isCurrentRefreshRequest(requestID) else { return }
            if result.didChange || currentSnapshot == nil {
                let derived = await deriveLayouts(for: result.snapshot)
                guard await installSnapshot(
                    result.snapshot,
                    integrity: result.integrity,
                    derived: derived,
                    requestID: requestID
                ) else { return }
            } else {
                integrityReport = result.integrity
            }
            guard isCurrentRefreshRequest(requestID) else { return }
            isLoading = false
            refreshState = .current(result.refreshedAt)
        } catch is CancellationError {
            guard isCurrentRefreshRequest(requestID) else { return }
            isLoading = false
            refreshState = currentSnapshot == nil
                ? .idle
                : .stale(message: "刷新已取消，显示上次正确结果。")
        } catch {
            guard isCurrentRefreshRequest(requestID) else { return }
            isLoading = false
            if case let CommitGraphRefreshError.invalidSnapshot(report) = error {
                integrityReport = report
            }
            if currentSnapshot != nil {
                let message = "刷新失败，显示上次正确结果。"
                refreshState = .stale(message: message)
                errorMessage = message
            } else {
                let message = "无法读取提交图，请稍后重试。"
                refreshState = .failed(message: message)
                errorMessage = message
            }
        }
    }

    public func setViewMode(_ mode: CommitGraphViewMode) {
        guard scene.viewMode != mode else { return }
        if scene.viewMode == .canvas {
            scene.canvasViewport = viewport
        }
        scene.viewMode = mode
        if mode == .canvas {
            viewport = scene.canvasViewport
        }
        focusedHash = navigationFocusHash()
        scheduleSceneSave()
    }

    public func selectForNavigation(hash: String) {
        guard layout.node(hash: hash) != nil else { return }
        selectedHash = hash
        selectedHashes = [hash]
        focusedHash = hash
    }

    public func consumeFocusedHash(_ hash: String) {
        guard focusedHash == hash else { return }
        focusedHash = nil
    }

    public func visibleScene(
        screenSize: GraphSize
    ) -> CommitGraphVisibleScene {
        renderIndex?.query(
            viewport: viewport,
            screenSize: screenSize,
            padding: 180
        ) ?? CommitGraphVisibleScene(nodes: [], groups: [], edges: [])
    }

    public func load() async {
        graphTask?.cancel()
        let requestID = UUID()
        graphRequestID = requestID
        isLoading = true
        isLoadingMore = false
        errorMessage = nil

        let reader = reader
        let repositoryURL = repositoryURL
        let pageSize = pageSize
        let task = Task {
            try await reader.graph(
                repositoryURL: repositoryURL,
                cursor: nil,
                limit: pageSize
            )
        }
        graphTask = task

        do {
            let page = try await task.value
            guard graphRequestID == requestID else { return }
            commits = uniqueCommits(page.commits)
            layout = graphLayout.layout(
                page: CommitGraphPage(
                    commits: commits,
                    nextCursor: page.nextCursor
                )
            )
            await restoreOrReconcileScene()
            nextCursor = page.nextCursor
            isLoading = false
        } catch is CancellationError {
            if graphRequestID == requestID {
                isLoading = false
            }
        } catch {
            guard graphRequestID == requestID else { return }
            isLoading = false
            errorMessage = "无法读取提交图，请稍后重试。"
        }
    }

    public func loadOlderCommits() async {
        guard !isLoading,
              !isLoadingMore,
              let cursor = nextCursor
        else {
            return
        }

        let requestID = UUID()
        graphRequestID = requestID
        isLoadingMore = true
        errorMessage = nil

        let reader = reader
        let repositoryURL = repositoryURL
        let pageSize = pageSize
        let task = Task {
            try await reader.graph(
                repositoryURL: repositoryURL,
                cursor: cursor,
                limit: pageSize
            )
        }
        graphTask = task

        do {
            let page = try await task.value
            guard graphRequestID == requestID else { return }
            commits = uniqueCommits(commits + page.commits)
            layout = graphLayout.layout(
                page: CommitGraphPage(
                    commits: commits,
                    nextCursor: page.nextCursor
                ),
                preserving: layout
            )
            reconcileSceneWithLayout()
            nextCursor = page.nextCursor
            isLoadingMore = false
        } catch is CancellationError {
            if graphRequestID == requestID {
                isLoadingMore = false
            }
        } catch {
            guard graphRequestID == requestID else { return }
            isLoadingMore = false
            errorMessage = "无法加载更早提交，请稍后重试。"
        }
    }

    public func pan(by translation: GraphPoint) {
        viewport.offsetX += translation.x
        viewport.offsetY += translation.y
        synchronizeCanvasViewportIfNeeded()
    }

    public func zoom(by multiplier: Double, anchor: GraphPoint) {
        viewport = CommitGraphViewportProjector.zoomed(
            viewport,
            by: multiplier,
            anchor: anchor
        )
        synchronizeCanvasViewportIfNeeded()
    }

    public func applyViewportChanges(_ changes: [GraphViewportChange]) {
        viewport = CommitGraphViewportProjector.applying(
            changes,
            to: viewport
        )
        synchronizeCanvasViewportIfNeeded()
    }

    public func applyPointerChanges(
        _ changes: [CommitGraphPointerChange]
    ) {
        guard !changes.isEmpty else { return }
        var updatedScene = scene
        var movedNodeHashes: Set<String> = []
        var movedGroupIDs: Set<UUID> = []
        for change in changes {
            switch change {
            case let .pan(translation):
                pan(by: translation)
            case let .moveNode(hash, translation):
                updatedScene = sceneByMovingNode(
                    hash: hash,
                    by: translation,
                    scene: updatedScene
                )
                movedNodeHashes.insert(hash)
            case let .moveGroup(id, translation):
                updatedScene = CommitGraphGrouping.movingGroup(
                    id: id,
                    translation: translation,
                    scene: updatedScene
                )
                movedGroupIDs.insert(id)
            case let .moveRegion(id, translation):
                updatedScene = sceneByMovingRegion(
                    id: id,
                    by: translation,
                    scene: updatedScene
                )
            case let .resizeRegion(id, translation):
                updatedScene = sceneByResizingRegion(
                    id: id,
                    by: translation,
                    scene: updatedScene
                )
            }
        }
        if updatedScene.viewMode == .canvas {
            updatedScene.canvasViewport = viewport
        }
        guard updatedScene != scene else { return }
        scene = updatedScene
        updateRenderIndex(
            movedNodeHashes: movedNodeHashes,
            movedGroupIDs: movedGroupIDs
        )
        if !movedNodeHashes.isEmpty || !movedGroupIDs.isEmpty {
            pathRevision &+= 1
        }
        scheduleSceneSave()
    }

    public func fitAll(
        in screenSize: GraphSize,
        padding: Double = 48
    ) {
        guard !layout.nodes.isEmpty,
              screenSize.width.isFinite,
              screenSize.height.isFinite,
              screenSize.width > 0,
              screenSize.height > 0
        else {
            return
        }

        let safePadding = max(padding, 0)
        let availableWidth = max(screenSize.width - safePadding * 2, 1)
        let availableHeight = max(screenSize.height - safePadding * 2, 1)
        let contentWidth = max(layout.contentWidth, 1)
        let contentHeight = max(layout.contentHeight, 1)
        let scale = min(
            max(
                min(
                    availableWidth / contentWidth,
                    availableHeight / contentHeight
                ),
                CommitGraphViewportProjector.minimumScale
            ),
            CommitGraphViewportProjector.maximumScale
        )

        viewport = GraphViewport(
            offsetX: (screenSize.width - contentWidth * scale) / 2,
            offsetY: (screenSize.height - contentHeight * scale) / 2,
            scale: scale
        )
        synchronizeCanvasViewportIfNeeded()
    }

    public func resetLayout() {
        let updatedLayout = graphLayout.layout(
            page: CommitGraphPage(
                commits: commits,
                nextCursor: nextCursor
            )
        )
        let defaults = CommitGraphSceneState.defaultState(
            layout: updatedLayout
        )
        let groupedHashes = Set(
            scene.groups.flatMap(\.memberHashes)
        )
        var updatedScene = scene
        updatedScene.nodePositions = defaults.nodePositions.filter {
            !groupedHashes.contains($0.key)
        }
        updatedScene.edgePorts = defaults.edgePorts

        layout = updatedLayout
        scene = CommitGraphGrouping.rebuildingBoundaryPorts(
            layout: updatedLayout,
            scene: updatedScene
        )
        selectedHashes.formIntersection(
            Set(updatedLayout.nodes.map(\.hash))
        )
        refreshProjection(incrementingPathRevision: true)
        scheduleSceneSave()
    }

    public func focusCurrentBranch(
        canvasWidth: Double = 1_040,
        canvasHeight: Double = 680
    ) {
        guard let node = layout.nodes.first(where: {
            $0.decorations.contains {
                $0.contains("HEAD") || $0.contains("main")
            }
        }) ?? layout.nodes.first else {
            return
        }
        let position: GraphPoint
        if let group = scene.groups.first(
            where: { $0.memberHashes.contains(node.hash) }
        ) {
            if group.isCollapsed {
                let rect = CommitGraphSceneGeometry
                    .collapsedGroupRect(group)
                position = GraphPoint(
                    x: rect.midpointX,
                    y: rect.midpointY
                )
            } else {
                position = group.absolutePosition(for: node.hash)
                    ?? GraphPoint(x: node.x, y: node.y)
            }
        } else {
            position = scene.nodePositions[node.hash]
                ?? GraphPoint(x: node.x, y: node.y)
        }
        viewport.offsetX =
            canvasWidth / 2 - position.x * viewport.scale
        viewport.offsetY =
            canvasHeight / 3 - position.y * viewport.scale
        synchronizeCanvasViewportIfNeeded()
    }

    public func toggleSelection(
        hash: String,
        modifiers: CommitGraphSelectionModifiers = []
    ) {
        guard layout.node(hash: hash) != nil else { return }
        if modifiers.contains(.command) {
            if selectedHashes.contains(hash) {
                selectedHashes.remove(hash)
            } else {
                selectedHashes.insert(hash)
            }
        } else if modifiers.contains(.shift) {
            selectedHashes.insert(hash)
        } else {
            selectedHashes = [hash]
        }
    }

    public func appendSelection(hash: String) {
        toggleSelection(hash: hash, modifiers: [.shift])
    }

    public func clearCanvasSelection() {
        selectedHashes.removeAll()
    }

    public func replaceSelection(with hashes: Set<String>) {
        let availableHashes = Set(layout.nodes.map(\.hash))
        selectedHashes = hashes.intersection(availableHashes)
    }

    public func validateManualGroupSelection() throws {
        try CommitGraphGrouping.validateGroupMembership(
            selectedHashes,
            layout: layout,
            scene: scene
        )
    }

    public func group(id: UUID) -> CommitGraphGroup? {
        scene.groups.first { $0.id == id }
    }

    public func renameGroup(id: UUID, title: String) throws {
        scene = try CommitGraphGrouping.renamingGroup(
            id: id,
            title: normalizedGroupTitle(title),
            scene: scene
        )
        refreshProjection(incrementingPathRevision: false)
        scheduleSceneSave()
    }

    public func addSelectedCommits(to groupID: UUID) throws {
        guard let group = group(id: groupID) else {
            throw CommitGraphGroupingError.groupNotFound
        }
        scene = try CommitGraphGrouping.updatingGroupMembers(
            groupID: groupID,
            memberHashes: group.memberHashes.union(selectedHashes),
            layout: layout,
            scene: scene
        )
        selectedHashes.removeAll()
        refreshProjection(incrementingPathRevision: true)
        scheduleSceneSave()
    }

    public func deleteGroup(id: UUID) throws {
        scene = try CommitGraphGrouping.removingGroup(
            id: id,
            layout: layout,
            scene: scene
        )
        selectedHashes.removeAll()
        refreshProjection(incrementingPathRevision: true)
        scheduleSceneSave()
    }

    @discardableResult
    public func createManualGroup(title: String) throws -> UUID {
        let id = UUID()
        scene = try CommitGraphGrouping.creatingGroup(
            id: id,
            title: normalizedGroupTitle(title),
            memberHashes: selectedHashes,
            source: .manual,
            layout: layout,
            scene: scene
        )
        selectedHashes.removeAll()
        refreshProjection(incrementingPathRevision: true)
        scheduleSceneSave()
        return id
    }

    @discardableResult
    public func confirmGroupSuggestion(id: String) throws -> UUID {
        guard let suggestion = groupSuggestions.first(
            where: { $0.id == id }
        ) else {
            throw CommitGraphGroupingError.unknownMembers([])
        }
        let groupID = UUID()
        scene = try CommitGraphGrouping.creatingGroup(
            id: groupID,
            title: suggestion.branchName,
            memberHashes: suggestion.memberHashes,
            source: .branchSuggestion,
            layout: layout,
            scene: scene
        )
        groupSuggestions.removeAll { $0.id == id }
        refreshProjection(incrementingPathRevision: true)
        scheduleSceneSave()
        return groupID
    }

    public func prepareGroupSuggestions() async {
        guard !isPreparingGroupSuggestions else { return }
        isPreparingGroupSuggestions = true
        defer { isPreparingGroupSuggestions = false }

        while currentSnapshot == nil, nextCursor != nil {
            let previousCursor = nextCursor
            await loadOlderCommits()
            if errorMessage != nil || nextCursor == previousCursor {
                return
            }
        }
        let occupied = Set(
            scene.groups.flatMap(\.memberHashes)
        )
        groupSuggestions = CommitGraphGrouping.branchSuggestions(
            layout: layout,
            occupiedHashes: occupied
        )
    }

    public func setGroupCollapsed(id: UUID, isCollapsed: Bool) {
        guard let index = scene.groups.firstIndex(
            where: { $0.id == id }
        ) else {
            return
        }
        scene.groups[index].isCollapsed = isCollapsed
        refreshProjection(incrementingPathRevision: true)
        scheduleSceneSave()
    }

    public func region(id: UUID) -> CommitGraphRegionMarker? {
        scene.regions.first { $0.id == id }
    }

    @discardableResult
    public func createRegion(
        title: String,
        colorHex: String,
        rect: GraphRect
    ) -> UUID {
        let region = CommitGraphRegionMarker(
            title: normalizedRegionTitle(title),
            colorHex: colorHex,
            rect: rect
        )
        scene.regions.append(region)
        scheduleSceneSave()
        return region.id
    }

    public func updateRegion(
        id: UUID,
        title: String,
        colorHex: String,
        rect: GraphRect?
    ) {
        guard let index = scene.regions.firstIndex(
            where: { $0.id == id }
        ) else {
            return
        }
        scene.regions[index].title = normalizedRegionTitle(title)
        scene.regions[index].colorHex = colorHex
        if let rect {
            scene.regions[index].rect = rect
        }
        scheduleSceneSave()
    }

    public func moveRegion(id: UUID, translation: GraphPoint) {
        let updated = sceneByMovingRegion(
            id: id,
            by: translation,
            scene: scene
        )
        guard updated != scene else { return }
        scene = updated
        scheduleSceneSave()
    }

    public func resizeRegion(id: UUID, translation: GraphPoint) {
        let updated = sceneByResizingRegion(
            id: id,
            by: translation,
            scene: scene
        )
        guard updated != scene else { return }
        scene = updated
        scheduleSceneSave()
    }

    public func deleteRegion(id: UUID) {
        scene.regions.removeAll { $0.id == id }
        scheduleSceneSave()
    }

    public func moveGroup(id: UUID, by translation: GraphPoint) {
        moveGroup(
            id: id,
            by: translation,
            schedulesPersistence: true
        )
    }

    public func moveNode(hash: String, by translation: GraphPoint) {
        moveNode(
            hash: hash,
            by: translation,
            schedulesPersistence: true
        )
    }

    public func setLineStyle(_ style: CommitGraphLineStyle) {
        guard scene.lineStyle != style else { return }
        scene.lineStyle = style
        _ = renderIndex?.setLineStyle(style)
        projection = CommitGraphSceneProjection(
            nodes: projection.nodes,
            groups: projection.groups,
            edges: projection.edges,
            lineStyle: style
        )
        pathRevision &+= 1
        scheduleSceneSave()
    }

    public func persistSceneImmediately() async {
        synchronizeCanvasViewportIfNeeded()
        sceneSaveTask?.cancel()
        sceneSaveTask = nil
        await saveScene(scene)
    }

    public func select(hash: String) async {
        detailTask?.cancel()
        diffTask?.cancel()
        let requestID = UUID()
        selectionRequestID = requestID
        selectedCommit = nil
        selectedDiff = nil
        isSelectedDiffTruncated = false
        errorMessage = nil

        guard commits.contains(where: { $0.fullHash == hash }) else {
            selectedHash = nil
            errorMessage = "只能查看提交图中的提交。"
            return
        }

        selectedHash = hash
        let reader = reader
        let repositoryURL = repositoryURL
        let detailTask = Task {
            try await reader.commit(
                repositoryURL: repositoryURL,
                hash: hash
            )
        }
        let diffTask = Task {
            try await reader.diff(
                repositoryURL: repositoryURL,
                hash: hash
            )
        }
        self.detailTask = detailTask
        self.diffTask = diffTask

        do {
            let detail = try await detailTask.value
            guard selectionRequestID == requestID,
                  detail.commit.fullHash == hash
            else {
                return
            }
            selectedCommit = detail
        } catch is CancellationError {
            return
        } catch {
            guard selectionRequestID == requestID else { return }
            errorMessage = "无法读取提交详情，请稍后重试。"
            diffTask.cancel()
            return
        }

        do {
            let diff = try await diffTask.value
            guard selectionRequestID == requestID,
                  diff.commitHash == hash
            else {
                return
            }
            selectedDiff = safeDiff(diff)
        } catch is CancellationError {
            return
        } catch {
            guard selectionRequestID == requestID else { return }
            errorMessage = "提交详情已打开，但暂时无法读取差异。"
        }
    }

    public func dismissDetail() {
        detailTask?.cancel()
        diffTask?.cancel()
        selectionRequestID = UUID()
        selectedHash = nil
        selectedCommit = nil
        selectedDiff = nil
        isSelectedDiffTruncated = false
    }

    private struct DerivedSnapshotLayouts: Sendable {
        let canvas: CommitGraphLayoutResult
        let traditional: CommitGraphTraditionalLayoutResult
    }

    private func beginRefreshRequest() -> UInt64 {
        refreshRequestID &+= 1
        return refreshRequestID
    }

    private func isCurrentRefreshRequest(_ requestID: UInt64) -> Bool {
        refreshRequestID == requestID
    }

    private func deriveLayouts(
        for snapshot: CommitGraphSnapshot
    ) async -> DerivedSnapshotLayouts {
        let graphLayout = graphLayout
        let traditionalGraphLayout = traditionalGraphLayout
        return await Task.detached(priority: .userInitiated) {
            let topology = CommitGraphLaneTopology.build(snapshot: snapshot)
            return DerivedSnapshotLayouts(
                canvas: graphLayout.layout(snapshot: snapshot),
                traditional: traditionalGraphLayout.layout(
                    topology: topology
                )
            )
        }.value
    }

    private func installSnapshot(
        _ snapshot: CommitGraphSnapshot,
        integrity: CommitGraphIntegrityReport,
        derived: DerivedSnapshotLayouts,
        requestID: UInt64
    ) async -> Bool {
        var baseScene = scene
        var warningMessage = sceneWarningMessage
        if !didRestoreScene {
            if let repositoryID, let sceneStore {
                do {
                    baseScene = try await sceneStore.load(
                        repositoryID: repositoryID
                    ) ?? CommitGraphSceneState.defaultState(
                        layout: derived.canvas
                    )
                    warningMessage = nil
                } catch {
                    baseScene = CommitGraphSceneState.defaultState(
                        layout: derived.canvas
                    )
                    warningMessage = "已使用默认画布布局。"
                }
            } else {
                baseScene = CommitGraphSceneState.defaultState(
                    layout: derived.canvas
                )
            }
            guard isCurrentRefreshRequest(requestID) else { return false }
            didRestoreScene = true
        }

        let oldSnapshot = currentSnapshot ?? snapshot
        let defaultPositions = Dictionary(
            uniqueKeysWithValues: derived.canvas.nodes.map {
                ($0.hash, GraphPoint(x: $0.x, y: $0.y))
            }
        )
        var reconciled = CommitGraphSceneReconciler.reconcile(
            scene: baseScene,
            oldSnapshot: oldSnapshot,
            newSnapshot: snapshot,
            defaultPositions: defaultPositions
        )
        let provisionalProjection = CommitGraphSceneProjector.project(
            layout: derived.canvas,
            scene: reconciled
        )
        for edge in provisionalProjection.edges
            where edge.aggregateKey == nil
                && reconciled.edgePorts[edge.id] == nil {
            reconciled.edgePorts[edge.id] = edge.ports
        }
        guard isCurrentRefreshRequest(requestID) else { return false }

        let availableHashes = Set(
            snapshot.commitsNewestFirst.map(\.fullHash)
        )
        let selectedCommitDisappeared = selectedHash.map {
            !availableHashes.contains($0)
        } ?? false
        commits = snapshot.commitsNewestFirst
        currentSnapshot = snapshot
        layout = derived.canvas
        traditionalLayout = derived.traditional
        scene = reconciled
        viewport = reconciled.canvasViewport
        integrityReport = integrity
        sceneWarningMessage = warningMessage
        nextCursor = nil
        isLoadingMore = false
        selectedHashes.formIntersection(availableHashes)
        if selectedCommitDisappeared {
            detailTask?.cancel()
            diffTask?.cancel()
            selectionRequestID = UUID()
            selectedHash = nil
            selectedCommit = nil
            selectedDiff = nil
            isSelectedDiffTruncated = false
            errorMessage = "原提交已不在当前分支历史中。"
        }
        if let focusedHash, !availableHashes.contains(focusedHash) {
            self.focusedHash = nil
        }
        refreshProjection(incrementingPathRevision: true)
        scheduleSceneSave()
        return true
    }

    private func navigationFocusHash() -> String? {
        if let selectedHash,
           currentSnapshot?.commitsNewestFirst.contains(
                where: { $0.fullHash == selectedHash }
           ) == true {
            return selectedHash
        }
        if let headHash = currentSnapshot?.fingerprint.headHash,
           currentSnapshot?.commitsNewestFirst.contains(
                where: { $0.fullHash == headHash }
           ) == true {
            return headHash
        }
        return currentSnapshot?.commitsNewestFirst.first?.fullHash
    }

    private func synchronizeCanvasViewportIfNeeded() {
        guard scene.viewMode == .canvas,
              scene.canvasViewport != viewport
        else { return }
        scene.canvasViewport = viewport
        scheduleSceneSave()
    }

    private func updateRenderIndex(
        movedNodeHashes: Set<String>,
        movedGroupIDs: Set<UUID>
    ) {
        for groupID in movedGroupIDs.sorted(
            by: { $0.uuidString < $1.uuidString }
        ) {
            guard let group = scene.groups.first(
                where: { $0.id == groupID }
            ) else { continue }
            _ = renderIndex?.moveGroup(id: groupID, to: group.origin)
        }
        for hash in movedNodeHashes.sorted() {
            guard let position = currentPosition(for: hash) else { continue }
            _ = renderIndex?.moveNode(hash: hash, to: position)
        }
    }

    private func currentPosition(for hash: String) -> GraphPoint? {
        if let group = scene.groups.first(
            where: { $0.memberHashes.contains(hash) }
        ) {
            return group.absolutePosition(for: hash)
        }
        return scene.nodePositions[hash]
            ?? layout.node(hash: hash).map {
                GraphPoint(x: $0.x, y: $0.y)
            }
    }

    private func restoreOrReconcileScene() async {
        guard !didRestoreScene else {
            reconcileSceneWithLayout()
            return
        }
        didRestoreScene = true

        guard let repositoryID, let sceneStore else {
            scene = CommitGraphSceneState.defaultState(layout: layout)
            refreshProjection(incrementingPathRevision: false)
            return
        }
        do {
            scene = try await sceneStore.load(
                repositoryID: repositoryID
            ) ?? CommitGraphSceneState.defaultState(layout: layout)
            sceneWarningMessage = nil
        } catch {
            scene = CommitGraphSceneState.defaultState(layout: layout)
            sceneWarningMessage = "已使用默认画布布局。"
        }
        reconcileSceneWithLayout()
    }

    private func reconcileSceneWithLayout() {
        let defaults = CommitGraphSceneState.defaultState(layout: layout)
        let groupedHashes = Set(scene.groups.flatMap(\.memberHashes))
        for (hash, position) in defaults.nodePositions
            where !groupedHashes.contains(hash)
                && scene.nodePositions[hash] == nil {
            scene.nodePositions[hash] = position
        }
        for (edgeID, ports) in defaults.edgePorts
            where scene.edgePorts[edgeID] == nil {
            scene.edgePorts[edgeID] = ports
        }

        let previousBoundaryPorts = scene.boundaryPorts
        let rebuilt = CommitGraphGrouping.rebuildingBoundaryPorts(
            layout: layout,
            scene: scene
        )
        scene.boundaryPorts = previousBoundaryPorts.merging(
            rebuilt.boundaryPorts,
            uniquingKeysWith: { old, _ in old }
        )
        selectedHashes.formIntersection(Set(layout.nodes.map(\.hash)))
        refreshProjection(incrementingPathRevision: true)
    }

    private func moveGroup(
        id: UUID,
        by translation: GraphPoint,
        schedulesPersistence: Bool
    ) {
        let updated = CommitGraphGrouping.movingGroup(
            id: id,
            translation: translation,
            scene: scene
        )
        guard updated != scene else { return }
        scene = updated
        updateRenderIndex(
            movedNodeHashes: [],
            movedGroupIDs: [id]
        )
        pathRevision &+= 1
        if schedulesPersistence {
            scheduleSceneSave()
        }
    }

    private func moveNode(
        hash: String,
        by translation: GraphPoint,
        schedulesPersistence: Bool
    ) {
        let updated = sceneByMovingNode(
            hash: hash,
            by: translation,
            scene: scene
        )
        guard updated != scene else { return }
        scene = updated
        updateRenderIndex(
            movedNodeHashes: [hash],
            movedGroupIDs: []
        )
        pathRevision &+= 1
        if schedulesPersistence {
            scheduleSceneSave()
        }
    }

    private func sceneByMovingNode(
        hash: String,
        by translation: GraphPoint,
        scene currentScene: CommitGraphSceneState
    ) -> CommitGraphSceneState {
        guard translation.x.isFinite,
              translation.y.isFinite,
              layout.node(hash: hash) != nil
        else {
            return currentScene
        }

        var updated = currentScene
        if let groupIndex = updated.groups.firstIndex(
            where: { $0.memberHashes.contains(hash) }
        ), let position = updated.groups[groupIndex]
            .relativePositions[hash] {
            updated.groups[groupIndex].relativePositions[hash] = GraphPoint(
                x: position.x + translation.x,
                y: position.y + translation.y
            )
        } else {
            let position = updated.nodePositions[hash]
                ?? layout.node(hash: hash).map {
                    GraphPoint(x: $0.x, y: $0.y)
                }
                ?? .zero
            updated.nodePositions[hash] = GraphPoint(
                x: position.x + translation.x,
                y: position.y + translation.y
            )
        }
        return updated
    }

    private func sceneByMovingRegion(
        id: UUID,
        by translation: GraphPoint,
        scene currentScene: CommitGraphSceneState
    ) -> CommitGraphSceneState {
        guard translation.x.isFinite,
              translation.y.isFinite,
              let index = currentScene.regions.firstIndex(
                where: { $0.id == id }
              )
        else {
            return currentScene
        }
        var updated = currentScene
        let rect = updated.regions[index].rect
        updated.regions[index].rect = GraphRect(
            x: rect.x + translation.x,
            y: rect.y + translation.y,
            width: rect.width,
            height: rect.height
        )
        return updated
    }

    private func sceneByResizingRegion(
        id: UUID,
        by translation: GraphPoint,
        scene currentScene: CommitGraphSceneState
    ) -> CommitGraphSceneState {
        guard translation.x.isFinite,
              translation.y.isFinite,
              let index = currentScene.regions.firstIndex(
                where: { $0.id == id }
              )
        else {
            return currentScene
        }
        var updated = currentScene
        let rect = updated.regions[index].rect
        updated.regions[index].rect = GraphRect(
            x: rect.x,
            y: rect.y,
            width: max(rect.width + translation.x, 120),
            height: max(rect.height + translation.y, 90)
        )
        return updated
    }

    private func refreshProjection(incrementingPathRevision: Bool) {
        projection = CommitGraphSceneProjector.project(
            layout: layout,
            scene: scene
        )
        renderIndex = CommitGraphRenderIndex(projection: projection)
        if incrementingPathRevision {
            pathRevision &+= 1
        }
    }

    private func scheduleSceneSave() {
        guard sceneStore != nil, repositoryID != nil else { return }
        let snapshot = scene
        sceneSaveTask?.cancel()
        sceneSaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await self?.saveScene(snapshot)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func saveScene(_ snapshot: CommitGraphSceneState) async {
        guard let repositoryID, let sceneStore else { return }
        do {
            try await sceneStore.save(
                snapshot,
                repositoryID: repositoryID
            )
            sceneWarningMessage = nil
        } catch {
            sceneWarningMessage = "画布布局暂时无法保存。"
        }
    }

    private func normalizedGroupTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? "提交分组" : String(trimmed.prefix(80))
    }

    private func normalizedRegionTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? "版本区域" : String(trimmed.prefix(80))
    }

    private func uniqueCommits(_ values: [GitCommit]) -> [GitCommit] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.fullHash).inserted }
    }

    private func safeDiff(_ diff: GitDiff) -> GitDiff {
        let plainPatch = diff.patch.replacingOccurrences(
            of: "\0",
            with: "\u{FFFD}"
        )
        let truncated = plainPatch.count > maximumPatchCharacters
        isSelectedDiffTruncated = truncated
        return GitDiff(
            commitHash: diff.commitHash,
            files: diff.files,
            patch: String(plainPatch.prefix(maximumPatchCharacters)),
            additions: diff.additions,
            deletions: diff.deletions
        )
    }
}
