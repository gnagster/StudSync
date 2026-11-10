import AppKit
import UserNotifications
import StudSyncCore

/// One quiet notification per sync that changed files. Clicking it reveals the files in Finder.
@MainActor
final class FileNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = FileNotifications()
    static let enabledKey = "notifyNewFiles"
    private var center: UNUserNotificationCenter { .current() }

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    func start(_ store: AppStore) {
        center.delegate = self
        store.notifyNewFiles = { [weak self, weak store] changes in
            guard let self, let store, self.enabled else { return }
            self.post(changes, root: store.preferences.destination)
        }
    }

    private func post(_ changes: [Change], root: String) {
        let text = Self.content(for: changes, root: root)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.userInfo = ["paths": changes.map(\.path)]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task {
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            try? await center.add(request)
        }
    }

    /// "New files in Analysis I" when one course changed, otherwise a count; the body names up to three files.
    static func content(for changes: [Change], root: String) -> (title: String, body: String) {
        let courses = Set(changes.compactMap { StatusPanel.courseName(for: $0.path, root: root) })
        let title = courses.count == 1 && changes.count > 0
            ? String(format: L("New files in %@"), courses.first!)
            : String(format: L("%lld new files"), changes.count)
        var names = changes.prefix(3).map(\.name)
        if changes.count > 3 { names.append(String(format: L("%lld more"), changes.count - 3)) }
        var body = names.joined(separator: ", ")
        if changes.contains(where: \.conflict) { body += "\n" + L("Local edits preserved") }
        return (title, body)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let paths = response.notification.request.content.userInfo["paths"] as? [String] ?? []
        await MainActor.run {
            let urls = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        }
    }
}
