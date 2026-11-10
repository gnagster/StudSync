import SwiftUI
import AppKit
import Network

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let connectivity = NWPathMonitor()
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppUpdates.shared.start()
        let store = AppStore.shared
        connectivity.pathUpdateHandler = { path in
            let available = path.status == .satisfied
            Task { @MainActor in store.networkChanged(available: available) }
        }
        connectivity.start(queue: DispatchQueue(label: "com.gnagster.StudSync.connectivity"))
        store.start()
        if !store.preferences.setupComplete { AppWindows.show(store) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { connectivity.cancel() }
}

@MainActor
enum AppWindows {
    private static var setup: NSWindow?
    private static var settings: NSWindow?

    /// Onboarding until setup is complete, then the native preferences window.
    static func show(_ store: AppStore) {
        let window = store.preferences.setupComplete ? settingsWindow(store) : setupWindow(store)
        if window !== setup { setup?.close() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func setupWindow(_ store: AppStore) -> NSWindow {
        if let setup { return setup }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "StudSync"
        window.minSize = NSSize(width: 540, height: 550)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SetupView(store: store))
        window.center()
        setup = window
        return window
    }

    private static func settingsWindow(_ store: AppStore) -> NSWindow {
        if let settings { return settings }
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let item = NSTabViewItem(viewController: NSHostingController(rootView: SettingsTabView(tab: tab, store: store)))
            item.label = L(tab.title)
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: L(tab.title))
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center(); window.setFrameAutosaveName("StudSyncPreferences")
        settings = window
        return window
    }
}

@main
struct StudSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore.shared
    var body: some Scene {
        MenuBarExtra {
            StatusPanel(store: store)
        } label: {
            Image(nsImage: store.needsAttention ? AppImages.menuBarError : AppImages.menuBar)
                .renderingMode(store.needsAttention ? .original : .template)
                .accessibilityLabel("StudSync")
        }
        .menuBarExtraStyle(.window)
    }
}
