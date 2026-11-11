import AppKit
import SwiftUI

struct MenuBarPanelAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ nsView: AnchorView, context: Context) { }

    /// Sits behind the whole panel content, so its height is the height the panel should have.
    final class AnchorView: NSView {
        private var fitScheduled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(windowChanged), name: name, object: window)
            }
            windowChanged()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            scheduleFit()
        }

        @objc private func windowChanged() {
            align()
            scheduleFit()
        }

        private func align() {
            guard let window, let screen = window.screen else { return }
            // SwiftUI positions the panel horizontally; remove only its extra gap below the menu bar.
            let top = min(screen.visibleFrame.maxY, screen.frame.maxY - NSStatusBar.system.thickness)
            if abs(window.frame.maxY - top) > 0.5 {
                window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
            }
        }

        /// SwiftUI can leave the panel at its taller size after the content shrinks (for example when the sync
        /// progress disappears): only its minimum size follows the content. The content then sits centered with
        /// bare glass above and below and loses its rounded corners. Deferred so layout and SwiftUI's own resize settle first.
        private func scheduleFit() {
            guard !fitScheduled else { return }
            fitScheduled = true
            RunLoop.main.perform { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.fitScheduled = false
                    self.fit()
                }
            }
        }

        private func fit() {
            guard let window, bounds.height > 0 else { return }
            let content = window.contentRect(forFrameRect: window.frame)
            guard abs(content.height - bounds.height) > 0.5 else { return }
            window.setContentSize(NSSize(width: content.width, height: bounds.height)) // keeps the top edge
        }
    }
}
