import AppKit
import Foundation
import Observation
import Dispatch
import Synchronization
import ServiceManagement
import StudSyncCore

@MainActor @Observable
final class AppStore {
    static let shared = AppStore()
    var preferences = Preferences()
    var courses: [Course] = []
    var semesters: [Semester] = []
    private(set) var semesterID = ""
    private var semesterCourseIDs: Set<String>?
    private var catalogLoaded = false
    var visibleCourses: [Course] { courses.filter { semesterCourseIDs?.contains($0.id) ?? true } }
    var username = ""
    var password = ""
    var message: String? {
        get {
            let entries = MessageSource.allCases.compactMap { feedback[$0] }
            if let hint = entries.first(where: \.isSignInHint) {
                return showWebLogin ? hint.text : "Use University web login… to sign in again."
            }
            return (entries.first(where: requiresAttention) ?? entries.first)?.text
        }
        set { feedback[.operation] = newValue.map { Feedback(text: $0) } }
    }
    var needsAttention: Bool {
        feedback.values.contains(where: requiresAttention)
    }
    var messages: [String] {
        var result = message.map { [$0] } ?? []
        for entry in MessageSource.allCases.compactMap({ feedback[$0] }) where !entry.isSignInHint && !result.contains(entry.text) {
            result.append(entry.text)
        }
        return result
    }
    private enum MessageSource: CaseIterable { case settingsSave, settingsLoad, launchAtLogin, sync, catalog, operation }
    private struct Feedback { let text: String; var isOffline = false; var isTransportFailure = false; var isSignInHint = false }
    // Independent failures clear only when their corresponding operation recovers.
    private var feedback: [MessageSource: Feedback] = [:]
    private func requiresAttention(_ entry: Feedback) -> Bool {
        !entry.isOffline && !(entry.isTransportFailure && networkAvailable == false)
    }
    var status = "Ready"
    var isBusy = false
    var paused = false
    var signedIn = false
    var completed = 0
    var total = 0
    var bytes: Int64 = 0
    var showWebLogin = false {
        didSet { if showWebLogin != oldValue { webLoginAttempt = UUID() } }
    }
    private(set) var webLoginAttempt = UUID()
    private(set) var launchAtLoginStatus: SMAppService.Status
    var changes: [Change] { preferences.changes }
    let client: StudIPClient
    var nextSync: Date?
    /// Called once per sync with the files it changed; the app wires this to Notification Center.
    var notifyNewFiles: (@MainActor ([Change]) -> Void)?
    private var engine: SyncEngine?
    private var storageError: String?
    private var task: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var reconnectPending = false
    private var retrySyncWhenOnline = false
    private var networkAvailable: Bool?
    private var networkRecoveryPending = false
    private let support: URL
    private let readCredentials: @Sendable () throws -> Credentials?
    private let writeCredentials: @Sendable (Credentials) throws -> Void
    private let credentialQueue = DispatchQueue(label: "com.gnagster.StudSync.credentials")
    private let readLaunchAtLogin: () -> SMAppService.Status
    private let updateLaunchAtLogin: (Bool) throws -> Void
    private var settingsURL: URL { support.appendingPathComponent("settings.json") }

