import AppKit
import GitMateCore
import SwiftUI

struct CommitGraphInteractionSurface: NSViewRepresentable {
    let layout: CommitGraphLayoutResult
    let viewport: GraphViewport
    let onPan: (GraphPoint) -> Void
    let onZoom: (Double, GraphPoint) -> Void
    let onClick: (String) -> Void
    let onDoubleClick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPan: onPan,
            onZoom: onZoom,
            onClick: onClick,
            onDoubleClick: onDoubleClick
        )
    }

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.coordinator = context.coordinator
        view.graphLayout = layout
        view.viewport = viewport
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        context.coordinator.update(
            onPan: onPan,
            onZoom: onZoom,
            onClick: onClick,
            onDoubleClick: onDoubleClick
        )
        nsView.graphLayout = layout
        nsView.viewport = viewport
    }

    @MainActor
    final class Coordinator {
        private var onPan: (GraphPoint) -> Void
        private var onZoom: (Double, GraphPoint) -> Void
        private var onClick: (String) -> Void
        private var onDoubleClick: () -> Void
        private var pendingPan = GraphPoint.zero
        private var pendingZoomMultiplier = 1.0
        private var pendingZoomAnchor = GraphPoint.zero
        private var flushScheduled = false

        init(
            onPan: @escaping (GraphPoint) -> Void,
            onZoom: @escaping (Double, GraphPoint) -> Void,
            onClick: @escaping (String) -> Void,
            onDoubleClick: @escaping () -> Void
        ) {
            self.onPan = onPan
            self.onZoom = onZoom
            self.onClick = onClick
            self.onDoubleClick = onDoubleClick
        }

        func update(
            onPan: @escaping (GraphPoint) -> Void,
            onZoom: @escaping (Double, GraphPoint) -> Void,
            onClick: @escaping (String) -> Void,
            onDoubleClick: @escaping () -> Void
        ) {
            self.onPan = onPan
            self.onZoom = onZoom
            self.onClick = onClick
            self.onDoubleClick = onDoubleClick
        }

        func enqueuePan(_ translation: GraphPoint) {
            pendingPan = GraphPoint(
                x: pendingPan.x + translation.x,
                y: pendingPan.y + translation.y
            )
            scheduleFlush()
        }

        func enqueueZoom(multiplier: Double, anchor: GraphPoint) {
            guard multiplier.isFinite, multiplier > 0 else { return }
            pendingZoomMultiplier *= multiplier
            pendingZoomAnchor = anchor
            scheduleFlush()
        }

        func select(hash: String) {
            onClick(hash)
        }

        func fitAll() {
            onDoubleClick()
        }

        private func scheduleFlush() {
            guard !flushScheduled else { return }
            flushScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.flush()
            }
        }

        private func flush() {
            flushScheduled = false
            let pan = pendingPan
            let zoomMultiplier = pendingZoomMultiplier
            let zoomAnchor = pendingZoomAnchor
            pendingPan = .zero
            pendingZoomMultiplier = 1

            if pan != .zero {
                onPan(pan)
            }
            if zoomMultiplier != 1 {
                onZoom(zoomMultiplier, zoomAnchor)
            }
        }
    }

    @MainActor
    final class InteractionView: NSView {
        weak var coordinator: Coordinator?
        var graphLayout = CommitGraphLayoutResult()
        var viewport = GraphViewport()
        private var didDrag = false

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            didDrag = true
            coordinator?.enqueuePan(
                GraphPoint(x: event.deltaX, y: -event.deltaY)
            )
        }

        override func mouseUp(with event: NSEvent) {
            guard !didDrag else { return }
            let point = convertedPoint(event.locationInWindow)
            let node = CommitGraphViewportProjector.node(
                at: point,
                layout: graphLayout,
                viewport: viewport
            )

            if event.clickCount >= 2 {
                if node == nil {
                    coordinator?.fitAll()
                }
            } else if let node {
                coordinator?.select(hash: node.hash)
            }
        }

        override func scrollWheel(with event: NSEvent) {
            let anchor = convertedPoint(event.locationInWindow)
            coordinator?.enqueueZoom(
                multiplier: exp(event.scrollingDeltaY * 0.012),
                anchor: anchor
            )
        }

        override func magnify(with event: NSEvent) {
            coordinator?.enqueueZoom(
                multiplier: 1 + event.magnification,
                anchor: convertedPoint(event.locationInWindow)
            )
        }

        private func convertedPoint(_ windowPoint: NSPoint) -> GraphPoint {
            let point = convert(windowPoint, from: nil)
            return GraphPoint(x: point.x, y: point.y)
        }
    }
}
