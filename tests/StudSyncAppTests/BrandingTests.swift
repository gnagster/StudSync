import AppKit
import SwiftUI
import Testing
@testable import StudSyncApp

@MainActor struct BrandingTests {
    @Test func bundledLogoAndAppIconDecode() throws {
        for (name, extensionName) in [("ClassicFold", "png"), ("AppIcon", "icns"), ("MenuBarLogo", "png")] {
            let url = try #require(appResourceBundle.url(forResource: name, withExtension: extensionName))
            let image = try #require(NSImage(contentsOf: url))
            #expect(image.size.width > 0 && image.size.height > 0)
        }
    }

    @Test func logoRendersAndMenuBarMaskHasTransparentGapsAndRedErrorVariant() throws {
        let logo = ImageRenderer(content: Image(nsImage: AppImages.logo).resizable().frame(width: 72, height: 72))
        // A software CGContext avoids ImageRenderer.cgImage's Metal requirement on hosted Intel Macs.
        let context = try #require(CGContext(data: nil, width: 72, height: 72, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        logo.render { _, draw in draw(context) }
        let rendered = try #require(context.makeImage())
        let pixels = NSBitmapImageRep(cgImage: rendered)
        #expect(pixels.colorAt(x: 36, y: 36)!.alphaComponent > 0)
        #expect(AppImages.menuBar.isTemplate)
        #expect(!AppImages.menuBarError.isTemplate)
        #expect(AppImages.menuBar.size.height == 18 * 0.85)
        #expect(AppImages.menuBarError.size == AppImages.menuBar.size)
        #expect(AppImages.menuBarSyncFrames.count == 16)
        for frame in AppImages.menuBarSyncFrames {
            #expect(frame.isTemplate)
            #expect(frame.size == AppImages.menuBar.size)
        }
        // The band moves: the logo's middle is bright in some frames and dimmed in others.
        let middles = try AppImages.menuBarSyncFrames.map { frame in
            let data = try #require(frame.tiffRepresentation)
            let rep = try #require(NSBitmapImageRep(data: data))
            return try #require(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)).alphaComponent
        }
        #expect(middles.max()! > 0.8)
        #expect(middles.min()! < 0.5)
        let maskData = try #require(AppImages.menuBar.tiffRepresentation)
        let mask = try #require(NSBitmapImageRep(data: maskData))
        #expect(mask.colorAt(x: 0, y: 0)!.alphaComponent == 0)
        let solid = try #require(mask.colorAt(x: mask.pixelsWide / 2, y: mask.pixelsHigh / 2))
        #expect(solid.alphaComponent > 0.9)
        let redData = try #require(AppImages.menuBarError.tiffRepresentation)
        let red = try #require(NSBitmapImageRep(data: redData))
        let errorColor = try #require(red.colorAt(x: red.pixelsWide / 2, y: red.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        #expect(errorColor.alphaComponent > 0.9)
        #expect(errorColor.redComponent > errorColor.greenComponent * 2)
        #expect(errorColor.redComponent > errorColor.blueComponent * 2)
        #expect(red.colorAt(x: 0, y: 0)!.alphaComponent == 0)
    }

    @Test func menuBarPanelAttachesToScreenTopAndKeepsItsHorizontalPositionOnResize() throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let frame = NSRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY, width: 380, height: 400)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = MenuBarPanelAnchor.AnchorView()
        let top = min(screen.visibleFrame.maxY, screen.frame.maxY - NSStatusBar.system.thickness)
        #expect(abs(window.frame.maxY - top) <= 0.5)
        #expect(window.frame.minX == frame.minX)
        window.setContentSize(NSSize(width: 380, height: 500))
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        #expect(abs(window.frame.maxY - top) <= 0.5)
        #expect(window.frame.minX == frame.minX)
    }

    /// Regression: after a sync the panel kept its taller progress-bar height, leaving bare glass above and below.
    @Test func menuBarPanelShrinksToItsContent() async throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let window = NSWindow(contentRect: NSRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY, width: 360, height: 680),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let anchor = MenuBarPanelAnchor.AnchorView(frame: NSRect(x: 0, y: 22, width: 360, height: 680))
        window.contentView = NSView()
        window.contentView?.addSubview(anchor)
        let top = min(screen.visibleFrame.maxY, screen.frame.maxY - NSStatusBar.system.thickness)
        await spinRunLoop(0.1)
        #expect(window.frame.height == 680)
        anchor.setFrameSize(NSSize(width: 360, height: 636)) // the content shrank; the window did not
        await spinRunLoop(0.1)
        #expect(window.frame.height == 636)
        #expect(abs(window.frame.maxY - top) <= 0.5)
    }
}
