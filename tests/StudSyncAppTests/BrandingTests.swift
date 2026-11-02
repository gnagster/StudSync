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
        let rendered = try #require(logo.cgImage)
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
}
