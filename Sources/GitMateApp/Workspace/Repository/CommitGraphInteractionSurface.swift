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
    let onGroupDoubleClick: (UUID, Bool) -> Void
    let onDoubleClickBlank: () -> Void
    let onInteractionEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onViewportChanges: onViewportChanges,
            onPointerChanges: onPointerChanges,
            onNodeClick: onNodeClick,
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
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        context.coordinator.update(
            onViewportChanges: onViewportChanges,
            onPointerChanges: onPointerChanges,
            onNodeClick: onNodeClick,
            onGroupDoubleClick: onGroupDoubleClick,
            onDoubleClickBlank: onDoubleClickBlank,
            onInteractionEnded: onInteractionEnded
        )
        nsView.projection = projection
        nsView.viewport = viewport
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
            onGroupDoubleClick: @escaping (UUID, Bool) -> Void,
            onDoubleClickBlank: @escaping () -> Void,
            onInteractionEnded: @escaping () -> Void
        ) {
            self.onViewportChanges = onViewportChanges
            self.onPointerChanges = onPointerChanges
            self.onNodeClick = onNodeClick
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
            onGroupDoubleClick: @escaping (UUID, Bool) -> Void,
            onDoubleClickBlank: @escaping () -> Void,
            onInteractionEnded: @escaping () -> Void
        ) {
            self.onViewportChanges = onViewportChanges
            self.onPointerChanges = onPointerChanges
            self.onNodeClick = onNodeClick
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
            displayLink.isPaused = true
            coordinator?.flush()
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
