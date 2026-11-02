import Foundation
import Testing
import Observation
import ServiceManagement
import StudSyncCore
@testable import StudSyncApp

private final class ConnectionFixture: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: (@Sendable (URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.response!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class RequestCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int { lock.withLock { value += 1; return value } }
    var total: Int { lock.withLock { value } }
}

private final class CredentialFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: Credentials?
    private var readOnMain: Bool?
    private var writeOnMain: Bool?
    let release = DispatchSemaphore(value: 0)
    let blockRead: Bool
    let blockWrite: Bool
    init(credentials: Credentials? = nil, blockRead: Bool = false, blockWrite: Bool = false) {
        self.credentials = credentials; self.blockRead = blockRead; self.blockWrite = blockWrite
    }
    var saved: Credentials? { lock.withLock { credentials } }
    var readStartedOnMain: Bool? { lock.withLock { readOnMain } }
    var writeStartedOnMain: Bool? { lock.withLock { writeOnMain } }
    func read() throws -> Credentials? {
        lock.withLock { readOnMain = Thread.isMainThread }
        if blockRead, release.wait(timeout: .now() + 10) != .success { throw URLError(.timedOut) }
        return saved
    }
    func write(_ value: Credentials) throws {
        lock.withLock { writeOnMain = Thread.isMainThread }
        if blockWrite, release.wait(timeout: .now() + 10) != .success { throw URLError(.timedOut) }
        lock.withLock { credentials = value }
    }
}

