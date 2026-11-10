import Foundation
import AppKit
import SwiftUI
import Testing
import StudSyncCore
@testable import StudSyncApp

/// Regenerates the README screenshots from sample data, in English and German:
/// `STUDSYNC_SCREENSHOTS=docs/images swift test --filter ReadmeScreenshots`
private final class ActiveWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

@MainActor struct ReadmeScreenshots {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STUDSYNC_SCREENSHOTS"] != nil))
    func renderReadmeScreenshots() throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["STUDSYNC_SCREENSHOTS"]), isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        UserDefaults.standard.setVolatileDomain(["AppleAccentColor": 4, "AppleHighlightColor": "0.698039 0.843137 1.000000 Blue"], forName: UserDefaults.argumentDomain)
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        defer { localizationBundle = appResourceBundle }
        for language in ["en", "de"] {
            localizationBundle = try #require(appResourceBundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)))
            let store = try Self.sampleStore()
            let suffix = language == "en" ? "" : ".de"

            let panel = NSHostingController(rootView: StatusPanel(store: store).background(.background))
            panel.view.frame.size = panel.sizeThatFits(in: NSSize(width: 360, height: CGFloat.greatestFiniteMagnitude))
            let panelWindow = ActiveWindow(contentViewController: panel)
            panelWindow.styleMask = [.borderless]
            defer { panelWindow.close() }
            try Self.write(Self.settle(panelWindow).contentView!, to: output.appendingPathComponent("panel\(suffix).png"))

            // Shown as it would be for a folder in Documents; the settings window never reads it.
            store.preferences.destination = NSHomeDirectory() + "/Documents/Stud.IP"

            // Courses tab: switches would draw as inactive because a test process cannot become the active app.
            let settings = Self.active(AppWindows.makeSettingsWindow(store))
            (settings.contentViewController as? SettingsTabController)?.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: .courses)!
            (settings.contentViewController as? SettingsTabController)?.fitWindow(animate: false)
            defer { settings.close() }
            try Self.write(Self.frameView(of: settings), to: output.appendingPathComponent("settings\(suffix).png"))

            let onboarding = ActiveWindow(contentViewController: AppWindows.makeOnboarding(store, step: .folder))
            onboarding.styleMask = [.titled, .closable]
            onboarding.title = L("Set Up StudSync")
            defer { onboarding.close() }
            try Self.write(Self.frameView(of: onboarding), to: output.appendingPathComponent("onboarding\(suffix).png"))
        }
    }

    /// Plausible first-semester data; nothing here comes from a real account.
    static func sampleStore() throws -> AppStore {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = support.appendingPathComponent("Stud.IP", isDirectory: true)
        let courses = ["Analysis I", "Lineare Algebra I", "Informatik I", "Experimentalphysik I", "Mathematisches Propädeutikum"]
        for course in courses.prefix(4) { try FileManager.default.createDirectory(at: root.appendingPathComponent(course), withIntermediateDirectories: true) }
        let store = AppStore(support: support, readCredentials: { nil }, writeCredentials: { _ in },
                             readLaunchAtLogin: { .enabled }, updateLaunchAtLogin: { _ in })
        store.signedIn = true
        store.username = "max.mustermann"
        store.status = "Up to date"
        store.courses = courses.enumerated().map { Course(id: "\($0.offset)", title: $0.element) }
        store.semesters = [Semester(id: "ws", title: "WiSe 2026/27", isCurrent: true), Semester(id: "ss", title: "SoSe 2026", isCurrent: false)]
        store.preferences.destination = root.path
        store.preferences.selectedCourses = ["0", "1", "2", "3"]
        store.preferences.setupComplete = true
        store.preferences.lastSync = Date().addingTimeInterval(-12 * 60)
        store.nextSync = Date().addingTimeInterval(48 * 60)
        func change(_ course: String, _ file: String, hoursAgo: Double) -> Change {
            var change = Change(name: file, path: root.appendingPathComponent(course).appendingPathComponent(file).path, conflict: false)
            change.date = Date().addingTimeInterval(-hoursAgo * 3600)
            return change
        }
        store.preferences.changes = [
            change("Analysis I", "Übungsblatt 04.pdf", hoursAgo: 0.2),
            change("Analysis I", "Vorlesung 07 – Folgen.pdf", hoursAgo: 0.2),
            change("Informatik I", "Folien Woche 4.pdf", hoursAgo: 1.5),
            change("Lineare Algebra I", "Skript Kapitel 3.pdf", hoursAgo: 26),
        ]
        return store
    }

    /// The window including its title bar and toolbar.
    static func frameView(of window: NSWindow) throws -> NSView {
        try #require(settle(window).contentView?.superview)
    }

    /// A test process cannot become active; this copy draws as the active window so controls show their real state.
    static func active(_ window: NSWindow) -> NSWindow {
        let controller = window.contentViewController
        window.contentViewController = nil
        window.close()
        let copy = ActiveWindow(contentViewController: controller!)
        copy.styleMask = window.styleMask
        copy.toolbarStyle = window.toolbarStyle
        copy.title = window.title
        (controller as? SettingsTabController)?.fitWindow(animate: false)
        return copy
    }

    /// Puts the window on screen briefly so controls finish drawing their state.
    static func settle(_ window: NSWindow) -> NSWindow {
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        window.displayIfNeeded()
        return window
    }

    static func write(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}
