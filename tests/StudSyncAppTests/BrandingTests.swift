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
        #expect(AppImages.menuBar.size.height == 18)
        #expect(AppImages.menuBarError.size == AppImages.menuBar.size)
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
}
