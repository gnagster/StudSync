import AppKit

@MainActor
enum AppImages {
    static let logo = load("ClassicFold")
    static let menuBarHeight: CGFloat = 18 * 0.85
    static let menuBar: NSImage = {
        let image = load("MenuBarLogo")
        image.size = NSSize(width: menuBarHeight * image.size.width / image.size.height, height: menuBarHeight)
        image.isTemplate = true
        return image
    }()
    static let menuBarError: NSImage = {
        let image = NSImage(size: menuBar.size, flipped: false) { rect in
            menuBar.draw(in: rect)
            NSColor.systemRed.setFill()
            rect.fill(using: .sourceIn)
            return true
        }
        image.isTemplate = false
        return image
    }()
    /// Sync animation: a bright band runs top to bottom through the dimmed logo, like files coming down.
    static let menuBarSyncFrames: [NSImage] = (0..<16).map { frame in
        let phase = 1 - CGFloat(frame) / 16
        let image = NSImage(size: menuBar.size, flipped: false) { rect in
            menuBar.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.35)
            let band = NSRect(x: rect.minX, y: rect.minY - rect.height * 0.6 + phase * rect.height * 1.6,
                              width: rect.width, height: rect.height * 0.6)
            let highlight = NSImage(size: rect.size, flipped: false) { inner in
                NSBezierPath(rect: band).setClip()
                menuBar.draw(in: inner)
                NSGraphicsContext.current?.compositingOperation = .destinationIn
                NSGradient(colors: [.clear, .black, .clear])?.draw(in: band, angle: 90)
                return true
            }
            highlight.draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func load(_ name: String) -> NSImage {
        // SwiftPM copies loose PNGs; load their URLs instead of relying on named asset lookup.
        guard let url = appResourceBundle.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { preconditionFailure("Missing bundled image: \(name)") }
        return image
    }
}
