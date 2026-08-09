import AppKit
import GitMateCore
import SwiftUI

struct CommitGraphTraditionalDividerHandle: NSViewRepresentable {
    let currentWidth: Double
    let viewportWidth: Double
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onCommit: onCommit)
    }

    func makeNSView(context: Context) -> DividerView {
        let view = DividerView()
        view.coordinator = context.coordinator
        update(view)
        return view
    }

    func updateNSView(_ view: DividerView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onCommit = onCommit
        update(view)
    }

    private func update(_ view: DividerView) {
        view.currentWidth = currentWidth
        view.viewportWidth = viewportWidth
    }

    @MainActor
    final class Coordinator {
        var onChange: (Double) -> Void
        var onCommit: (Double) -> Void

        init(
            onChange: @escaping (Double) -> Void,
            onCommit: @escaping (Double) -> Void
        ) {
            self.onChange = onChange
            self.onCommit = onCommit
        }
    }

    @MainActor
    final class DividerView: NSView {
        weak var coordinator: Coordinator?
        var currentWidth = 0.0
        var viewportWidth = 0.0
        private var startWindowX = 0.0
        private var startWidth = 0.0
        private var proposedWidth = 0.0
        private var isDragging = false

        override var acceptsFirstResponder: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            NSColor.separatorColor.setFill()
            NSRect(
                x: floor(bounds.midX),
                y: dirtyRect.minY,
                width: 1,
                height: dirtyRect.height
            ).fill()
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                let width = CommitGraphTraditionalSplitLayout
                    .defaultDividerWidth(viewportWidth: viewportWidth)
                coordinator?.onChange(width)
                coordinator?.onCommit(width)
                return
            }
            startWindowX = Double(event.locationInWindow.x)
            startWidth = currentWidth
            proposedWidth = currentWidth
            isDragging = true
        }

        override func mouseDragged(with event: NSEvent) {
            guard isDragging else { return }
            let delta = Double(event.locationInWindow.x) - startWindowX
            proposedWidth = CommitGraphTraditionalSplitLayout
                .clampedDividerWidth(
                    startWidth + delta,
                    viewportWidth: viewportWidth
                )
            coordinator?.onChange(proposedWidth)
        }

        override func mouseUp(with _: NSEvent) {
            guard isDragging else { return }
            isDragging = false
            coordinator?.onCommit(proposedWidth)
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }
    }
}
