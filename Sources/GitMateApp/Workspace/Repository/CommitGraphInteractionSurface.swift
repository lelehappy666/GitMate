import AppKit
import GitMateCore
import QuartzCore
import SwiftUI

enum CommitGraphMarqueePurpose: Equatable {
    case createGroup
    case addToGroup(UUID)
    case createRegion
}

enum CommitGraphContextAction: Equatable {
    case renameGroup(UUID)
    case addToGroup(UUID)
    case deleteGroup(UUID)
    case editRegion(UUID)
    case deleteRegion(UUID)
}

struct CommitGraphInteractionSurface: NSViewRepresentable {
    let visibleScene: CommitGraphVisibleScene
    let regions: [CommitGraphRegionMarker]
    let viewport: GraphViewport
    let marqueePurpose: CommitGraphMarqueePurpose
    let onViewportChanges: ([GraphViewportChange]) -> Void
    let onPointerChanges: ([CommitGraphPointerChange]) -> Void
    let onNodeClick:
        (String, CommitGraphSelectionModifiers, Bool) -> Void
    let onMarqueeSelectionCompleted:
        (CommitGraphMarqueePurpose, Set<String>, GraphRect) -> Void
    let onContextAction: (CommitGraphContextAction) -> Void
    let onCancelMarqueeMode: () -> Void
    let onGroupDoubleClick: (UUID, Bool) -> Void
    let onDoubleClickBlank: () -> Void
    let onInteractionEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onViewportChanges: onViewportChanges,
            onPointerChanges: onPointerChanges,
            onNodeClick: onNodeClick,
            onMarqueeSelectionCompleted: onMarqueeSelectionCompleted,
            onContextAction: onContextAction,
            onCancelMarqueeMode: onCancelMarqueeMode,
            onGroupDoubleClick: onGroupDoubleClick,
            onDoubleClickBlank: onDoubleClickBlank,
            onInteractionEnded: onInteractionEnded
        )
    }

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.coordinator = context.coordinator
        view.visibleScene = visibleScene
        view.regions = regions
        view.viewport = viewport
        view.marqueePurpose = marqueePurpose
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        context.coordinator.update(
            onViewportChanges: onViewportChanges,
            onPointerChanges: onPointerChanges,
            onNodeClick: onNodeClick,
            onMarqueeSelectionCompleted: onMarqueeSelectionCompleted,
            onContextAction: onContextAction,
            onCancelMarqueeMode: onCancelMarqueeMode,
            onGroupDoubleClick: onGroupDoubleClick,
            onDoubleClickBlank: onDoubleClickBlank,
            onInteractionEnded: onInteractionEnded
        )
        nsView.visibleScene = visibleScene
        nsView.regions = regions
        nsView.viewport = viewport
        nsView.marqueePurpose = marqueePurpose
        if nsView.isMarqueeActive {
            nsView.refreshMarquee()
        }
    }

    static func dismantleNSView(
        _ nsView: InteractionView,
        coordinator _: Coordinator
    ) {
        nsView.stopFrameScheduler()
        nsView.coordinator = nil
    }

    @MainActor
    final class Coordinator {
        private var onViewportChanges: ([GraphViewportChange]) -> Void
        private var onPointerChanges: ([CommitGraphPointerChange]) -> Void
        private var onNodeClick:
            (String, CommitGraphSelectionModifiers, Bool) -> Void
        private var onMarqueeSelectionCompleted:
            (CommitGraphMarqueePurpose, Set<String>, GraphRect) -> Void
        private var onContextAction: (CommitGraphContextAction) -> Void
        private var onCancelMarqueeMode: () -> Void
        private var onGroupDoubleClick: (UUID, Bool) -> Void
        private var onDoubleClickBlank: () -> Void
        private var onInteractionEnded: () -> Void
        private var pendingViewportChanges: [GraphViewportChange] = []
        private var pendingPointerChanges: [CommitGraphPointerChange] = []

        init(
            onViewportChanges: @escaping ([GraphViewportChange]) -> Void,
            onPointerChanges: @escaping ([CommitGraphPointerChange]) -> Void,
            onNodeClick: @escaping (
                String,
                CommitGraphSelectionModifiers,
                Bool
            ) -> Void,
            onMarqueeSelectionCompleted: @escaping (
                CommitGraphMarqueePurpose,
                Set<String>,
                GraphRect
            ) -> Void,
            onContextAction: @escaping (CommitGraphContextAction) -> Void,
            onCancelMarqueeMode: @escaping () -> Void,
            onGroupDoubleClick: @escaping (UUID, Bool) -> Void,
            onDoubleClickBlank: @escaping () -> Void,
            onInteractionEnded: @escaping () -> Void
        ) {
            self.onViewportChanges = onViewportChanges
            self.onPointerChanges = onPointerChanges
            self.onNodeClick = onNodeClick
            self.onMarqueeSelectionCompleted =
                onMarqueeSelectionCompleted
            self.onContextAction = onContextAction
            self.onCancelMarqueeMode = onCancelMarqueeMode
            self.onGroupDoubleClick = onGroupDoubleClick
            self.onDoubleClickBlank = onDoubleClickBlank
            self.onInteractionEnded = onInteractionEnded
        }

        func update(
            onViewportChanges: @escaping ([GraphViewportChange]) -> Void,
            onPointerChanges: @escaping ([CommitGraphPointerChange]) -> Void,
            onNodeClick: @escaping (
                String,
                CommitGraphSelectionModifiers,
                Bool
            ) -> Void,
            onMarqueeSelectionCompleted: @escaping (
                CommitGraphMarqueePurpose,
                Set<String>,
                GraphRect
            ) -> Void,
            onContextAction: @escaping (CommitGraphContextAction) -> Void,
            onCancelMarqueeMode: @escaping () -> Void,
            onGroupDoubleClick: @escaping (UUID, Bool) -> Void,
            onDoubleClickBlank: @escaping () -> Void,
            onInteractionEnded: @escaping () -> Void
        ) {
            self.onViewportChanges = onViewportChanges
            self.onPointerChanges = onPointerChanges
            self.onNodeClick = onNodeClick
            self.onMarqueeSelectionCompleted =
                onMarqueeSelectionCompleted
            self.onContextAction = onContextAction
            self.onCancelMarqueeMode = onCancelMarqueeMode
            self.onGroupDoubleClick = onGroupDoubleClick
            self.onDoubleClickBlank = onDoubleClickBlank
            self.onInteractionEnded = onInteractionEnded
        }

        func enqueueViewport(_ change: GraphViewportChange) {
            pendingViewportChanges.append(change)
        }

        func enqueuePointer(_ change: CommitGraphPointerChange) {
            pendingPointerChanges.append(change)
        }

        func nodeClick(
            hash: String,
            modifiers: CommitGraphSelectionModifiers,
            opensDetail: Bool
        ) {
            onNodeClick(hash, modifiers, opensDetail)
        }

        func groupDoubleClick(id: UUID, isCollapsed: Bool) {
            onGroupDoubleClick(id, isCollapsed)
        }

        func marqueeSelectionCompleted(
            purpose: CommitGraphMarqueePurpose,
            hashes: Set<String>,
            rect: GraphRect
        ) {
            onMarqueeSelectionCompleted(purpose, hashes, rect)
        }

        func contextAction(_ action: CommitGraphContextAction) {
            onContextAction(action)
        }

        func cancelMarqueeMode() {
            onCancelMarqueeMode()
        }

        func blankDoubleClick() {
            onDoubleClickBlank()
        }

        func interactionEnded() {
            onInteractionEnded()
        }

        func flush() {
            if !pendingViewportChanges.isEmpty {
                let changes = pendingViewportChanges
                pendingViewportChanges.removeAll(keepingCapacity: true)
                onViewportChanges(changes)
            }
            if !pendingPointerChanges.isEmpty {
                let changes = pendingPointerChanges
                pendingPointerChanges.removeAll(keepingCapacity: true)
                onPointerChanges(changes)
            }
        }
    }

    @MainActor
    final class InteractionView: NSView {
        private enum DragTarget {
            case canvas
            case node(String)
            case group(UUID)
            case region(UUID)
            case resizeRegion(UUID)
        }

        private enum ContextTarget {
            case group(UUID)
            case region(UUID)
        }

        weak var coordinator: Coordinator?
        var visibleScene = CommitGraphVisibleScene(
            nodes: [],
            groups: [],
            edges: []
        )
        var regions: [CommitGraphRegionMarker] = []
        var viewport = GraphViewport()
        var marqueePurpose = CommitGraphMarqueePurpose.createGroup
        private var dragTarget: DragTarget = .canvas
        private var didDrag = false
        private var accumulatedDistance = 0.0
        private var lastDragScreenPoint: GraphPoint?
        private var frameLink: CADisplayLink?
        private var canStartMarquee = false
        private(set) var isMarqueeActive = false
        private var marqueeAnchorCanvasPoint: GraphPoint?
        private var marqueePointerScreenPoint: GraphPoint?
        private var marqueeSelectedHashes: Set<String> = []
        private var marqueeScreenRect: NSRect?
        private var marqueeCanvasRect: GraphRect?
        private var contextTarget: ContextTarget?

        private let marqueeThreshold = 2.0
        private let edgeHotZone = 40.0
        private let maximumAutoPanSpeed = 15.0

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                stopFrameScheduler()
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            didDrag = false
            accumulatedDistance = 0
            let screenPoint = convertedPoint(event.locationInWindow)
            lastDragScreenPoint = screenPoint
            dragTarget = target(at: screenPoint)
            NSCursor.closedHand.set()
        }

        override func mouseDragged(with event: NSEvent) {
            let currentPoint = convertedPoint(event.locationInWindow)
            guard let previousPoint = lastDragScreenPoint else {
                lastDragScreenPoint = currentPoint
                return
            }
            let screenTranslation = GraphPoint(
                x: currentPoint.x - previousPoint.x,
                y: currentPoint.y - previousPoint.y
            )
            lastDragScreenPoint = currentPoint
            accumulatedDistance += hypot(
                screenTranslation.x,
                screenTranslation.y
            )
            didDrag = accumulatedDistance >= 2

            switch dragTarget {
            case .canvas:
                coordinator?.enqueueViewport(.pan(screenTranslation))
            case let .node(hash):
                coordinator?.enqueuePointer(
                    .moveNode(
                        hash: hash,
                        translation: canvasTranslation(screenTranslation)
                    )
                )
            case let .group(id):
                coordinator?.enqueuePointer(
                    .moveGroup(
                        id: id,
                        translation: canvasTranslation(screenTranslation)
                    )
                )
            case let .region(id):
                coordinator?.enqueuePointer(
                    .moveRegion(
                        id: id,
                        translation: canvasTranslation(screenTranslation)
                    )
                )
            case let .resizeRegion(id):
                coordinator?.enqueuePointer(
                    .resizeRegion(
                        id: id,
                        translation: canvasTranslation(screenTranslation)
                    )
                )
            }
            requestDisplayFrame()
        }

        override func mouseUp(with event: NSEvent) {
            coordinator?.flush()
            lastDragScreenPoint = nil
            NSCursor.openHand.set()
            if didDrag {
                coordinator?.interactionEnded()
                return
            }

            switch dragTarget {
            case let .node(hash):
                let modifiers = selectionModifiers(event.modifierFlags)
                coordinator?.nodeClick(
                    hash: hash,
                    modifiers: modifiers,
                    opensDetail: modifiers.isEmpty
                )
            case let .group(id):
                guard event.clickCount >= 2,
                      let group = visibleScene.groups.first(
                        where: { $0.id == id }
                      )
                else {
                    return
                }
                coordinator?.groupDoubleClick(
                    id: id,
                    isCollapsed: group.isCollapsed
                )
            case .canvas:
                if event.clickCount >= 2 {
                    coordinator?.blankDoubleClick()
                }
            case .region, .resizeRegion:
                return
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            didDrag = false
            accumulatedDistance = 0
            let screenPoint = convertedPoint(event.locationInWindow)
            if let contextTarget = contextTarget(at: screenPoint) {
                showContextMenu(
                    for: contextTarget,
                    event: event
                )
                return
            }
            canStartMarquee = isCanvasBlank(at: screenPoint)
            guard canStartMarquee else { return }
            marqueeAnchorCanvasPoint =
                CommitGraphViewportProjector.canvasPoint(
                    screenPoint: screenPoint,
                    viewport: viewport
                )
            marqueePointerScreenPoint = screenPoint
            marqueeSelectedHashes.removeAll(keepingCapacity: true)
            marqueeScreenRect = nil
            NSCursor.crosshair.set()
        }

        override func rightMouseDragged(with event: NSEvent) {
            guard canStartMarquee,
                  let previousPoint = marqueePointerScreenPoint
            else {
                return
            }
            let currentPoint = convertedPoint(event.locationInWindow)
            accumulatedDistance += hypot(
                currentPoint.x - previousPoint.x,
                currentPoint.y - previousPoint.y
            )
            marqueePointerScreenPoint = currentPoint
            if accumulatedDistance >= marqueeThreshold {
                didDrag = true
                isMarqueeActive = true
                refreshMarquee()
                requestDisplayFrame()
            }
        }

        override func rightMouseUp(with event: NSEvent) {
            guard canStartMarquee else { return }
            marqueePointerScreenPoint =
                convertedPoint(event.locationInWindow)
            if isMarqueeActive {
                refreshMarquee()
                coordinator?.flush()
            }
            let selectedHashes = marqueeSelectedHashes
            let canvasRect = marqueeCanvasRect
            let completedSelection = didDrag && isMarqueeActive
            resetMarquee()
            NSCursor.openHand.set()
            if completedSelection, let canvasRect {
                coordinator?.marqueeSelectionCompleted(
                    purpose: marqueePurpose,
                    hashes: selectedHashes,
                    rect: canvasRect
                )
            }
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {
                resetMarquee()
                coordinator?.cancelMarqueeMode()
                return
            }
            super.keyDown(with: event)
        }

        override func scrollWheel(with event: NSEvent) {
            let sensitivity = event.hasPreciseScrollingDeltas
                ? 0.004
                : 0.08
            let zoomDelta = min(
                max(
                    -Double(event.scrollingDeltaY) * sensitivity,
                    -0.35
                ),
                0.35
            )
            guard zoomDelta != 0 else { return }
            coordinator?.enqueueViewport(
                .zoom(
                    multiplier: exp(zoomDelta),
                    anchor: convertedPoint(event.locationInWindow)
                )
            )
            requestDisplayFrame()
        }

        override func magnify(with event: NSEvent) {
            coordinator?.enqueueViewport(
                .zoom(
                    multiplier: 1 + Double(event.magnification),
                    anchor: convertedPoint(event.locationInWindow)
                )
            )
            requestDisplayFrame()
        }

        func stopFrameScheduler() {
            frameLink?.invalidate()
            frameLink = nil
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .openHand)
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard isMarqueeActive,
                  let marqueeScreenRect,
                  let pointer = marqueePointerScreenPoint
            else {
                return
            }

            let highlightColor = NSColor.controlAccentColor
            highlightColor.withAlphaComponent(0.08).setFill()
            highlightColor.withAlphaComponent(0.82).setStroke()
            let selectionPath = NSBezierPath(
                roundedRect: marqueeScreenRect,
                xRadius: 7,
                yRadius: 7
            )
            selectionPath.lineWidth = 1.5
            selectionPath.fill()
            selectionPath.stroke()

            if marqueePurpose != .createRegion {
                for node in visibleScene.nodes
                    where marqueeSelectedHashes.contains(node.node.hash) {
                    let rect = screenRect(for: node)
                    let path = NSBezierPath(
                        roundedRect: rect.insetBy(dx: -2, dy: -2),
                        xRadius: 11,
                        yRadius: 11
                    )
                    path.lineWidth = 2.5
                    highlightColor.setStroke()
                    path.stroke()
                }
            }

            drawMarqueeCount(
                marqueePurpose == .createRegion
                    ? nil
                    : marqueeSelectedHashes.count,
                near: pointer
            )
        }

        func refreshMarquee() {
            guard isMarqueeActive,
                  let anchor = marqueeAnchorCanvasPoint,
                  let pointer = marqueePointerScreenPoint
            else {
                return
            }
            let currentCanvasPoint =
                CommitGraphViewportProjector.canvasPoint(
                    screenPoint: clampedScreenPoint(pointer),
                    viewport: viewport
                )
            let canvasRect = normalizedRect(
                from: anchor,
                to: currentCanvasPoint
            )
            marqueeCanvasRect = canvasRect
            if marqueePurpose == .createRegion {
                marqueeSelectedHashes.removeAll(keepingCapacity: true)
            } else {
                let visibleHashes = Set(
                    visibleScene.nodes.compactMap { visibleNode in
                        intersects(
                            canvasRect,
                            nodeAt: visibleNode.position
                        )
                            ? visibleNode.node.hash
                            : nil
                    }
                )
                // 边缘自动滚动时可见候选会换页；保留已经经过的
                // 节点，避免被视口裁剪掉后从框选结果中消失。
                marqueeSelectedHashes.formUnion(visibleHashes)
            }
            let anchorScreenPoint =
                CommitGraphViewportProjector.screenPoint(
                    canvasPoint: anchor,
                    viewport: viewport
                )
            marqueeScreenRect = screenRect(
                from: anchorScreenPoint,
                to: clampedScreenPoint(pointer)
            )
            needsDisplay = true
        }

        private func requestDisplayFrame() {
            if frameLink == nil {
                let link = displayLink(
                    target: self,
                    selector: #selector(displayFrameDidFire(_:))
                )
                link.add(to: .main, forMode: .common)
                link.isPaused = true
                frameLink = link
            }
            frameLink?.isPaused = false
        }

        @objc
        private func displayFrameDidFire(_ displayLink: CADisplayLink) {
            let shouldContinue = advanceMarqueeAutoPan()
            coordinator?.flush()
            displayLink.isPaused = !shouldContinue
        }

        private func target(at screenPoint: GraphPoint) -> DragTarget {
            let point = CommitGraphViewportProjector.canvasPoint(
                screenPoint: screenPoint,
                viewport: viewport
            )
            for visibleNode in visibleScene.nodes.reversed() {
                let halfWidth =
                    CommitGraphViewportProjector.nodeWidth / 2
                let halfHeight =
                    CommitGraphViewportProjector.nodeHeight / 2
                if point.x >= visibleNode.position.x - halfWidth,
                   point.x <= visibleNode.position.x + halfWidth,
                   point.y >= visibleNode.position.y - halfHeight,
                   point.y <= visibleNode.position.y + halfHeight {
                    return .node(visibleNode.node.hash)
                }
            }
            for group in visibleScene.groups.reversed() {
                let rect = group.rect
                let isInRect = point.x >= rect.minimumX
                    && point.x <= rect.maximumX
                    && point.y >= rect.minimumY
                    && point.y <= rect.maximumY
                let isInDraggableArea = group.isCollapsed
                    || point.y <= rect.minimumY + 38
                if isInRect && isInDraggableArea {
                    return .group(group.id)
                }
            }
            for region in regions.reversed() {
                let rect = region.rect
                let handleSize = 20.0
                let isInResizeHandle =
                    point.x >= rect.maximumX - handleSize
                    && point.x <= rect.maximumX + 4
                    && point.y >= rect.maximumY - handleSize
                    && point.y <= rect.maximumY + 4
                if isInResizeHandle {
                    return .resizeRegion(region.id)
                }
                let isInHeader = point.x >= rect.minimumX
                    && point.x <= rect.maximumX
                    && point.y >= rect.minimumY
                    && point.y <= rect.minimumY + 36
                if isInHeader {
                    return .region(region.id)
                }
            }
            return .canvas
        }

        private func contextTarget(
            at screenPoint: GraphPoint
        ) -> ContextTarget? {
            let point = CommitGraphViewportProjector.canvasPoint(
                screenPoint: screenPoint,
                viewport: viewport
            )
            for group in visibleScene.groups.reversed() {
                let rect = group.rect
                let isInHeader = point.x >= rect.minimumX
                    && point.x <= rect.maximumX
                    && point.y >= rect.minimumY
                    && point.y <= (
                        group.isCollapsed
                            ? rect.maximumY
                            : rect.minimumY + 38
                    )
                if isInHeader {
                    return .group(group.id)
                }
            }
            for region in regions.reversed() {
                let rect = region.rect
                let isInHeader = point.x >= rect.minimumX
                    && point.x <= rect.maximumX
                    && point.y >= rect.minimumY
                    && point.y <= rect.minimumY + 36
                if isInHeader {
                    return .region(region.id)
                }
            }
            return nil
        }

        private func showContextMenu(
            for target: ContextTarget,
            event: NSEvent
        ) {
            contextTarget = target
            let menu = NSMenu()
            switch target {
            case .group:
                addMenuItem(
                    "重命名分组",
                    selector: #selector(renameGroupFromMenu),
                    to: menu
                )
                addMenuItem(
                    "添加提交",
                    selector: #selector(addToGroupFromMenu),
                    to: menu
                )
                menu.addItem(.separator())
                addMenuItem(
                    "删除分组",
                    selector: #selector(deleteGroupFromMenu),
                    to: menu
                )
            case .region:
                addMenuItem(
                    "编辑名称与颜色",
                    selector: #selector(editRegionFromMenu),
                    to: menu
                )
                menu.addItem(.separator())
                addMenuItem(
                    "删除区域标识",
                    selector: #selector(deleteRegionFromMenu),
                    to: menu
                )
            }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        private func addMenuItem(
            _ title: String,
            selector: Selector,
            to menu: NSMenu
        ) {
            let item = NSMenuItem(
                title: title,
                action: selector,
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }

        @objc
        private func renameGroupFromMenu() {
            guard case let .group(id) = contextTarget else { return }
            coordinator?.contextAction(.renameGroup(id))
        }

        @objc
        private func addToGroupFromMenu() {
            guard case let .group(id) = contextTarget else { return }
            coordinator?.contextAction(.addToGroup(id))
        }

        @objc
        private func deleteGroupFromMenu() {
            guard case let .group(id) = contextTarget else { return }
            coordinator?.contextAction(.deleteGroup(id))
        }

        @objc
        private func editRegionFromMenu() {
            guard case let .region(id) = contextTarget else { return }
            coordinator?.contextAction(.editRegion(id))
        }

        @objc
        private func deleteRegionFromMenu() {
            guard case let .region(id) = contextTarget else { return }
            coordinator?.contextAction(.deleteRegion(id))
        }

        private func isCanvasBlank(at screenPoint: GraphPoint) -> Bool {
            if case .canvas = target(at: screenPoint) {
                return true
            }
            return false
        }

        private func advanceMarqueeAutoPan() -> Bool {
            guard isMarqueeActive,
                  let pointer = marqueePointerScreenPoint
            else {
                return false
            }
            let translation = autoPanTranslation(for: pointer)
            if translation != .zero {
                viewport.offsetX += translation.x
                viewport.offsetY += translation.y
                coordinator?.enqueueViewport(.pan(translation))
            }
            refreshMarquee()
            return translation != .zero
        }

        private func autoPanTranslation(
            for point: GraphPoint
        ) -> GraphPoint {
            GraphPoint(
                x: edgeTranslation(
                    coordinate: point.x,
                    extent: bounds.width
                ),
                y: edgeTranslation(
                    coordinate: point.y,
                    extent: bounds.height
                )
            )
        }

        private func edgeTranslation(
            coordinate: Double,
            extent: Double
        ) -> Double {
            if coordinate < edgeHotZone {
                let progress = min(
                    max((edgeHotZone - coordinate) / edgeHotZone, 0),
                    1
                )
                return maximumAutoPanSpeed * progress * progress
            }
            if coordinate > extent - edgeHotZone {
                let progress = min(
                    max(
                        (coordinate - (extent - edgeHotZone))
                            / edgeHotZone,
                        0
                    ),
                    1
                )
                return -maximumAutoPanSpeed * progress * progress
            }
            return 0
        }

        private func normalizedRect(
            from start: GraphPoint,
            to end: GraphPoint
        ) -> GraphRect {
            GraphRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        }

        private func intersects(
            _ selection: GraphRect,
            nodeAt position: GraphPoint
        ) -> Bool {
            let halfWidth =
                CommitGraphViewportProjector.nodeWidth / 2
            let halfHeight =
                CommitGraphViewportProjector.nodeHeight / 2
            return selection.minimumX <= position.x + halfWidth
                && selection.maximumX >= position.x - halfWidth
                && selection.minimumY <= position.y + halfHeight
                && selection.maximumY >= position.y - halfHeight
        }

        private func screenRect(
            for visibleNode: CommitGraphVisibleNode
        ) -> NSRect {
            let point = CommitGraphViewportProjector.screenPoint(
                canvasPoint: visibleNode.position,
                viewport: viewport
            )
            return NSRect(
                x: point.x
                    - CommitGraphViewportProjector.nodeWidth
                        * viewport.scale / 2,
                y: point.y
                    - CommitGraphViewportProjector.nodeHeight
                        * viewport.scale / 2,
                width: CommitGraphViewportProjector.nodeWidth
                    * viewport.scale,
                height: CommitGraphViewportProjector.nodeHeight
                    * viewport.scale
            )
        }

        private func screenRect(
            from start: GraphPoint,
            to end: GraphPoint
        ) -> NSRect {
            NSRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        }

        private func clampedScreenPoint(
            _ point: GraphPoint
        ) -> GraphPoint {
            GraphPoint(
                x: min(max(point.x, 0), bounds.width),
                y: min(max(point.y, 0), bounds.height)
            )
        }

        private func drawMarqueeCount(
            _ count: Int?,
            near point: GraphPoint
        ) {
            let value = count.map { "已选 \($0) 个" }
                ?? "版本区域"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(
                    ofSize: 11.5,
                    weight: .semibold
                ),
                .foregroundColor: NSColor.white,
            ]
            let textSize = value.size(withAttributes: attributes)
            let bubbleSize = NSSize(
                width: textSize.width + 18,
                height: 24
            )
            let origin = NSPoint(
                x: min(
                    max(point.x + 12, 6),
                    bounds.width - bubbleSize.width - 6
                ),
                y: min(
                    max(point.y + 12, 6),
                    bounds.height - bubbleSize.height - 6
                )
            )
            let bubbleRect = NSRect(
                origin: origin,
                size: bubbleSize
            )
            NSColor.controlAccentColor.setFill()
            NSBezierPath(
                roundedRect: bubbleRect,
                xRadius: 12,
                yRadius: 12
            ).fill()
            value.draw(
                at: NSPoint(
                    x: origin.x + 9,
                    y: origin.y + 5
                ),
                withAttributes: attributes
            )
        }

        private func resetMarquee() {
            canStartMarquee = false
            isMarqueeActive = false
            marqueeAnchorCanvasPoint = nil
            marqueePointerScreenPoint = nil
            marqueeSelectedHashes.removeAll(keepingCapacity: true)
            marqueeScreenRect = nil
            marqueeCanvasRect = nil
            contextTarget = nil
            frameLink?.isPaused = true
            needsDisplay = true
        }

        private func canvasTranslation(
            _ screenTranslation: GraphPoint
        ) -> GraphPoint {
            let scale = max(viewport.scale, 0.001)
            return GraphPoint(
                x: screenTranslation.x / scale,
                y: screenTranslation.y / scale
            )
        }

        private func selectionModifiers(
            _ flags: NSEvent.ModifierFlags
        ) -> CommitGraphSelectionModifiers {
            var result: CommitGraphSelectionModifiers = []
            if flags.contains(.command) {
                result.insert(.command)
            }
            if flags.contains(.shift) {
                result.insert(.shift)
            }
            return result
        }

        private func convertedPoint(_ windowPoint: NSPoint) -> GraphPoint {
            let point = convert(windowPoint, from: nil)
            return GraphPoint(x: point.x, y: point.y)
        }
    }
}
