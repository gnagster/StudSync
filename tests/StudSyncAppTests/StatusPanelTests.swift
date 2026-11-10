import Foundation
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
