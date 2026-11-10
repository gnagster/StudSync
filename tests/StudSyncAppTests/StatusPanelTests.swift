import Foundation
import AppKit
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
