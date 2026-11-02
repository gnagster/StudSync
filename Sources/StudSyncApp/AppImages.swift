import AppKit

@MainActor
enum AppImages {
    static let logo = load("ClassicFold")
    static let menuBar: NSImage = {
        let image = load("MenuBarLogo")
        image.size = NSSize(width: 18 * image.size.width / image.size.height, height: 18)
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

    private static func load(_ name: String) -> NSImage {
        // SwiftPM copies loose PNGs; load their URLs instead of relying on named asset lookup.
        guard let url = appResourceBundle.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { preconditionFailure("Missing bundled image: \(name)") }
        return image
    }
}