    init(support: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StudSync"),
         client: StudIPClient = StudIPClient(),
         readCredentials: @escaping @Sendable () throws -> Credentials? = { try CredentialVault.read() },
         writeCredentials: @escaping @Sendable (Credentials) throws -> Void = { try CredentialVault.save($0) },
         readLaunchAtLogin: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         updateLaunchAtLogin: @escaping (Bool) throws -> Void = { enabled in
             if enabled { try SMAppService.mainApp.register() }
             else { try SMAppService.mainApp.unregister() }
         }) {
        self.support = support; self.client = client
        self.readCredentials = readCredentials; self.writeCredentials = writeCredentials
        self.readLaunchAtLogin = readLaunchAtLogin; self.updateLaunchAtLogin = updateLaunchAtLogin
        launchAtLoginStatus = readLaunchAtLogin()
        do { engine = try SyncEngine(manifest: support.appendingPathComponent("manifest.json")) }
        catch { storageError = error.localizedDescription; showError(error) }
        do {
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                preferences = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: settingsURL))
            }
        } catch { showError(error, source: .settingsLoad) }
    }

    func start() {
        guard !isBusy else { return }
        guard engine != nil else { message = storageError; return }
        guard feedback[.settingsLoad] == nil else { status = "Settings need attention"; return }
        if !username.isEmpty, !password.isEmpty { connect(); return }
        let read = readCredentials
        isBusy = true; status = "Unlocking saved credentials…"
        task = Task {
            do {
                // Keychain may wait for system authorization; keep the app's main actor free.
                let saved = try await credentialOperation { try read() }
                try Task.checkCancellation()
                isBusy = false
                guard let saved else { message = nil; status = "Sign-in required"; return }
                username = saved.username; password = saved.password
                connect()
            } catch {
                isBusy = false
                if error is CancellationError || (error as? URLError)?.code == .cancelled { status = "Cancelled" }
                else { status = "Sign-in required"; showError(error) }
            }
        }
    }
    func connect() {
        guard !isBusy else { return }
        guard engine != nil else { message = storageError; return }
        let credentials = Credentials(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        reconnectPending = false
        isBusy = true; status = "Signing in…"
        task = Task {
            var syncOnSuccess = false
            defer { isBusy = false; schedule(); if syncOnSuccess { sync() }; resumeAfterNetworkChange() }
            do {
                try await client.signIn(username: credentials.username, password: credentials.password)
                try Task.checkCancellation()
                let write = writeCredentials
                try await credentialOperation { try write(credentials) }
                try Task.checkCancellation()
                try await loadCourseCatalog()
                signedIn = true; status = "Ready"; message = nil; feedback[.catalog] = nil
                if preferences.selectedCourses.isEmpty && !preferences.setupComplete {
                    preferences.selectedCourses = Set(visibleCourses.map(\.id))
                }
                password = ""
                syncOnSuccess = preferences.setupComplete
            } catch {
                signedIn = false
                if error is CancellationError || (error as? URLError)?.code == .cancelled { status = "Cancelled"; return }
                reconnectPending = canRetryConnection(error)
                status = reconnectPending ? "Waiting for connection" : "Sign-in required"
                showError(error)
            }
        }
    }
    private func credentialOperation<Value: Sendable>(_ operation: @escaping @Sendable () throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let (stream, continuation) = AsyncThrowingStream<Value, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let cancelled = Mutex(false)
        continuation.onTermination = { _ in cancelled.withLock { $0 = true } }
        // Serialize writes; a cancelled older request must not finish after a newer save.
        credentialQueue.async {
            guard !cancelled.withLock({ $0 }) else { return }
            do { continuation.yield(try operation()); continuation.finish() }
            catch { continuation.finish(throwing: error) }
        }
        var iterator = stream.makeAsyncIterator()
        guard let result = try await iterator.next() else { throw CancellationError() }
        try Task.checkCancellation()
        return result
    }
    func finishSetup() {
        guard !isBusy, canStartSync else { return }
        let wasComplete = preferences.setupComplete
        preferences.setupComplete = true
        guard save() else {
            preferences.setupComplete = wasComplete
            status = "Settings need attention"
            return
        }
        schedule(); sync()
    }
    @discardableResult func save() -> Bool {
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path)
            if feedback[.settingsLoad] != nil {
                let backup = support.appendingPathComponent("settings-recovery-\(UUID().uuidString).json")
                try Data(contentsOf: settingsURL).write(to: backup, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            }
            try JSONEncoder().encode(preferences).write(to: settingsURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
            feedback[.settingsLoad] = nil; feedback[.settingsSave] = nil
            return true
        } catch { showError(error, source: .settingsSave); return false }
    }
    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = L("Choose sync folder")
        if panel.runModal() == .OK, let url = panel.url {
            preferences.destination = url.path; save()
        }
    }
    func reveal(_ path: String? = nil) {
        let path = path ?? preferences.destination
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
    var canStartSync: Bool { signedIn && !paused && !preferences.destination.isEmpty && !preferences.selectedCourses.isEmpty }
    var canSync: Bool { canStartSync && preferences.setupComplete }
    private func loadCourseCatalog(semesterID requested: String? = nil) async throws {
        let enrollment = try await client.courses()
        let terms = try await client.semesters()
        let preferred = requested ?? (catalogLoaded ? semesterID : terms.first(where: \.isCurrent)?.id ?? "")
        let selected = preferred.isEmpty || terms.contains(where: { $0.id == preferred }) ? preferred : ""
        let visible = selected.isEmpty ? enrollment : try await client.courses(semesterID: selected)
        try Task.checkCancellation()
        courses = enrollment; semesters = terms; semesterID = selected
        semesterCourseIDs = selected.isEmpty ? nil : Set(visible.map(\.id))
        catalogLoaded = true
    }
    func refreshCourses(semesterID: String? = nil) {
        guard !isBusy, signedIn else { return }
        retrySyncWhenOnline = false
        isBusy = true; status = "Loading courses…"
        task = Task {
            defer { isBusy = false; schedule(); resumeAfterNetworkChange() }
            do { try await loadCourseCatalog(semesterID: semesterID); feedback[.catalog] = nil; status = "Ready" }
            catch { reportSyncFailure(error, source: .catalog) }
        }
    }
    private func reportSyncFailure(_ error: Error, source: MessageSource = .sync) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { status = "Cancelled"; return }
        if case StudSyncError.authentication = error {
            signedIn = false; reconnectPending = false; status = "Sign-in required"
        } else { status = "Sync needs attention" }
        retrySyncWhenOnline = canRetryConnection(error)
        showError(error, source: source)
    }
    private func showError(_ error: Error, source: MessageSource = .operation) {
        // Retryable server failures still need attention; only connectivity failures stay monochrome.
        let offline = (error as? URLError).map { [.notConnectedToInternet, .networkConnectionLost].contains($0.code) } ?? false
        feedback[source] = Feedback(text: error.localizedDescription, isOffline: offline,
                                    isTransportFailure: error is URLError && canRetryConnection(error))
    }
    private func canRetryConnection(_ error: Error) -> Bool {
        if let error = error as? URLError {
            return [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                    .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(error.code)
        }
        if case StudSyncError.http(let code) = error { return (500..<600).contains(code) }
        return false
    }
    func networkChanged(available: Bool) {
        let wasOffline = networkAvailable == false
        networkAvailable = available
        if wasOffline && available { networkRecoveryPending = true }
        resumeAfterNetworkChange()
    }
    private func resumeAfterNetworkChange() {
        guard networkRecoveryPending, !isBusy else { return }
        networkRecoveryPending = false
        guard networkAvailable == true, !paused, preferences.setupComplete,
              preferences.intervalMinutes > 0, !preferences.destination.isEmpty,
              !preferences.selectedCourses.isEmpty else { return }
        if signedIn && retrySyncWhenOnline { sync() }
        else if reconnectPending { connect() }
    }
    func sync() {
        guard !isBusy, canSync, let engine else { return }
        retrySyncWhenOnline = false
        isBusy = true; completed = 0; total = 0; bytes = 0; status = "Checking courses…"
        let selectedIDs = preferences.selectedCourses
        let root = URL(fileURLWithPath: preferences.destination, isDirectory: true)
        task = Task {
            var fresh: [Change] = []
            defer { if !fresh.isEmpty { notifyNewFiles?(fresh) } }
            defer { isBusy = false; schedule(); resumeAfterNetworkChange() }
            do {
                courses = try await client.courses()
                let selected = courses.filter { selectedIDs.contains($0.id) }
                guard !selected.isEmpty else {
                    status = "Choose courses"
                    feedback[.sync] = Feedback(text: "No selected courses are currently available. Check your course selection in Settings.")
                    return
                }
                for course in selected {
                    try Task.checkCancellation()
                    status = course.title
                    let files = try await client.files(course: course)
                    total += files.count
                    for file in files {
                        try Task.checkCancellation()
                        if let change = try await engine.synchronize(file, courseID: course.id, root: root, fetch: { [client] in
                            try await client.download(id: file.id)
                        }) {
                            preferences.changes.insert(change, at: 0); fresh.append(change)
                            preferences.changes = Array(preferences.changes.prefix(200))
                            bytes += file.size
                            save()
                        }
                        completed += 1
                    }
                }
                preferences.lastSync = Date(); status = "Up to date"; feedback[.sync] = nil; save()
            } catch { reportSyncFailure(error) }
        }
    }
    func cancel() { task?.cancel() }
    func schedule() {
        timer?.cancel()
        nextSync = nil
        guard !paused, signedIn || reconnectPending, preferences.setupComplete,
              !preferences.destination.isEmpty, !preferences.selectedCourses.isEmpty, preferences.intervalMinutes > 0 else { return }
        let delay = Double(preferences.intervalMinutes * 60)
        nextSync = Date().addingTimeInterval(delay)
        timer = Task {
            do { try await Task.sleep(for: .seconds(delay)); runScheduledSync() } catch { }
        }
    }
    func runScheduledSync() {
        if signedIn { sync() } else if reconnectPending { connect() }
    }
    func setPaused(_ value: Bool) { paused = value; schedule() }
    func setLaunchAtLogin(_ value: Bool) {
        defer { refreshLaunchAtLogin() }
        do {
            try updateLaunchAtLogin(value)
            feedback[.launchAtLogin] = nil
        } catch { showError(error, source: .launchAtLogin) }
    }
    func refreshLaunchAtLogin() { launchAtLoginStatus = readLaunchAtLogin() }
    var launchAtLogin: Bool { launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval }
    func adoptWebSession(_ cookies: [HTTPCookie], attempt: UUID) {
        guard showWebLogin, attempt == webLoginAttempt, !isBusy else { return }
        guard engine != nil else { message = storageError; return }
        isBusy = true
        task = Task {
            var source = MessageSource.operation
            defer { isBusy = false; schedule(); resumeAfterNetworkChange() }
            signedIn = false; reconnectPending = false; retrySyncWhenOnline = false
            do {
                try await client.adopt(cookies: cookies)
                signedIn = true; reconnectPending = false; password = ""
                message = nil; source = .catalog
                try Task.checkCancellation()
                try await loadCourseCatalog()
                status = "Ready"; message = nil; feedback[.catalog] = nil; showWebLogin = false
                if !preferences.setupComplete && preferences.selectedCourses.isEmpty {
                    preferences.selectedCourses = Set(visibleCourses.map(\.id))
                }
            } catch {
                if Task.isCancelled { status = "Cancelled"; return }
                reportSyncFailure(error, source: source)
                if case StudSyncError.authentication = error {
                    feedback[source] = Feedback(text: "Finish signing into Stud.IP, then click Continue.", isSignInHint: true)
                }
            }
        }
    }
}