private final class SemesterFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var offline = false
    private var files: Set<String> = []
    var requestedFiles: Set<String> { lock.withLock { files } }
    func setOffline(_ value: Bool) { lock.withLock { offline = value } }
    func clearRequests() { lock.withLock { files = [] } }
    func respond(_ request: URLRequest) throws -> (Int, String) {
        try lock.withLock {
            let url = request.url!
            let path = url.path
            if path.isEmpty || path == "/" || path == "/dispatch.php/login" {
                return (200, #"<form action="/dispatch.php/login"><input name="loginname"><input name="password"></form>"#)
            }
            if path.hasSuffix("users/me") { return (200, #"{"data":{"id":"ee"}}"#) }
            if path.hasSuffix("semesters") {
                return (200, #"{"data":[{"id":"aa","attributes":{"title":"Past","start":"2025-04-01","is-current":false}},{"id":"bb","attributes":{"title":"Current","start":"2026-10-01","is-current":true}}]}"#)
            }
            if path.hasSuffix("/courses") {
                let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "filter[semester]" })?.value
                if term == "aa" && offline { throw URLError(.notConnectedToInternet) }
                let courses = term == "aa" ? [("dd", "Past course")] : term == "bb" ? [("cc", "Current course")] : [("dd", "Past course"), ("cc", "Current course")]
                let body = try JSONSerialization.data(withJSONObject: ["data": courses.map { ["id": $0.0, "attributes": ["title": $0.1]] }])
                return (200, String(decoding: body, as: UTF8.self))
            }
            files.insert(path)
            return (200, #"{"data":[]}"#)
        }
    }
}

@Suite(.serialized) @MainActor
struct AppStoreTests {
    private func store(support: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                       writeCredentials: @escaping @Sendable (Credentials) throws -> Void = { _ in }) -> AppStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ConnectionFixture.self]
        let store = AppStore(support: support,
                             client: StudIPClient(session: URLSession(configuration: config)),
                             readCredentials: { nil }, writeCredentials: writeCredentials)
        store.username = "fixture"; store.password = "not-real"
        store.preferences.setupComplete = true
        store.preferences.destination = support.appendingPathComponent("sync").path
        store.preferences.selectedCourses = ["cc"]
        return store
    }
    private func serveCourses(_ courses: [Course]) throws {
        let data = try JSONSerialization.data(withJSONObject: ["data": courses.map { ["id": $0.id, "attributes": ["title": $0.title]] }])
        let body = String(decoding: data, as: UTF8.self)
        ConnectionFixture.response = { request in
            let path = request.url!.path
            if path.isEmpty || path == "/" || path == "/dispatch.php/login" {
                return (200, #"<form action="/dispatch.php/login"><input name="loginname"><input name="password"></form>"#)
            }
            if path.hasSuffix("users/me") { return (200, #"{"data":{"id":"bb"}}"#) }
            if path.hasSuffix("/courses") { return (200, body) }
            return (200, #"{"data":[]}"#)
        }
    }
    private func waitForConnection(_ store: AppStore, timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while store.isBusy && Date() < deadline { await Task.yield() }
        try #require(!store.isBusy)
    }
    @Test func offlineStartupSchedulesReconnectAndRejectedCredentialsStopIt() async throws {
        ConnectionFixture.response = { _ in throw URLError(.notConnectedToInternet) }
        let store = store()
        defer { store.setPaused(true) }
        store.start()
        try await waitForConnection(store)
        #expect(!store.signedIn)
        #expect(store.status == "Waiting for connection")
        #expect(store.nextSync != nil)

        // Fire the actual timer callback without waiting an hour; 401 proves a new request ran.
        ConnectionFixture.response = { _ in (401, "") }
        store.runScheduledSync()
        try await waitForConnection(store)
        #expect(store.status == "Sign-in required")
        #expect(store.nextSync == nil)
    }
    @Test func manualAndPausedModesDoNotRetryOfflineStartup() async throws {
        ConnectionFixture.response = { _ in throw URLError(.notConnectedToInternet) }
        for paused in [true, false] {
            let store = store()
            store.preferences.intervalMinutes = paused ? 60 : 0
            store.setPaused(paused)
            store.start()
            try await waitForConnection(store)
            #expect(store.nextSync == nil)
        }
    }
    @Test func successfulWebLoginReplacesPendingPasswordReconnectWithSync() async throws {
        ConnectionFixture.response = { _ in throw URLError(.notConnectedToInternet) }
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = store(support: support)
        defer { store.setPaused(true); try? FileManager.default.removeItem(at: support) }
        store.start()
        try await waitForConnection(store)
        #expect(store.nextSync != nil)

        ConnectionFixture.response = { request in
            let path = request.url!.path
            #expect(path.hasPrefix("/jsonapi.php/v1/"))
            if path.hasSuffix("/courses") { return (200, #"{"data":[{"id":"cc","attributes":{"title":"Course"}}]}"#) }
            return (200, path.hasSuffix("users/me") ? #"{"data":{"id":"bb"}}"# : #"{"data":[]}"#)
        }
        store.adoptWebSession([])
        try await waitForConnection(store)
        #expect(store.signedIn)
        store.runScheduledSync()
        try await waitForConnection(store)
        #expect(store.signedIn)
        #expect(store.preferences.lastSync != nil)
        #expect(store.status == "Up to date")
    }
    @Test func firstRunPersistsSetupAndKeepsCredentialsOutOfSettings() async throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = CredentialFixture()
        let store = store(support: support, writeCredentials: { try vault.write($0) })
        defer { store.setPaused(true); try? FileManager.default.removeItem(at: support) }
        store.preferences = Preferences()
        try serveCourses([Course(id: "cc", title: "First"), Course(id: "dd", title: "Second")])
        store.connect()
        try await waitForConnection(store)
        #expect(store.signedIn)
        #expect(store.preferences.selectedCourses == ["cc", "dd"])
        #expect(store.password.isEmpty)
        #expect(vault.saved?.username == "fixture")
        #expect(vault.saved?.password == "not-real")

        let destination = support.appendingPathComponent("sync")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        store.preferences.destination = destination.path
        store.preferences.selectedCourses = ["cc"]
        store.preferences.intervalMinutes = 0
        store.finishSetup()
        try await waitForConnection(store)
        #expect(store.preferences.lastSync != nil)
        #expect(store.status == "Up to date")

        let restored = AppStore(support: support, client: store.client, readCredentials: { vault.saved }, writeCredentials: { _ in })
        #expect(restored.preferences.setupComplete)
        #expect(restored.preferences.destination == destination.path)
        #expect(restored.preferences.selectedCourses == ["cc"])
        #expect(restored.preferences.intervalMinutes == 0)
        #expect(restored.username.isEmpty)
        restored.start()
        try await waitForConnection(restored)
        #expect(restored.username == "fixture")
        let settings = support.appendingPathComponent("settings.json")
        #expect(!(try String(contentsOf: settings, encoding: .utf8)).contains("not-real"))
        let permissions = try FileManager.default.attributesOfItem(atPath: settings.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }
    @Test func setupPersistenceFailureDoesNotStartSyncOrCompleteSetup() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("blocked".utf8).write(to: support)
        defer { try? FileManager.default.removeItem(at: support) }
        ConnectionFixture.response = { _ in Issue.record("Setup must not start network requests after saving fails"); throw URLError(.badURL) }
        let store = store(support: support)
        store.signedIn = true
        store.preferences.setupComplete = false
        store.finishSetup()
        #expect(!store.preferences.setupComplete)
        #expect(!store.isBusy)
        #expect(store.preferences.lastSync == nil)
        #expect(store.message != nil)
        #expect(store.status == "Settings need attention")
    }
    @Test func courseRefreshPreservesSelectionAndSyncUsesTheCurrentList() async throws {
        let store = store()
        defer { store.setPaused(true) }
        store.signedIn = true
        store.courses = [Course(id: "cc", title: "Old title")]
        try serveCourses([Course(id: "cc", title: "New title"), Course(id: "dd", title: "New course")])
        store.refreshCourses()
        try await waitForConnection(store)
        #expect(Set(store.courses.map(\.id)) == ["cc", "dd"])
        #expect(store.courses.first(where: { $0.id == "cc" })?.title == "New title")
        #expect(store.preferences.selectedCourses == ["cc"])
        #expect(store.preferences.lastSync == nil)

        try serveCourses([Course(id: "dd", title: "New course")])
        store.sync()
        try await waitForConnection(store)
        #expect(store.courses.map(\.id) == ["dd"])
        #expect(store.preferences.selectedCourses == ["cc"])
        #expect(store.preferences.lastSync == nil)
        #expect(store.status == "Choose courses")
    }
    @Test func refreshFailurePreservesCoursesAndRejectedSessionStopsScheduling() async throws {
        let store = store()
        defer { store.setPaused(true) }
        store.signedIn = true
        store.courses = [Course(id: "cc", title: "Saved course")]
        ConnectionFixture.response = { _ in throw URLError(.notConnectedToInternet) }
        store.refreshCourses()
        try await waitForConnection(store)
        #expect(store.signedIn)
        #expect(store.courses.map(\.id) == ["cc"])
        #expect(store.nextSync != nil)
        ConnectionFixture.response = { _ in (401, "") }
        store.refreshCourses()
        try await waitForConnection(store)
        #expect(!store.signedIn)
        #expect(store.nextSync == nil)
        #expect(store.status == "Sign-in required")
        #expect(store.preferences.selectedCourses == ["cc"])
    }
    @Test func networkRecoveryReconnectsAndSyncsWithoutWaitingForTheTimer() async throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = store(support: support)
        defer { store.setPaused(true); try? FileManager.default.removeItem(at: support) }
        store.networkChanged(available: false)
        ConnectionFixture.response = { _ in throw URLError(.notConnectedToInternet) }
        store.start()
        try await waitForConnection(store)
        try serveCourses([Course(id: "cc", title: "Course")])
        store.networkChanged(available: true)
        try await waitForConnection(store)
        #expect(store.signedIn)
        #expect(store.preferences.lastSync != nil)

        store.networkChanged(available: false)
        ConnectionFixture.response = { _ in throw URLError(.notConnectedToInternet) }
        store.sync()
        try await waitForConnection(store)
        let previous = store.preferences.lastSync
        try serveCourses([Course(id: "cc", title: "Course")])
        store.networkChanged(available: true)
        try await waitForConnection(store)
        #expect(store.preferences.lastSync! > previous!)
        ConnectionFixture.response = { _ in Issue.record("Repeated online events must not start another sync"); throw URLError(.badURL) }
        store.networkChanged(available: true)
        #expect(!store.isBusy)
    }
    @Test func networkRecoveryDuringAnActiveRequestIsNotLost() async throws {
        let store = store()
        defer { store.setPaused(true) }
        store.signedIn = true
        store.networkChanged(available: false)
        let requests = RequestCount()
        ConnectionFixture.response = { _ in
            if requests.increment() == 1 { throw URLError(.notConnectedToInternet) }
            return (401, "")
        }
        store.refreshCourses()
        // Main-actor isolation keeps the response task pending until we yield below.
        store.networkChanged(available: true)
        try await waitForConnection(store)
        #expect(store.status == "Sign-in required")
        #expect(!store.signedIn)
        #expect(!store.isBusy) // The queued transition was consumed once, without a retry loop.
    }
    @Test func networkRecoveryRespectsManualPauseAndRejectedCredentials() async throws {
        for mode in ["manual", "paused", "rejected"] {
            let store = store()
            defer { store.setPaused(true) }
            store.networkChanged(available: false)
            ConnectionFixture.response = { _ in throw URLError(.notConnectedToInternet) }
            store.start()
            try await waitForConnection(store)
            if mode == "manual" { store.preferences.intervalMinutes = 0 }
            if mode == "paused" { store.setPaused(true) }
            if mode == "rejected" {
                ConnectionFixture.response = { _ in (401, "") }
                store.runScheduledSync()
                try await waitForConnection(store)
            }
            ConnectionFixture.response = { _ in Issue.record("Network recovery must respect user choices and rejected login"); throw URLError(.badURL) }
            store.networkChanged(available: true)
            #expect(!store.isBusy)
            #expect(!store.signedIn)
        }
    }
    @Test func launchAtLoginTracksRegistrationApprovalAndExternalChanges() throws {
        var status = SMAppService.Status.notRegistered
        var rejectChange = false
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: support) }
        let store = AppStore(support: support, readCredentials: { nil }, writeCredentials: { _ in },
                             readLaunchAtLogin: { status }, updateLaunchAtLogin: { enabled in
            if rejectChange { throw URLError(.noPermissionsToReadFile) }
            status = enabled ? .requiresApproval : .notRegistered
        })
        let updates = RequestCount()
        withObservationTracking { _ = store.launchAtLogin } onChange: { _ = updates.increment() }
        #expect(!store.launchAtLogin)
        store.setLaunchAtLogin(true)
        #expect(store.launchAtLogin)
        #expect(store.launchAtLoginStatus == .requiresApproval)
        #expect(updates.total == 1)
        status = .enabled
        store.refreshLaunchAtLogin()
        #expect(store.launchAtLoginStatus == .enabled)
        rejectChange = true
        store.setLaunchAtLogin(false)
        #expect(store.launchAtLogin)
        #expect(store.message != nil)
        rejectChange = false
        store.setLaunchAtLogin(false)
        #expect(!store.launchAtLogin)
        status = .enabled
        store.refreshLaunchAtLogin()
        #expect(store.launchAtLogin)
    }
    @Test func setupSyncActionRespectsPauseAndIncompleteConfiguration() {
        let store = store()
        defer { store.setPaused(true) }
        store.signedIn = true
        store.preferences.setupComplete = false
        #expect(store.canStartSync)
        #expect(!store.canSync)
        store.setPaused(true)
        store.finishSetup()
        #expect(!store.preferences.setupComplete)
        #expect(!store.isBusy)
        #expect(!store.canStartSync)
        store.setPaused(false)
        store.preferences.destination = ""
        #expect(!store.canStartSync)
        store.finishSetup()
        #expect(!store.preferences.setupComplete)
    }
    @Test func historicalSelectionsSurviveBrowsingSavingRestartAndSync() async throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: support) }
        let fixture = SemesterFixture()
        ConnectionFixture.response = { try fixture.respond($0) }
        let store = store(support: support)
        defer { store.setPaused(true) }
        store.preferences.setupComplete = false; store.preferences.selectedCourses = []
        store.preferences.intervalMinutes = 0
        store.connect()
        try await waitForConnection(store)
        #expect(store.semesterID == "bb")
        #expect(store.visibleCourses.map(\.id) == ["cc"])
        #expect(store.preferences.selectedCourses == ["cc"])
        store.refreshCourses(semesterID: "aa")
        try await waitForConnection(store)
        #expect(store.visibleCourses.map(\.id) == ["dd"])
        #expect(store.preferences.selectedCourses == ["cc"])
        store.preferences.selectedCourses.insert("dd")
        store.refreshCourses(semesterID: "")
        try await waitForConnection(store)
        #expect(Set(store.visibleCourses.map(\.id)) == ["cc", "dd"])
        store.refreshCourses(semesterID: "bb")
        try await waitForConnection(store)
        #expect(store.preferences.selectedCourses == ["cc", "dd"])
        store.adoptWebSession([])
        try await waitForConnection(store)
        #expect(store.preferences.selectedCourses == ["cc", "dd"])
        store.finishSetup()
        try await waitForConnection(store)
        #expect(store.preferences.lastSync != nil)
        #expect(fixture.requestedFiles.contains("/jsonapi.php/v1/courses/dd/file-refs"))
        #expect(fixture.requestedFiles.contains("/jsonapi.php/v1/courses/cc/file-refs"))

        fixture.clearRequests()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ConnectionFixture.self]
        let restored = AppStore(support: support, client: StudIPClient(session: URLSession(configuration: config)),
                                readCredentials: { Credentials(username: "fixture", password: "not-real") }, writeCredentials: { _ in })
        defer { restored.setPaused(true) }
        restored.start()
        try await waitForConnection(restored)
        #expect(restored.preferences.selectedCourses == ["cc", "dd"])
        #expect(restored.semesterID == "bb")
        #expect(restored.status == "Up to date")
        #expect(fixture.requestedFiles.contains("/jsonapi.php/v1/courses/dd/file-refs"))
    }
    @Test func failedSemesterChangePreservesTheVisibleCatalogAndSelections() async throws {
        let fixture = SemesterFixture()
        ConnectionFixture.response = { try fixture.respond($0) }
        let store = store()
        defer { store.setPaused(true) }
        store.preferences.setupComplete = false
        store.connect()
        try await waitForConnection(store)
        fixture.setOffline(true)
        store.refreshCourses(semesterID: "aa")
        try await waitForConnection(store)
        #expect(store.semesterID == "bb")
        #expect(store.visibleCourses.map(\.id) == ["cc"])
        #expect(store.preferences.selectedCourses == ["cc"])
        #expect(store.signedIn)
        #expect(store.message != nil)
        fixture.setOffline(false)
        store.refreshCourses(semesterID: "aa")
        try await waitForConnection(store)
        #expect(store.semesterID == "aa")
    }
    @Test func onboardingRequiresVerifiedAccountFolderAndCoursesBeforeCompletion() {
        let store = store()
        defer { store.setPaused(true) }
        store.preferences.setupComplete = false
        store.preferences.destination = ""; store.preferences.selectedCourses = []
        #expect(SetupStep.allCases.allSatisfy { !store.canContinueSetup($0) })
        store.signedIn = true
        #expect(store.canContinueSetup(.account))
        #expect(!store.canContinueSetup(.folder))
        store.preferences.destination = "/tmp/fixture"
        #expect(store.canContinueSetup(.folder))
        #expect(!store.canContinueSetup(.courses))
        store.preferences.selectedCourses = ["cc"]
        #expect(store.canContinueSetup(.courses))
        #expect(store.canContinueSetup(.review))
        #expect(!store.preferences.setupComplete)
        store.isBusy = true
        #expect(SetupStep.allCases.allSatisfy { !store.canContinueSetup($0) })
        store.isBusy = false; store.signedIn = false
        #expect(!store.canContinueSetup(.review))
    }
    @Test func webLoginDoesNotFallBackToOldCredentialsAfterCatalogNetworkFailure() async throws {
        let store = store()
        defer { store.setPaused(true) }
        ConnectionFixture.response = { _ in throw URLError(.notConnectedToInternet) }
        store.start()
        try await waitForConnection(store)
        ConnectionFixture.response = { request in
            if request.url!.path.hasSuffix("users/me") { return (200, #"{"data":{"id":"bb"}}"#) }
            throw URLError(.notConnectedToInternet)
        }
        store.adoptWebSession([])
        try await waitForConnection(store)
        #expect(store.signedIn)
        #expect(store.password.isEmpty)
        #expect(store.message != nil)
        #expect(store.nextSync != nil)
        ConnectionFixture.response = { request in
            #expect(request.url!.path.hasPrefix("/jsonapi.php/v1/"))
            if request.url!.path.hasSuffix("users/me") { return (200, #"{"data":{"id":"bb"}}"#) }
            if request.url!.path.hasSuffix("/courses") { return (200, #"{"data":[{"id":"cc","attributes":{"title":"Course"}}]}"#) }
            return (200, #"{"data":[]}"#)
        }
        store.runScheduledSync()
        try await waitForConnection(store)
        #expect(store.status == "Up to date")
    }
    @Test func blockedCredentialReadDoesNotBlockTheMainActorAndCancellationDiscardsIt() async throws {
        let vault = CredentialFixture(credentials: Credentials(username: "fixture", password: "not-real"), blockRead: true, blockWrite: true)
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ConnectionFixture.self]
        ConnectionFixture.response = { _ in Issue.record("Cancelled credentials must not start sign-in"); throw URLError(.badURL) }
        let store = AppStore(support: support, client: StudIPClient(session: URLSession(configuration: config)),
                             readCredentials: { try vault.read() }, writeCredentials: { try vault.write($0) })
        defer { store.cancel(); vault.release.signal(); vault.release.signal(); store.setPaused(true); try? FileManager.default.removeItem(at: support) }
        #expect(vault.readStartedOnMain == nil)
        #expect(store.username.isEmpty)
        store.start()
        #expect(store.isBusy)
        let deadline = Date().addingTimeInterval(3)
        while vault.readStartedOnMain == nil && Date() < deadline { await Task.yield() }
        try #require(vault.readStartedOnMain == false)
        store.setPaused(true)
        #expect(store.paused)
        store.cancel()
        try await waitForConnection(store, timeout: 1)
        #expect(store.status == "Cancelled")
        #expect(store.username.isEmpty)
        #expect(!store.signedIn)
        // A new login can begin before the old Keychain read returns.
        try serveCourses([Course(id: "cc", title: "Course")])
        store.username = "new-fixture"; store.password = "new-not-real"
        store.connect()
        vault.release.signal()
        let writeDeadline = Date().addingTimeInterval(3)
        while vault.writeStartedOnMain == nil && Date() < writeDeadline { await Task.yield() }
        try #require(vault.writeStartedOnMain == false)
        #expect(store.isBusy)
        #expect(store.username == "new-fixture")
        #expect(!store.signedIn)
        vault.release.signal()
        try await waitForConnection(store)
        #expect(store.signedIn)
        #expect(vault.saved?.username == "new-fixture")
    }
    @Test func blockedCredentialWriteDoesNotBlockTheMainActorOrCompleteCancelledLogin() async throws {
        let vault = CredentialFixture(blockWrite: true)
        let store = store(writeCredentials: { try vault.write($0) })
        defer { store.cancel(); vault.release.signal(); store.setPaused(true) }
        store.preferences.setupComplete = false
        try serveCourses([Course(id: "cc", title: "Course")])
        store.connect()
        let deadline = Date().addingTimeInterval(3)
        while vault.writeStartedOnMain == nil && Date() < deadline { await Task.yield() }
        try #require(vault.writeStartedOnMain == false)
        #expect(store.isBusy)
        store.setPaused(true)
        #expect(store.paused)
        store.cancel()
        try await waitForConnection(store, timeout: 1)
        #expect(store.status == "Cancelled")
        #expect(!store.signedIn)
        #expect(store.courses.isEmpty)
        store.adoptWebSession([])
        try await waitForConnection(store)
        #expect(store.signedIn)
        #expect(store.status == "Ready")
        vault.release.signal()
        let savedDeadline = Date().addingTimeInterval(3)
        while vault.saved == nil && Date() < savedDeadline { await Task.yield() }
        try #require(vault.saved != nil)
        #expect(store.signedIn)
        #expect(store.status == "Ready")
        #expect(store.password.isEmpty)
    }
    @Test(arguments: [false, true]) func missingOrDeniedCredentialsStillAllowManualSignIn(_ denied: Bool) async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ConnectionFixture.self]
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(support: support, client: StudIPClient(session: URLSession(configuration: config)), readCredentials: {
            if denied { throw NSError(domain: "fixture.Keychain", code: 1) }
            return nil
        }, writeCredentials: { _ in })
        defer { store.setPaused(true); try? FileManager.default.removeItem(at: support) }
        store.start()
        try await waitForConnection(store)
        #expect(store.status == "Sign-in required")
        #expect((store.message != nil) == denied)
        store.username = "fixture"; store.password = "not-real"
        try serveCourses([Course(id: "cc", title: "Course")])
        store.connect()
        try await waitForConnection(store)
        #expect(store.signedIn)
        #expect(store.message == nil)
    }
}
