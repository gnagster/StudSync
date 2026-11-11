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
        let hosting = OnboardingController(rootView: SetupView(store: store, close: close, step: step))
        // Explicit fitting: automatic preferredContentSize sizing looped endlessly in constraint passes while a sync updated the page.
        hosting.sizingOptions = []
        hosting.view.frame.size = hosting.fittingSize
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

/// A window whose content view controller resizes the window to its content.
@MainActor protocol WindowFitting { func fitWindow(animate: Bool) }

extension NSHostingController {
    var fittingSize: NSSize { sizeThatFits(in: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)) }
}

extension NSWindow {
    /// Resizes to the given content size, keeping the top edge in place.
    func fit(contentSize size: NSSize, animate: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        let target = frameRect(forContentRect: NSRect(origin: .zero, size: size))
        guard target.size != frame.size else { return }
        var frame = frame
        frame.origin.y += frame.height - target.height
        frame.size = target.size
        setFrame(frame, display: true, animate: animate && isVisible)
    }
}

/// The setup assistant; it refits the window when its page or content changes.
final class OnboardingController: NSHostingController<SetupView>, WindowFitting {
    func fitWindow(animate: Bool) { view.window?.fit(contentSize: fittingSize, animate: animate) }
}

/// Preferences tabs, each sized to its content: the window grows or shrinks when the tab changes, keeping its top edge.
final class SettingsTabController: NSTabViewController, WindowFitting {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(animate: true)
    }

    func fitWindow(animate: Bool) {
        guard let window = view.window,
              let hosting = tabViewItems[safe: selectedTabViewItemIndex]?.viewController as? NSHostingController<SettingsTabView> else { return }
        window.fit(contentSize: hosting.fittingSize, animate: animate)
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
            MenuBarIcon(state: store.isBusy ? .syncing : store.needsAttention ? .error : .idle)
        }
        .menuBarExtraStyle(.window)
    }
}

enum MenuBarIconState: CaseIterable { case idle, syncing, error }

/// The menu-bar logo: template while idle, animated while busy, red when something needs attention.
/// Launch with `-StudSyncIconDemo YES` to cycle through all states.
struct MenuBarIcon: View {
    let state: MenuBarIconState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame = 0
    @State private var demoState: MenuBarIconState?
    private let demo = UserDefaults.standard.bool(forKey: "StudSyncIconDemo")

    var body: some View {
        let shown = demoState ?? state
        Image(nsImage: image(for: shown))
            .renderingMode(shown == .error ? .original : .template)
            .accessibilityLabel("StudSync")
            .task(id: shown == .syncing && !reduceMotion) {
                frame = 0
                guard shown == .syncing && !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(75))
                    frame = (frame + 1) % AppImages.menuBarSyncFrames.count
                }
            }
            .task {
                guard demo else { return }
                while !Task.isCancelled {
                    for next in MenuBarIconState.allCases {
                        demoState = next
                        try? await Task.sleep(for: .seconds(3))
                    }
                }
            }
    }

    private func image(for state: MenuBarIconState) -> NSImage {
        switch state {
        case .idle: AppImages.menuBar
        case .syncing: reduceMotion ? AppImages.menuBar : AppImages.menuBarSyncFrames[frame]
        case .error: AppImages.menuBarError
        }
    }
}

extension View {
    /// Refits content-sized windows after `value` changes, once SwiftUI has applied the change.
    func refitsWindow<Value: Equatable>(on value: Value) -> some View {
        onChange(of: value) {
            // A run-loop block rather than the main queue, so it also runs inside nested run loops.
            RunLoop.main.perform {
                MainActor.assumeIsolated {
                    for window in NSApp.windows where window.isVisible { (window.contentViewController as? WindowFitting)?.fitWindow(animate: true) }
                }
            }
        }
    }
}
