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
        FileNotifications.shared.start(store)
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
        if store.preferences.setupComplete { present(settings ?? makeSettingsWindow(store)) } else { showOnboarding(store) }
    }

    /// Runs the onboarding from its first page, also after setup is complete.
    static func showOnboarding(_ store: AppStore) {
        settings?.close()
        let window = setup ?? {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = L("Set Up StudSync")
            window.isReleasedWhenClosed = false
            setup = window
            return window
        }()
        if !window.isVisible {
            window.contentViewController = makeOnboarding(store, close: { setup?.close() })
            window.center()
        }
        present(window)
    }

    /// The assistant sized to its current page; the window follows the page height.
    static func makeOnboarding(_ store: AppStore, step: SetupStep = .account, close: @escaping () -> Void = {}) -> NSViewController {
        let hosting = NSHostingController(rootView: SetupView(store: store, close: close, step: step))
        hosting.sizingOptions = .preferredContentSize
        hosting.view.frame.size = hosting.sizeThatFits(in: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        return hosting
    }

    private static func present(_ window: NSWindow) {
        if window !== setup { setup?.close() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func makeSettingsWindow(_ store: AppStore) -> NSWindow {
        let tabs = SettingsTabController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = false
        for tab in SettingsTab.allCases {
            let hosting = NSHostingController(rootView: SettingsTabView(tab: tab, store: store))
            hosting.sizingOptions = []
            let item = NSTabViewItem(viewController: hosting)
            item.label = L(tab.title)
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: L(tab.title))
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.title = L("StudSync Settings")
        window.isReleasedWhenClosed = false
        tabs.fitWindow(animate: false)
        window.center()
        settings = window
        return window
    }
}

/// Preferences tabs, each sized to its content: the window grows or shrinks when the tab changes, keeping its top edge.
final class SettingsTabController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(animate: true)
    }

    func fitWindow(animate: Bool) {
        guard let window = view.window,
              let hosting = tabViewItems[safe: selectedTabViewItemIndex]?.viewController as? NSHostingController<SettingsTabView> else { return }
        let size = hosting.sizeThatFits(in: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        guard size.width > 0, size.height > 0 else { return }
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var frame = window.frame
        frame.origin.y += frame.height - target.height
        frame.size = target.size
        window.setFrame(frame, display: true, animate: animate && window.isVisible)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
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
