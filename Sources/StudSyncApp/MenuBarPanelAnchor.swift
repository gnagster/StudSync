import AppKit
import SwiftUI

struct MenuBarPanelAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ nsView: AnchorView, context: Context) { }

    final class AnchorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(align), name: name, object: window)
            }
            align()
        }

        @objc private func align() {
            guard let window, let screen = window.screen else { return }
            // SwiftUI positions the panel horizontally; remove only its extra gap below the menu bar.
            let top = min(screen.visibleFrame.maxY, screen.frame.maxY - NSStatusBar.system.thickness)
            if abs(window.frame.maxY - top) > 0.5 {
                window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
            }
        }
    }
}
