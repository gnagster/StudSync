import Foundation
import AppKit
import SwiftUI
import Testing
import StudSyncCore
@testable import StudSyncApp

@MainActor struct StatusPanelTests {
    @Test func courseNameIsTheFirstFolderBelowTheSyncRoot() {
        #expect(StatusPanel.courseName(for: "/Users/a/Stud.IP/Analysis I/Folien/v1.pdf", root: "/Users/a/Stud.IP") == "Analysis I")
        #expect(StatusPanel.courseName(for: "/Users/a/Stud.IP/Analysis I/v1.pdf", root: "/Users/a/Stud.IP/") == "Analysis I")
        #expect(StatusPanel.courseName(for: "/Users/a/Stud.IP/loose.pdf", root: "/Users/a/Stud.IP") == nil)
        #expect(StatusPanel.courseName(for: "/Users/a/Stud.IPx/Kurs/v1.pdf", root: "/Users/a/Stud.IP") == nil)
        #expect(StatusPanel.courseName(for: "/Users/a/Stud.IP/Kurs/v1.pdf", root: "") == nil)
    }

    @Test func courseNameMatchesASyncRootReachedThroughASymlink() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let real = base.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real.appendingPathComponent("Analysis I"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let link = base.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        // Sync writes resolved paths while preferences keep the chosen (linked) folder.
        let file = real.resolvingSymlinksInPath().appendingPathComponent("Analysis I/v1.pdf").path
        #expect(StatusPanel.courseName(for: file, root: link.path) == "Analysis I")
    }

    @Test func changesAreGroupedByConsecutiveDayInOrder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        func change(_ name: String, _ day: Int, _ hour: Int) throws -> Change {
            var item = Change(name: name, path: "/x/\(name)", conflict: false)
            item.date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour)))
            return item
        }
        let groups = StatusPanel.dayGroups([try change("a", 10, 12), try change("b", 10, 8), try change("c", 9, 23)], calendar: calendar)
        #expect(groups.map { $0.changes.map(\.name) } == [["a", "b"], ["c"]])
        #expect(groups.map(\.day) == [calendar.startOfDay(for: groups[0].changes[0].date), calendar.startOfDay(for: groups[1].changes[0].date)])
    }
}

@MainActor struct FileNotificationTests {
    @Test func oneCourseNamesTheCourseAndListsAtMostThreeFiles() {
        let changes = ["a.pdf", "b.pdf", "c.pdf", "d.pdf"].map { Change(name: $0, path: "/r/Analysis I/\($0)", conflict: false) }
        let text = FileNotifications.content(for: changes, root: "/r")
        #expect(text.title.contains("Analysis I"))
        #expect(text.body.hasPrefix("a.pdf, b.pdf, c.pdf, "))
        #expect(!text.body.contains("d.pdf"))
    }

    @Test func severalCoursesShowACountAndMentionPreservedEdits() {
        let changes = [Change(name: "a.pdf", path: "/r/A/a.pdf", conflict: false), Change(name: "b.pdf", path: "/r/B/b.pdf", conflict: true)]
        let text = FileNotifications.content(for: changes, root: "/r")
        #expect(text.title.contains("2"))
        #expect(text.body.contains("\n"))
    }
}

@MainActor struct SettingsWindowTests {
    @Test func preferencesWindowIsTitledAndEveryTabFitsItsContent() throws {
        _ = NSApplication.shared
        let store = AppStore(support: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                             readCredentials: { nil }, writeCredentials: { _ in },
                             readLaunchAtLogin: { .notRegistered }, updateLaunchAtLogin: { _ in })
        let window = AppWindows.makeSettingsWindow(store)
        defer { window.close() }
        #expect(window.title == L("StudSync Settings"))
        let tabs = try #require(window.contentViewController as? SettingsTabController)
        var heights: [CGFloat] = []
        for index in tabs.tabViewItems.indices {
            tabs.selectedTabViewItemIndex = index
            tabs.fitWindow(animate: false)
            let content = window.contentRect(forFrameRect: window.frame)
            #expect(abs(content.width - SettingsLayout.width) < 1, "tab \(index) width \(content.width)")
            #expect(content.height < 560, "tab \(index) height \(content.height)")
            heights.append(content.height)
        }
        print("settings tab content heights:", heights)
        #expect(Set(heights.map { Int($0) }).count > 1)
    }
}

