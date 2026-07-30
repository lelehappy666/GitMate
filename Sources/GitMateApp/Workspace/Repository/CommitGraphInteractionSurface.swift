import AppKit
import GitMateCore
import QuartzCore
import SwiftUI

struct CommitGraphInteractionSurface: NSViewRepresentable {
    let projection: CommitGraphSceneProjection
    let viewport: GraphViewport
    let onViewportChanges: ([GraphViewportChange]) -> Void
    let onPointerChanges: ([CommitGraphPointerChange]) -> Void
    let onNodeClick:
        (String, CommitGraphSelectionModifiers, Bool) -> Void
    let onMarqueeSelectionCompleted: (Set<String>) -> Void
    let onGroupDoubleClick: (UUID, Bool) -> Void
    let onDoubleClickBlank: () -> Void
    let onInteractionEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onViewportChanges: onViewportChanges,
            onPointerChanges: onPointerChanges,
            onNodeClick: onNodeClick,
            onMarqueeSelectionCompleted: onMarqueeSelectionCompleted,
            onGroupDoubleClick: onGroupDoubleClick,
            onDoubleClickBlank: onDoubleClickBlank,
            onInteractionEnded: onInteractionEnded
        )
    }

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.coordinator = context.coordinator
        view.projection = projection
        view.viewport = viewport
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
            onGroupDoubleClick: onGroupDoubleClick,
            onDoubleClickBlank: onDoubleClickBlank,
            onInteractionEnded: onInteractionEnded
        )
        nsView.projection = projection
        nsView.viewport = viewport
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
        private var onMarqueeSelectionCompleted: (Set<String>) -> Void
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
            onMarqueeSelectionCompleted: @escaping (Set<String>) -> Void,
            onGroupDoubleClick: @escaping (UUID, Bool) -> Void,
            onDoubleClickBlank: @escaping () -> Void,
            onInteractionEnded: @escaping () -> Void
        ) {
            self.onViewportChanges = onViewportChanges
            self.onPointerChanges = onPointerChanges
            self.onNodeClick = onNodeClick
            self.onMarqueeSelectionCompleted =
                onMarqueeSelectionCompleted
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
            onMarqueeSelectionCompleted: @escaping (Set<String>) -> Void,
            onGroupDoubleClick: @escaping (UUID, Bool) -> Void,
            onDoubleClickBlank: @escaping () -> Void,
            onInteractionEnded: @escaping () -> Void
        ) {
            self.onViewportChanges = onViewportChanges
            self.onPointerChanges = onPointerChanges
            self.onNodeClick = onNodeClick
            self.onMarqueeSelectionCompleted =
                onMarqueeSelectionCompleted
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

        func marqueeSelectionCompleted(hashes: Set<String>) {
            onMarqueeSelectionCompleted(hashes)
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
        }

        weak var coordinator: Coordinator?
        var projection = CommitGraphSceneProjection(
            nodes: [],
            groups: [],
            edges: []
        )
        var viewport = GraphViewport()
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
                      let group = projection.groups.first(
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
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            didDrag = false
            accumulatedDistance = 0
            let screenPoint = convertedPoint(event.locationInWindow)
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
            let completedSelection = didDrag && isMarqueeActive
            resetMarquee()
            NSCursor.openHand.set()
            if completedSelection {
                coordinator?.marqueeSelectionCompleted(
                    hashes: selectedHashes
                )
            }
        }

        override func scrollWheel(with event: NSEvent) {
            let sensitivity = event.hasPreciseScrollingDeltas
                ? 0.004
                : 0.08
            let zoomDelta = min(
                max(
                    Double(event.scrollingDeltaY) * sensitivity,
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

            for node in projection.nodes
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

            drawMarqueeCount(
                marqueeSelectedHashes.count,
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
            marqueeSelectedHashes = Set(
                projection.nodes.compactMap { visibleNode in
                    intersects(
                        canvasRect,
                        nodeAt: visibleNode.position
                    )
                        ? visibleNode.node.hash
                        : nil
                }
            )
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
            for visibleNode in projection.nodes.reversed() {
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
            for group in projection.groups.reversed() {
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
            return .canvas
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
            _ count: Int,
            near point: GraphPoint
        ) {
            let value = "已选 \(count) 个"
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
