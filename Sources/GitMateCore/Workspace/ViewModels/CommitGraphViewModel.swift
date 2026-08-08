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

public struct CommitGraphGitDerivationRequest: Sendable {
    public let snapshot: CommitGraphSnapshot
    public let integrityReport: CommitGraphIntegrityReport?

    public init(
        snapshot: CommitGraphSnapshot,
        integrityReport: CommitGraphIntegrityReport? = nil
    ) {
        self.snapshot = snapshot
        self.integrityReport = integrityReport
    }
}

public struct CommitGraphGitDerivedBase: Sendable {
    public let integrityReport: CommitGraphIntegrityReport
    public let canvasLayout: CommitGraphLayoutResult
    public let traditionalLayout: CommitGraphTraditionalLayoutResult
    public let defaultPositions: [String: GraphPoint]
    public let availableHashes: Set<String>

    public init(
        integrityReport: CommitGraphIntegrityReport,
        canvasLayout: CommitGraphLayoutResult,
        traditionalLayout: CommitGraphTraditionalLayoutResult,
        defaultPositions: [String: GraphPoint],
        availableHashes: Set<String>
    ) {
        self.integrityReport = integrityReport
        self.canvasLayout = canvasLayout
        self.traditionalLayout = traditionalLayout
        self.defaultPositions = defaultPositions
        self.availableHashes = availableHashes
    }
}

public struct CommitGraphSceneDerivationRequest: Sendable {
    public let snapshot: CommitGraphSnapshot
    public let previousSnapshot: CommitGraphSnapshot?
    public let scene: CommitGraphSceneState
    public let base: CommitGraphGitDerivedBase

    public init(
        snapshot: CommitGraphSnapshot,
        previousSnapshot: CommitGraphSnapshot?,
        scene: CommitGraphSceneState,
        base: CommitGraphGitDerivedBase
    ) {
        self.snapshot = snapshot
        self.previousSnapshot = previousSnapshot
        self.scene = scene
        self.base = base
    }
}

public struct CommitGraphSceneDerivedState: Sendable {
    public let scene: CommitGraphSceneState
    public let projection: CommitGraphSceneProjection
    public let renderIndex: CommitGraphRenderIndex

    public init(
        scene: CommitGraphSceneState,
        projection: CommitGraphSceneProjection,
        renderIndex: CommitGraphRenderIndex
    ) {
        self.scene = scene
        self.projection = projection
        self.renderIndex = renderIndex
    }
}

public protocol CommitGraphViewModelDeriving: Sendable {
    func deriveGitBase(
        _ request: CommitGraphGitDerivationRequest
    ) async throws -> CommitGraphGitDerivedBase

    func deriveScene(
        _ request: CommitGraphSceneDerivationRequest
    ) async throws -> CommitGraphSceneDerivedState
}