@MainActor struct OnboardingWindowTests {
    @Test func everyOnboardingPageFitsAtSettingsWidth() throws {
        _ = NSApplication.shared
        let store = try ReadmeScreenshots.sampleStore()
        var heights: [CGFloat] = []
        for step in SetupStep.allCases {
            let window = NSWindow(contentViewController: AppWindows.makeOnboarding(store, step: step))
            defer { window.close() }
            let content = window.contentRect(forFrameRect: window.frame)
            #expect(abs(content.width - SettingsLayout.width) < 1, "\(step) width \(content.width)")
            #expect(content.height > 200 && content.height < 600, "\(step) height \(content.height)")
            heights.append(content.height)
        }
        print("onboarding page heights:", heights)
    }
}

@MainActor struct OnboardingDuringSyncTests {
    /// Regression: opening the assistant while a sync updated the store crashed in an endless constraint pass.
    @Test func onboardingSurvivesStoreUpdatesWhileOnScreen() async throws {
        _ = NSApplication.shared
        let store = try ReadmeScreenshots.sampleStore()
        for step in SetupStep.allCases {
            let controller = AppWindows.makeOnboarding(store, step: step)
            // Automatic sizing (preferredContentSize) caused the endless constraint passes.
            #expect((controller as? NSHostingController<SetupView>)?.sizingOptions.isEmpty == true)
            let window = NSWindow(contentViewController: controller)
            window.orderFrontRegardless()
            for round in 0..<6 {
                store.isBusy = round.isMultiple(of: 2)
                store.total = 40; store.completed = round * 6
                store.status = round.isMultiple(of: 2) ? "Analysis I" : "Up to date"
                await spinRunLoop(0.05)
                window.layoutIfNeeded()
            }
            await spinRunLoop(0.6) // let the animated refit finish
            let content = window.contentRect(forFrameRect: window.frame)
            #expect(abs(content.width - SettingsLayout.width) < 1, "\(step) width \(content.width)")
            let fitted = try #require(controller as? OnboardingController).fittingSize
            #expect(abs(content.height - fitted.height) < 1, "\(step) height \(content.height) vs \(fitted.height)")
            window.close()
        }
    }
}

@MainActor struct ContentFitTests {
    /// Regression: the settings window kept its height when the open tab's content changed.
    @Test func settingsWindowRefitsWhenTheOpenTabChanges() async throws {
        _ = NSApplication.shared
        let store = try ReadmeScreenshots.sampleStore()
        let window = AppWindows.makeSettingsWindow(store)
        defer { window.close() }
        let tabs = try #require(window.contentViewController as? SettingsTabController)
        tabs.selectedTabViewItemIndex = try #require(SettingsTab.allCases.firstIndex(of: .account))
        window.orderFrontRegardless()
        await spinRunLoop(0.6)
        let signedIn = window.contentRect(forFrameRect: window.frame).height
        store.signedIn = false
        await spinRunLoop(0.8)
        let signedOut = window.contentRect(forFrameRect: window.frame).height
        let fitted = try #require(tabs.tabViewItems[tabs.selectedTabViewItemIndex].viewController as? NSHostingController<SettingsTabView>).fittingSize
        #expect(signedOut != signedIn)
        #expect(abs(signedOut - fitted.height) < 1, "\(signedOut) vs \(fitted.height)")
    }

    /// Regression: many course folders grew the menu-bar panel beyond the screen.
    @Test func panelCourseListScrollsBeyondItsLimit() async throws {
        _ = NSApplication.shared
        func height(folders count: Int) async throws -> CGFloat {
            let store = try ReadmeScreenshots.sampleStore()
            let root = URL(fileURLWithPath: store.preferences.destination)
            for index in 0..<count { try FileManager.default.createDirectory(at: root.appendingPathComponent("Kurs \(index)"), withIntermediateDirectories: true) }
            let panel = NSHostingController(rootView: StatusPanel(store: store))
            let window = NSWindow(contentViewController: panel)
            defer { window.close() }
            window.orderFrontRegardless()
            await spinRunLoop(0.3)
            return panel.fittingSize.height
        }
        let atLimit = try await height(folders: StatusPanel.visibleFolders - 4) // sample data already has four folders
        let many = try await height(folders: 40)
        #expect(many - atLimit < 32, "\(atLimit) vs \(many)")
    }
}

/// Synchronous so it may run the loop from the async helper below.
@MainActor private func runMainLoop(until date: Date) { RunLoop.main.run(until: date) }

/// Runs the main run loop for `seconds` in short slices, yielding the main actor in between so tests that
/// run in parallel and poll with wall-clock deadlines (AppStoreTests) are not starved.
@MainActor func spinRunLoop(_ seconds: TimeInterval) async {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        runMainLoop(until: min(deadline, Date().addingTimeInterval(0.01)))
        await Task.yield()
    }
}
