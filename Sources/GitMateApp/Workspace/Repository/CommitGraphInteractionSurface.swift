import AppKit
import GitMateCore
import QuartzCore
import SwiftUI

struct CommitGraphInteractionSurface: NSViewRepresentable {
    let layout: CommitGraphLayoutResult
    let viewport: GraphViewport
    let onViewportChanges: ([GraphViewportChange]) -> Void
    let onClick: (String) -> Void
    let onDoubleClick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onViewportChanges: onViewportChanges,
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
            onViewportChanges: onViewportChanges,
            onClick: onClick,
            onDoubleClick: onDoubleClick
        )
        nsView.graphLayout = layout
        nsView.viewport = viewport
    }

    static func dismantleNSView(
        _ nsView: InteractionView,
        coordinator: Coordinator
    ) {
        nsView.stopFrameScheduler()
        nsView.coordinator = nil
    }

    @MainActor
    final class Coordinator {
        private var onViewportChanges: ([GraphViewportChange]) -> Void
        private var onClick: (String) -> Void
        private var onDoubleClick: () -> Void
        private var pendingChanges: [GraphViewportChange] = []

        init(
            onViewportChanges: @escaping ([GraphViewportChange]) -> Void,
            onClick: @escaping (String) -> Void,
            onDoubleClick: @escaping () -> Void
        ) {
            self.onViewportChanges = onViewportChanges
            self.onClick = onClick
            self.onDoubleClick = onDoubleClick
        }

        func update(
            onViewportChanges: @escaping ([GraphViewportChange]) -> Void,
            onClick: @escaping (String) -> Void,
            onDoubleClick: @escaping () -> Void
        ) {
            self.onViewportChanges = onViewportChanges
            self.onClick = onClick
            self.onDoubleClick = onDoubleClick
        }

        func enqueuePan(_ translation: GraphPoint) {
            pendingChanges.append(.pan(translation))
        }

        func enqueueZoom(multiplier: Double, anchor: GraphPoint) {
            guard multiplier.isFinite, multiplier > 0 else { return }
            pendingChanges.append(
                .zoom(multiplier: multiplier, anchor: anchor)
            )
        }

        func select(hash: String) {
            onClick(hash)
        }

        func fitAll() {
            onDoubleClick()
        }

        func flush() {
            guard !pendingChanges.isEmpty else { return }
            let changes = pendingChanges
            pendingChanges.removeAll(keepingCapacity: true)
            onViewportChanges(changes)
        }
    }

    @MainActor
    final class InteractionView: NSView {
        weak var coordinator: Coordinator?
        var graphLayout = CommitGraphLayoutResult()
        var viewport = GraphViewport()
        private var didDrag = false
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
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            didDrag = true
            coordinator?.enqueuePan(
                GraphPoint(
                    x: Double(event.deltaX),
                    y: -Double(event.deltaY)
                )
            )
            requestDisplayFrame()
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
                multiplier: exp(Double(event.scrollingDeltaY) * 0.012),
                anchor: anchor
            )
            requestDisplayFrame()
        }

        override func magnify(with event: NSEvent) {
            coordinator?.enqueueZoom(
                multiplier: 1 + Double(event.magnification),
                anchor: convertedPoint(event.locationInWindow)
            )
            requestDisplayFrame()
        }

        func stopFrameScheduler() {
            frameLink?.invalidate()
            frameLink = nil
        }

        private func requestDisplayFrame() {
            if frameLink == nil {
                let link = displayLink(
                    target: self,
                    selector: #selector(displayFrameDidFire(_:))
                )
                link.add(
                    to: RunLoop.main,
                    forMode: RunLoop.Mode.common
                )
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

        private func convertedPoint(_ windowPoint: NSPoint) -> GraphPoint {
            let point = convert(windowPoint, from: nil)
            return GraphPoint(
                x: Double(point.x),
                y: Double(point.y)
            )
        }
    }
}