public struct DefaultCommitGraphViewModelDeriver:
    CommitGraphViewModelDeriving,
    Sendable
{
    private let graphLayout: CommitGraphLayout
    private let traditionalLayout: CommitGraphTraditionalLayout

    public init(
        graphLayout: CommitGraphLayout = CommitGraphLayout(),
        traditionalLayout: CommitGraphTraditionalLayout =
            CommitGraphTraditionalLayout()
    ) {
        self.graphLayout = graphLayout
        self.traditionalLayout = traditionalLayout
    }

    public func deriveGitBase(
        _ request: CommitGraphGitDerivationRequest
    ) async throws -> CommitGraphGitDerivedBase {
        let graphLayout = graphLayout
        let traditionalLayout = traditionalLayout
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let integrity = request.integrityReport
                ?? CommitGraphIntegrityValidator.validate(request.snapshot)
            try Task.checkCancellation()
            guard integrity.status != .invalid else {
                return CommitGraphGitDerivedBase(
                    integrityReport: integrity,
                    canvasLayout: CommitGraphLayoutResult(),
                    traditionalLayout: CommitGraphTraditionalLayoutResult(
                        rows: [],
                        maximumLane: 0
                    ),
                    defaultPositions: [:],
                    availableHashes: []
                )
            }

            let topology = CommitGraphLaneTopology.build(
                snapshot: request.snapshot
            )
            try Task.checkCancellation()
            let canvas = graphLayout.layout(topology: topology)
            try Task.checkCancellation()
            let traditional = traditionalLayout.layout(topology: topology)
            try Task.checkCancellation()
            let defaultPositions = Dictionary(
                uniqueKeysWithValues: canvas.nodes.map {
                    ($0.hash, GraphPoint(x: $0.x, y: $0.y))
                }
            )
            let availableHashes = Set(
                request.snapshot.commitsNewestFirst.map(\.fullHash)
            )
            try Task.checkCancellation()
            return CommitGraphGitDerivedBase(
                integrityReport: integrity,
                canvasLayout: canvas,
                traditionalLayout: traditional,
                defaultPositions: defaultPositions,
                availableHashes: availableHashes
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    public func deriveScene(
        _ request: CommitGraphSceneDerivationRequest
    ) async throws -> CommitGraphSceneDerivedState {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            var reconciled = CommitGraphSceneReconciler.reconcile(
                scene: request.scene,
                oldSnapshot: request.previousSnapshot ?? request.snapshot,
                newSnapshot: request.snapshot,
                defaultPositions: request.base.defaultPositions
            )
            try Task.checkCancellation()
            let provisionalProjection = CommitGraphSceneProjector.project(
                layout: request.base.canvasLayout,
                scene: reconciled
            )
            for edge in provisionalProjection.edges
                where edge.aggregateKey == nil
                    && reconciled.edgePorts[edge.id] == nil {
                reconciled.edgePorts[edge.id] = edge.ports
            }
            try Task.checkCancellation()
            let projection = CommitGraphSceneProjector.project(
                layout: request.base.canvasLayout,
                scene: reconciled
            )
            try Task.checkCancellation()
            let renderIndex = CommitGraphRenderIndex(projection: projection)
            try Task.checkCancellation()
            return CommitGraphSceneDerivedState(
                scene: reconciled,
                projection: projection,
                renderIndex: renderIndex
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

private enum CommitGraphScenePersistenceState: Sendable {
    case restoring
    case writable
    case readOnlyFutureSchema
}

private struct CommitGraphHistoryBinCacheKey: Hashable {
    let pixelHeight: Int
    let revision: UInt64
}

@MainActor
@Observable
public final class CommitGraphViewModel {
    public var viewport = GraphViewport() {
        didSet {
            guard viewport != oldValue,
                  scene.viewMode == .canvas,
                  scene.canvasViewport != viewport
            else { return }
            scene.canvasViewport = viewport
            recordSceneMutation()
            scheduleSceneSave()
        }
    }
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
    public private(set) var selectedHash: String? {
        didSet {
            guard selectedHash != oldValue else { return }
            rebuildSelectionHighlight()
        }
    }
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var nextCursor: String?
    public private(set) var errorMessage: String?
    public private(set) var traditionalLayout =
        CommitGraphTraditionalLayoutResult(rows: [], maximumLane: 0)
    public private(set) var traditionalGroupBadgeByHash:
        [String: CommitGraphTraditionalGroupBadge] = [:]
    public private(set) var traditionalGroupRevision: UInt64 = 0
    public private(set) var integrityReport: CommitGraphIntegrityReport?
    public private(set) var refreshState: CommitGraphRefreshState = .idle
    public private(set) var focusedHash: String?
    public private(set) var historyMarkers: [CommitGraphHistoryMarker] = []
    public private(set) var historyMarkerRevision: UInt64 = 0
    public private(set) var highlightedEdgeIDs: Set<String> = []
    public private(set) var highlightedNodeHashes: Set<String> = []

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
    private let deriver: any CommitGraphViewModelDeriving

    @ObservationIgnored
    private let pageSize: Int

    @ObservationIgnored
    private let maximumPatchCharacters: Int

    @ObservationIgnored
    private let graphLayout: CommitGraphLayout

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
    private var installedSnapshotIdentity: CommitGraphSnapshotIdentity?

    @ObservationIgnored
    private var renderIndex: CommitGraphRenderIndex?

    @ObservationIgnored
    private var historyMarkerBinCache:
        [CommitGraphHistoryBinCacheKey: [CommitGraphHistoryMarkerBin]] = [:]

    @ObservationIgnored
    private var historyMarkersNeedRebuild = false

    @ObservationIgnored
    private var refreshRequestID: UInt64 = 0

    @ObservationIgnored
    private var sceneRevision: UInt64 = 0

    @ObservationIgnored
    private var scenePersistenceState: CommitGraphScenePersistenceState =
        .restoring

    @ObservationIgnored
    private var baseDerivationTask:
        Task<CommitGraphGitDerivedBase, Error>?

    @ObservationIgnored
    private var sceneDerivationTask:
        Task<CommitGraphSceneDerivedState, Error>?

    @ObservationIgnored
    private var initialCacheLoadTask: Task<Bool, Never>?

    @ObservationIgnored
    private var initialCacheLoadID: UUID?

    @ObservationIgnored
    private var didCompleteInitialCacheLoad = false

    @ObservationIgnored
    private var initialPresentationLeases: Set<UUID> = []

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
            CommitGraphTraditionalLayout(),
        deriver: (any CommitGraphViewModelDeriving)? = nil
    ) {
        self.reader = reader
        self.repositoryURL = repositoryURL
        self.repositoryID = repositoryID
        self.sceneStore = sceneStore
        self.refreshCoordinator = refreshCoordinator
        self.deriver = deriver ?? DefaultCommitGraphViewModelDeriver(
            graphLayout: layout,
            traditionalLayout: traditionalLayout
        )
        self.pageSize = min(max(pageSize, 1), 200)
        self.maximumPatchCharacters = max(maximumPatchCharacters, 1)
        graphLayout = layout
    }

    @discardableResult
    public func loadCachedSnapshot() async -> Bool {
        guard let repositoryID, let refreshCoordinator else {
            await load()
            return !Task.isCancelled
        }
        let requestID = beginRefreshRequest()
        isLoading = currentSnapshot == nil
        defer { finishRefreshRequest(requestID) }
        let loadedScene = await loadSceneForDerivation()
        guard adoptLoadedScene(
            loadedScene,
            requestID: requestID
        ) else { return false }
        do {
            guard let snapshot = try await refreshCoordinator.cachedSnapshot(
                repositoryID: repositoryID,
                repositoryURL: repositoryURL
            ) else {
                guard isCurrentRefreshRequest(requestID) else { return false }
                refreshState = currentSnapshot == nil
                    ? .idle
                    : .stale(message: "本地缓存缺失，继续显示上次正确结果。")
                return true
            }
            guard let base = try await deriveGitBase(
                snapshot: snapshot,
                integrityReport: nil,
                requestID: requestID
            ) else { return false }
            guard base.integrityReport.status != .invalid else {
                integrityReport = base.integrityReport
                refreshState = currentSnapshot == nil
                    ? .failed(message: "本地提交图缓存已损坏。")
                    : .stale(message: "本地缓存损坏，继续显示上次正确结果。")
                return false
            }
            guard let derived = try await deriveLatestScene(
                snapshot: snapshot,
                base: base,
                requestID: requestID
            ) else { return false }
            guard installDerivedState(
                snapshot,
                base: base,
                derived: derived.state,
                expectedSceneRevision: derived.sceneRevision,
                requestID: requestID
            ) else { return false }
            refreshState = .stale(message: "正在显示上次正确结果。")
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard isCurrentRefreshRequest(requestID) else { return false }
            refreshState = currentSnapshot == nil
                ? .failed(message: "本地提交图缓存已损坏。")
                : .stale(message: "本地缓存损坏，继续显示上次正确结果。")
            return false
        }
    }

    /// 页面进入时取得稳定租约。该租约与单次刷新任务分离，避免 revision
    /// 变化取消旧任务时错误终止仍在显示的缓存读取。
    @discardableResult
    public func beginInitialPresentation() -> UUID {
        let leaseID = UUID()
        initialPresentationLeases.insert(leaseID)
        startInitialCacheLoadForPresentationIfNeeded()
        return leaseID
    }

    /// 页面离开时归还稳定租约；最后一个页面离开才终止可取消的缓存和派生。
    public func endInitialPresentation(_ leaseID: UUID) {
        guard initialPresentationLeases.remove(leaseID) != nil,
              initialPresentationLeases.isEmpty
        else { return }

        cancelInitialPresentationWork()
    }

    /// revision 任务只协调“缓存优先后刷新”，不会取得或释放页面呈现租约。
    public func refreshForPresentationRevision(
        source: CommitGraphRefreshSource
    ) async {
        guard !initialPresentationLeases.isEmpty else { return }
        await loadCachedSnapshotForPresentation()
        guard !Task.isCancelled,
              !initialPresentationLeases.isEmpty
        else { return }
        await refresh(source: source)
    }

    private func cancelInitialPresentationWork() {
        initialCacheLoadTask?.cancel()
        initialCacheLoadTask = nil
        initialCacheLoadID = nil
        baseDerivationTask?.cancel()
        sceneDerivationTask?.cancel()
        baseDerivationTask = nil
        sceneDerivationTask = nil
        refreshRequestID &+= 1
        isLoading = false
        isLoadingMore = false
    }

    private func startInitialCacheLoadForPresentationIfNeeded() {
        guard !didCompleteInitialCacheLoad,
              initialCacheLoadTask == nil
        else { return }

        let loadID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.loadCachedSnapshot()
        }
        initialCacheLoadTask = task
        initialCacheLoadID = loadID
    }

    private func loadCachedSnapshotForPresentation() async {
        guard !didCompleteInitialCacheLoad else { return }
        startInitialCacheLoadForPresentationIfNeeded()
        guard let task = initialCacheLoadTask,
              let loadID = initialCacheLoadID
        else { return }

        let didLoad = await task.value
        guard !Task.isCancelled,
              !initialPresentationLeases.isEmpty,
              initialCacheLoadID == loadID
        else { return }
        initialCacheLoadTask = nil
        initialCacheLoadID = nil
        didCompleteInitialCacheLoad = didLoad
        if !didLoad {
            // 失败或取消不应消耗首次缓存机会；下一次呈现可以重新尝试。
            return
        }
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
        defer { finishRefreshRequest(requestID) }
        errorMessage = nil

        do {
            let loadedScene = await loadSceneForDerivation()
            guard adoptLoadedScene(
                loadedScene,
                requestID: requestID
            ) else { return }
            let result = try await refreshCoordinator.refresh(
                repositoryID: repositoryID,
                repositoryURL: repositoryURL
            )
            guard isCurrentRefreshRequest(requestID) else { return }
            let resultIdentity = CommitGraphSnapshotIdentity(result.snapshot)
            if installedSnapshotIdentity != resultIdentity {
                guard let base = try await deriveGitBase(
                    snapshot: result.snapshot,
                    integrityReport: result.integrity,
                    requestID: requestID
                ) else { return }
                guard let derived = try await deriveLatestScene(
                    snapshot: result.snapshot,
                    base: base,
                    requestID: requestID
                ) else { return }
                guard installDerivedState(
                    result.snapshot,
                    base: base,
                    derived: derived.state,
                    expectedSceneRevision: derived.sceneRevision,
                    requestID: requestID
                ) else { return }
            } else {
                integrityReport = result.integrity
            }
            guard isCurrentRefreshRequest(requestID) else { return }
            refreshState = .current(result.refreshedAt)
        } catch is CancellationError {
            guard isCurrentRefreshRequest(requestID) else { return }
            refreshState = currentSnapshot == nil
                ? .idle
                : .stale(message: "刷新已取消，显示上次正确结果。")
        } catch {
            guard isCurrentRefreshRequest(requestID) else { return }
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
        recordSceneMutation()
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

    public var historyCommitCount: Int {
        traditionalLayout.rows.count
    }

    public func historyRow(hash: String?) -> Int? {
        guard let hash else { return nil }
        return layout.node(hash: hash)?.row
    }

    public func hashAtHistoryProgress(_ progress: Double) -> String? {
        guard !layout.nodes.isEmpty else { return nil }
        let row = CommitGraphHistoryNavigation.row(
            progress: progress,
            count: layout.nodes.count
        )
        guard layout.nodes.indices.contains(row) else {
            return nil
        }
        return layout.nodes[row].hash
    }

    public func historyMarkerBins(
        pixelHeight: Double
    ) -> [CommitGraphHistoryMarkerBin] {
        let height = max(Int(pixelHeight.rounded()), 1)
        let key = CommitGraphHistoryBinCacheKey(
            pixelHeight: height,
            revision: historyMarkerRevision
        )
        if let cached = historyMarkerBinCache[key] { return cached }
        let bins = CommitGraphHistoryNavigation.binnedMarkers(
            historyMarkers,
            count: historyCommitCount,
            pixelHeight: height
        )
        historyMarkerBinCache[key] = bins
        return bins
    }

    public func historyViewportRange(
        screenHeight: Double
    ) -> CommitGraphHistoryViewportRange {
        CommitGraphHistoryNavigation.viewportRange(
            viewport: viewport,
            screenHeight: screenHeight,
            minimumY: 0,
            maximumY: max(layout.contentHeight, 1)
        )
    }

    public func setHistoryViewportProgress(
        _ progress: Double,
        screenHeight: Double
    ) {
        viewport = CommitGraphHistoryNavigation.viewportCentered(
            at: progress,
            viewport: viewport,
            screenHeight: screenHeight,
            minimumY: 0,
            maximumY: max(layout.contentHeight, 1)
        )
        synchronizeCanvasViewportIfNeeded()
    }

    public func hitTest(
        canvasPoint: GraphPoint
    ) -> CommitGraphRenderHit? {
        renderIndex?.hitTest(canvasPoint: canvasPoint)
    }

    @discardableResult
    public func navigateToFirstMatch(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalized.isEmpty else { return false }
        let matchingReferenceTargets = Set(
            currentSnapshot?.fingerprint.references.compactMap { reference in
                reference.name.localizedCaseInsensitiveContains(normalized)
                    ? reference.targetHash
                    : nil
            } ?? []
        )
        let match = commits.first { commit in
            commit.fullHash.localizedCaseInsensitiveContains(normalized)
                || commit.shortHash.localizedCaseInsensitiveContains(normalized)
                || commit.subject.localizedCaseInsensitiveContains(normalized)
                || commit.authorName.localizedCaseInsensitiveContains(normalized)
                || commit.decorations.contains {
                    $0.localizedCaseInsensitiveContains(normalized)
                }
                || matchingReferenceTargets.contains(commit.fullHash)
        }
        guard let match else { return false }
        selectForNavigation(hash: match.fullHash)
        return true
    }

    public func focusCommit(
        hash: String,
        in screenSize: GraphSize
    ) {
        guard layout.node(hash: hash) != nil else { return }
        let position: GraphPoint
        if let group = scene.groups.first(
            where: { $0.memberHashes.contains(hash) }
        ) {
            if group.isCollapsed {
                let rect = CommitGraphSceneGeometry
                    .collapsedGroupRect(group)
                position = GraphPoint(
                    x: rect.midpointX,
                    y: rect.midpointY
                )
            } else {
                position = group.absolutePosition(for: hash)
                    ?? currentPosition(for: hash)
                    ?? .zero
            }
        } else {
            position = currentPosition(for: hash) ?? .zero
        }
        viewport.offsetX = screenSize.width * 0.5
            - position.x * viewport.scale
        viewport.offsetY = screenSize.height * 0.42
            - position.y * viewport.scale
        synchronizeCanvasViewportIfNeeded()
    }

    public func refreshHistoryNavigationMarkers() {
        rebuildHistoryNavigationMarkers()
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
        var didMoveHistoryGeometry = false
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
                didMoveHistoryGeometry = true
            case let .moveGroup(id, translation):
                updatedScene = CommitGraphGrouping.movingGroup(
                    id: id,
                    translation: translation,
                    scene: updatedScene
                )
                movedGroupIDs.insert(id)
                didMoveHistoryGeometry = true
            case let .moveRegion(id, translation):
                updatedScene = sceneByMovingRegion(
                    id: id,
                    by: translation,
                    scene: updatedScene
                )
                didMoveHistoryGeometry = true
            case let .resizeRegion(id, translation):
                updatedScene = sceneByResizingRegion(
                    id: id,
                    by: translation,
                    scene: updatedScene
                )
                didMoveHistoryGeometry = true
            }
        }
        if updatedScene.viewMode == .canvas {
            updatedScene.canvasViewport = viewport
        }
        guard updatedScene != scene else { return }
        scene = updatedScene
        historyMarkersNeedRebuild = historyMarkersNeedRebuild
            || didMoveHistoryGeometry
        syncRenderRegions()
        updateRenderIndex(
            movedNodeHashes: movedNodeHashes,
            movedGroupIDs: movedGroupIDs
        )
        if !movedNodeHashes.isEmpty || !movedGroupIDs.isEmpty {
            pathRevision &+= 1
        }
        recordSceneMutation()
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
        let requestedScale = min(
            availableWidth / contentWidth,
            availableHeight / contentHeight
        )
        let scale = min(
            max(requestedScale, CommitGraphViewportProjector.minimumScale),
            CommitGraphViewportProjector.maximumScale
        )
        let cannotFitEntireHistory = requestedScale
            < CommitGraphViewportProjector.minimumScale
        let latestHash = currentSnapshot?.commitsNewestFirst.first?.fullHash
            ?? layout.nodes.last?.hash
        let latestPosition = latestHash.flatMap(currentPosition(for:))

        viewport = GraphViewport(
            offsetX: (screenSize.width - contentWidth * scale) / 2,
            offsetY: cannotFitEntireHistory
                ? latestPosition.map {
                    screenSize.height / 2 - $0.y * scale
                } ?? safePadding
                : (screenSize.height - contentHeight * scale) / 2,
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
        recordSceneMutation()
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
        rebuildTraditionalGroupBadgeIndex()
        refreshProjection(incrementingPathRevision: false)
        recordSceneMutation()
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
        rebuildTraditionalGroupBadgeIndex()
        selectedHashes.removeAll()
        refreshProjection(incrementingPathRevision: true)
        recordSceneMutation()
        scheduleSceneSave()
    }

    public func deleteGroup(id: UUID) throws {
        scene = try CommitGraphGrouping.removingGroup(
            id: id,
            layout: layout,
            scene: scene
        )
        rebuildTraditionalGroupBadgeIndex()
        selectedHashes.removeAll()
        refreshProjection(incrementingPathRevision: true)
        recordSceneMutation()
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
        rebuildTraditionalGroupBadgeIndex()
        selectedHashes.removeAll()
        refreshProjection(incrementingPathRevision: true)
        recordSceneMutation()
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
        rebuildTraditionalGroupBadgeIndex()
        groupSuggestions.removeAll { $0.id == id }
        refreshProjection(incrementingPathRevision: true)
        recordSceneMutation()
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
        guard scene.groups[index].isCollapsed != isCollapsed else { return }
        scene.groups[index].isCollapsed = isCollapsed
        rebuildTraditionalGroupBadgeIndex()
        refreshProjection(incrementingPathRevision: true)
        recordSceneMutation()
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
        syncRenderRegions()
        rebuildHistoryNavigationMarkers()
        recordSceneMutation()
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
        syncRenderRegions()
        rebuildHistoryNavigationMarkers()
        recordSceneMutation()
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
        syncRenderRegions()
        historyMarkersNeedRebuild = true
        recordSceneMutation()
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
        syncRenderRegions()
        historyMarkersNeedRebuild = true
        recordSceneMutation()
        scheduleSceneSave()
    }

    public func deleteRegion(id: UUID) {
        guard scene.regions.contains(where: { $0.id == id }) else { return }
        scene.regions.removeAll { $0.id == id }
        syncRenderRegions()
        rebuildHistoryNavigationMarkers()
        recordSceneMutation()
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
        recordSceneMutation()
        scheduleSceneSave()
    }

    public func persistSceneImmediately() async {
        synchronizeCanvasViewportIfNeeded()
        if historyMarkersNeedRebuild {
            rebuildHistoryNavigationMarkers()
        }
        sceneSaveTask?.cancel()
        sceneSaveTask = nil
        guard scenePersistenceState == .writable else { return }
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

    private struct LoadedScene: Sendable {
        let scene: CommitGraphSceneState
        let warningMessage: String?
        let persistenceState: CommitGraphScenePersistenceState
    }

    private struct RevisionMatchedDerivedState: Sendable {
        let state: CommitGraphSceneDerivedState
        let sceneRevision: UInt64
    }

    private func beginRefreshRequest() -> UInt64 {
        baseDerivationTask?.cancel()
        sceneDerivationTask?.cancel()
        baseDerivationTask = nil
        sceneDerivationTask = nil
        refreshRequestID &+= 1
        return refreshRequestID
    }

    private func isCurrentRefreshRequest(_ requestID: UInt64) -> Bool {
        refreshRequestID == requestID
    }

    private func finishRefreshRequest(_ requestID: UInt64) {
        guard isCurrentRefreshRequest(requestID) else { return }
        baseDerivationTask = nil
        sceneDerivationTask = nil
        isLoading = false
        isLoadingMore = false
    }

    private func loadSceneForDerivation() async -> LoadedScene {
        if didRestoreScene {
            return LoadedScene(
                scene: scene,
                warningMessage: sceneWarningMessage,
                persistenceState: scenePersistenceState
            )
        }
        guard let repositoryID, let sceneStore else {
            return LoadedScene(
                scene: CommitGraphSceneState(),
                warningMessage: nil,
                persistenceState: .writable
            )
        }
        do {
            return LoadedScene(
                scene: try await sceneStore.load(
                    repositoryID: repositoryID
                ) ?? CommitGraphSceneState(),
                warningMessage: nil,
                persistenceState: .writable
            )
        } catch let error as CommitGraphSceneStoreError {
            if case .unsupportedSchema = error {
                return LoadedScene(
                    scene: CommitGraphSceneState(),
                    warningMessage: "检测到较新版本的画布数据，当前仅以只读默认布局显示。",
                    persistenceState: .readOnlyFutureSchema
                )
            }
            return LoadedScene(
                scene: CommitGraphSceneState(),
                warningMessage: "已使用默认画布布局。",
                persistenceState: .writable
            )
        } catch {
            return LoadedScene(
                scene: CommitGraphSceneState(),
                warningMessage: "已使用默认画布布局。",
                persistenceState: .writable
            )
        }
    }

    private func adoptLoadedScene(
        _ loadedScene: LoadedScene,
        requestID: UInt64
    ) -> Bool {
        guard isCurrentRefreshRequest(requestID) else { return false }
        if !didRestoreScene {
            scene = loadedScene.scene
            rebuildTraditionalGroupBadgeIndex()
            sceneWarningMessage = loadedScene.warningMessage
            scenePersistenceState = loadedScene.persistenceState
            viewport = loadedScene.scene.canvasViewport
            didRestoreScene = true
            sceneRevision &+= 1
        }
        return true
    }

    private func deriveGitBase(
        snapshot: CommitGraphSnapshot,
        integrityReport: CommitGraphIntegrityReport?,
        requestID: UInt64
    ) async throws -> CommitGraphGitDerivedBase? {
        guard isCurrentRefreshRequest(requestID) else { return nil }
        let request = CommitGraphGitDerivationRequest(
            snapshot: snapshot,
            integrityReport: integrityReport
        )
        let deriver = deriver
        let task = Task {
            try await deriver.deriveGitBase(request)
        }
        baseDerivationTask?.cancel()
        baseDerivationTask = task
        let base = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        guard isCurrentRefreshRequest(requestID) else { return nil }
        baseDerivationTask = nil
        return base
    }

    private func deriveLatestScene(
        snapshot: CommitGraphSnapshot,
        base: CommitGraphGitDerivedBase,
        requestID: UInt64
    ) async throws -> RevisionMatchedDerivedState? {
        while isCurrentRefreshRequest(requestID) {
            try Task.checkCancellation()
            let revision = sceneRevision
            let request = CommitGraphSceneDerivationRequest(
                snapshot: snapshot,
                previousSnapshot: currentSnapshot,
                scene: scene,
                base: base
            )
            let deriver = deriver
            let task = Task {
                try await deriver.deriveScene(request)
            }
            sceneDerivationTask?.cancel()
            sceneDerivationTask = task
            let state: CommitGraphSceneDerivedState
            do {
                state = try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: {
                    task.cancel()
                }
            } catch is CancellationError {
                guard isCurrentRefreshRequest(requestID) else { return nil }
                if sceneRevision != revision {
                    continue
                }
                throw CancellationError()
            }
            guard isCurrentRefreshRequest(requestID) else { return nil }
            guard sceneRevision == revision else {
                continue
            }
            sceneDerivationTask = nil
            return RevisionMatchedDerivedState(
                state: state,
                sceneRevision: revision
            )
        }
        return nil
    }

    private func installDerivedState(
        _ snapshot: CommitGraphSnapshot,
        base: CommitGraphGitDerivedBase,
        derived: CommitGraphSceneDerivedState,
        expectedSceneRevision: UInt64,
        requestID: UInt64
    ) -> Bool {
        guard isCurrentRefreshRequest(requestID),
              sceneRevision == expectedSceneRevision
        else { return false }

        let availableHashes = base.availableHashes
        let selectedCommitDisappeared = selectedHash.map {
            !availableHashes.contains($0)
        } ?? false
        commits = snapshot.commitsNewestFirst
        currentSnapshot = snapshot
        installedSnapshotIdentity = CommitGraphSnapshotIdentity(snapshot)
        layout = base.canvasLayout
        traditionalLayout = base.traditionalLayout
        scene = derived.scene
        rebuildTraditionalGroupBadgeIndex()
        rebuildHistoryNavigationMarkers()
        viewport = derived.scene.canvasViewport
        integrityReport = base.integrityReport
        projection = derived.projection
        renderIndex = derived.renderIndex
        rebuildSelectionHighlight()
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
        pathRevision &+= 1
        recordSceneMutation()
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
        recordSceneMutation()
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

    private func syncRenderRegions() {
        renderIndex?.syncRegions(scene.regions)
        projection = CommitGraphSceneProjection(
            nodes: projection.nodes,
            groups: projection.groups,
            regions: scene.regions,
            shallowBoundaryEndpoints: projection.shallowBoundaryEndpoints,
            edges: projection.edges,
            lineStyle: projection.lineStyle
        )
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
            scenePersistenceState = .writable
            scene = CommitGraphSceneState.defaultState(layout: layout)
            rebuildTraditionalGroupBadgeIndex()
            refreshProjection(incrementingPathRevision: false)
            return
        }
        do {
            scene = try await sceneStore.load(
                repositoryID: repositoryID
            ) ?? CommitGraphSceneState.defaultState(layout: layout)
            sceneWarningMessage = nil
            scenePersistenceState = .writable
        } catch let error as CommitGraphSceneStoreError {
            scene = CommitGraphSceneState.defaultState(layout: layout)
            if case .unsupportedSchema = error {
                sceneWarningMessage =
                    "检测到较新版本的画布数据，当前仅以只读默认布局显示。"
                scenePersistenceState = .readOnlyFutureSchema
            } else {
                sceneWarningMessage = "已使用默认画布布局。"
                scenePersistenceState = .writable
            }
        } catch {
            scene = CommitGraphSceneState.defaultState(layout: layout)
            sceneWarningMessage = "已使用默认画布布局。"
            scenePersistenceState = .writable
        }
        rebuildTraditionalGroupBadgeIndex()
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
        historyMarkersNeedRebuild = true
        updateRenderIndex(
            movedNodeHashes: [],
            movedGroupIDs: [id]
        )
        pathRevision &+= 1
        recordSceneMutation()
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
        historyMarkersNeedRebuild = true
        updateRenderIndex(
            movedNodeHashes: [hash],
            movedGroupIDs: []
        )
        pathRevision &+= 1
        recordSceneMutation()
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
        rebuildSelectionHighlight()
        rebuildHistoryNavigationMarkers()
        if incrementingPathRevision {
            pathRevision &+= 1
        }
    }

    private func rebuildTraditionalGroupBadgeIndex() {
        var rebuilt: [String: CommitGraphTraditionalGroupBadge] = [:]
        rebuilt.reserveCapacity(
            scene.groups.reduce(0) { $0 + $1.memberHashes.count }
        )
        for group in scene.groups {
            let badge = CommitGraphTraditionalGroupBadge(
                title: group.title,
                isCollapsed: group.isCollapsed,
                groupID: group.id
            )
            for hash in group.memberHashes {
                rebuilt[hash] = badge
            }
        }
        traditionalGroupBadgeByHash = rebuilt
        traditionalGroupRevision &+= 1
    }

    private func rebuildHistoryNavigationMarkers() {
        historyMarkers = CommitGraphHistoryNavigation.markers(
            traditionalLayout: traditionalLayout,
            canvasLayout: layout,
            scene: scene
        )
        historyMarkerBinCache.removeAll(keepingCapacity: true)
        historyMarkerRevision &+= 1
        historyMarkersNeedRebuild = false
    }

    private func rebuildSelectionHighlight() {
        guard let selectedHash, let renderIndex else {
            highlightedEdgeIDs.removeAll(keepingCapacity: true)
            highlightedNodeHashes.removeAll(keepingCapacity: true)
            return
        }
        highlightedEdgeIDs = renderIndex.highlightedEdgeIDs(
            for: selectedHash
        )
        highlightedNodeHashes = renderIndex.highlightedNodeHashes(
            for: selectedHash
        )
    }

    private func recordSceneMutation() {
        sceneRevision &+= 1
        sceneDerivationTask?.cancel()
    }

    private func scheduleSceneSave() {
        guard scenePersistenceState == .writable,
              sceneStore != nil,
              repositoryID != nil
        else { return }
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
        guard scenePersistenceState == .writable,
              let repositoryID,
              let sceneStore
        else { return }
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
