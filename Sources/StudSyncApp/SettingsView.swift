import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers
import StudSyncCore

enum SettingsTab: String, CaseIterable {
    case general, account, courses, history, updates
    var title: String {
        switch self {
        case .general: "General"
        case .account: "Account"
        case .courses: "Courses"
        case .history: "History"
        case .updates: "Updates"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .account: "person.crop.circle"
        case .courses: "books.vertical"
        case .history: "clock.arrow.circlepath"
        case .updates: "arrow.down.circle"
        }
    }
}

/// One tab of the native preferences window. Each tab owns the side effects of the values it edits.
struct SettingsTabView: View {
    let tab: SettingsTab
    @Bindable var store: AppStore

    var body: some View {
        Group {
            switch tab {
            case .general: general
            case .account: account
            case .courses: courses
            case .history: SyncHistory(store: store)
            case .updates: Form { Section { UpdatePreferences() } }.formStyle(.grouped)
            }
        }
        .frame(width: 520, height: 440)
    }

    private var general: some View {
        Form {
            Section {
                SyncFolderRow(store: store)
            } footer: {
                Text(L("Untouched files update automatically. Local edits are kept; incoming versions appear beside them. Server deletions never delete your files."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section { SyncPreferenceRows(store: store) }
        }
        .formStyle(.grouped)
        .onChange(of: store.preferences.intervalMinutes) { store.save(); store.schedule() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refreshLaunchAtLogin() }
    }

    private var account: some View {
        Form {
            Section { AccountRows(store: store) } footer: {
                Text(L("Credentials stay in your Mac’s Keychain. StudSync reuses your session and attempts one re-login when it expires."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            FeedbackSection(store: store)
        }
        .formStyle(.grouped)
        .sheet(isPresented: $store.showWebLogin) { WebLogin(store: store) }
    }

    private var courses: some View {
        VStack(spacing: 0) {
            CoursePicker(store: store).padding(20)
            FeedbackBar(store: store)
        }
        .onChange(of: store.preferences.selectedCourses) { store.save(); store.schedule() }
    }
}

struct SyncFolderRow: View {
    @Bindable var store: AppStore
    var body: some View {
        LabeledContent(L("Sync folder")) {
            HStack(spacing: 8) {
                if store.preferences.destination.isEmpty {
                    Text(L("No folder selected")).foregroundStyle(.secondary)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: store.preferences.destination))
                        .resizable().frame(width: 16, height: 16).accessibilityHidden(true)
                    Text((store.preferences.destination as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.middle).help(store.preferences.destination)
                }
                Button(L("Choose…")) { store.chooseDestination() }.disabled(store.isBusy)
            }
        }
    }
}

struct SyncPreferenceRows: View {
    @Bindable var store: AppStore
    var body: some View {
        Picker(L("Sync"), selection: $store.preferences.intervalMinutes) {
            Text(L("Manually")).tag(0)
            Text(L("Every 15 minutes")).tag(15)
            Text(L("Hourly")).tag(60)
            Text(L("Every 4 hours")).tag(240)
        }.disabled(store.isBusy)
        Toggle(L("Start at Login"), isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
            .disabled(store.isBusy)
        if store.launchAtLoginStatus == .requiresApproval {
            LabeledContent {
                Button(L("Open Login Items…")) { SMAppService.openSystemSettingsLoginItems() }
            } label: {
                Text(L("Allow StudSync in System Settings to finish enabling Start at Login.")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Signed in: who and how. Signed out (or switching): the sign-in fields.
struct AccountRows: View {
    @Bindable var store: AppStore
    @State private var switching = false
    var body: some View {
        if store.signedIn && !switching {
            LabeledContent(L("Account")) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(store.username.isEmpty ? L("University web login") : store.username)
                }
            }
            LabeledContent(L("University")) { Text("Universität Göttingen · Stud.IP").foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button(L("Use another account…")) { switching = true }.disabled(store.isBusy)
            }
        } else {
            SignInFields(store: store)
        }
    }
}

struct SignInFields: View {
    @Bindable var store: AppStore
    var body: some View {
        TextField(L("Username"), text: $store.username, prompt: Text(L("Without email suffix")))
            .textContentType(.username).disabled(store.isBusy)
        SecureField(L("Password"), text: $store.password).textContentType(.password).disabled(store.isBusy)
            .onSubmit { if !store.username.isEmpty && !store.password.isEmpty && !store.isBusy { store.connect() } }
        HStack {
            Button(L("University web login…")) { store.showWebLogin = true }.disabled(store.isBusy)
            Spacer()
            if store.isBusy { ProgressView().controlSize(.small) }
            Button(L("Sign in")) { store.connect() }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(store.username.isEmpty || store.password.isEmpty || store.isBusy)
        }
    }
}

/// Searchable course selection, shared by Settings and onboarding.
struct CoursePicker: View {
    @Bindable var store: AppStore
    @State private var query = ""

    private var shown: [Course] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? store.visibleCourses : store.visibleCourses.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField(L("Search"), text: $query, prompt: Text(L("Search courses"))).textFieldStyle(.roundedBorder)
                Picker(L("Semester"), selection: Binding(get: { store.semesterID }, set: { store.refreshCourses(semesterID: $0) })) {
                    Text(L("All semesters")).tag("")
                    ForEach(store.semesters) { term in Text(term.title).tag(term.id) }
                }
                .labelsHidden().fixedSize()
                Button { store.refreshCourses() } label: { Image(systemName: "arrow.clockwise") }.help(L("Refresh courses"))
            }
            .disabled(!store.signedIn || store.isBusy)
            List {
                if shown.isEmpty {
                    Text(L(!store.signedIn ? "Sign in to load your current courses."
                           : query.isEmpty ? "No courses found in this semester. Try another semester or refresh." : "No matching courses"))
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { course in
                    Toggle(isOn: Binding(get: { store.preferences.selectedCourses.contains(course.id) }, set: { selected in
                        if selected { store.preferences.selectedCourses.insert(course.id) } else { store.preferences.selectedCourses.remove(course.id) }
                    })) { Text(course.title).lineLimit(1) }
                    .toggleStyle(.checkbox).disabled(store.isBusy)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            HStack(spacing: 12) {
                Text(String(format: L("%lld selected"), store.preferences.selectedCourses.count)).monospacedDigit()
                Spacer()
                Button(L("Select shown")) { store.preferences.selectedCourses.formUnion(shown.map(\.id)) }.buttonStyle(.link)
                Button(L("Clear shown")) { store.preferences.selectedCourses.subtract(shown.map(\.id)) }.buttonStyle(.link)
            }
            .font(.callout).foregroundStyle(.secondary).disabled(!store.signedIn || store.isBusy)
        }
    }
}

struct SyncHistory: View {
    @Bindable var store: AppStore
    var body: some View {
        if store.changes.isEmpty {
            ContentUnavailableView(L("No changes yet"), systemImage: "doc", description: Text(L("Downloaded files will appear here.")))
        } else {
            List(store.changes) { change in
                Button { store.reveal(change.path) } label: {
                    HStack(spacing: 8) {
                        if change.conflict {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).frame(width: 20)
                        } else {
                            Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (change.name as NSString).pathExtension) ?? .data))
                                .resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(change.name).lineLimit(1).truncationMode(.middle)
                            Text(change.conflict ? L("Local edits preserved")
                                 : StatusPanel.courseName(for: change.path, root: store.preferences.destination) ?? "")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(change.date, format: .dateTime.day().month().hour().minute())
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain).help(L("Reveal in Finder"))
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

/// Errors and hints in a grouped form.
struct FeedbackSection: View {
    @Bindable var store: AppStore
    var body: some View {
        if !store.messages.isEmpty {
            Section {
                ForEach(store.messages, id: \.self) { message in
                    Label {
                        Text(L(message)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
            }
        }
    }
}

/// Status, progress and errors along the bottom edge of a window.
struct FeedbackBar: View {
    @Bindable var store: AppStore
    var body: some View {
        if store.isBusy || !store.messages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if store.isBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L(store.status)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button(L("Cancel")) { store.cancel() }
                    }
                }
                ForEach(store.messages, id: \.self) { message in
                    Label {
                        Text(L(message)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
            }
            .font(.callout).padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading).background(.bar)
        }
    }
}

struct UpdatePreferences: View {
    private let updates = AppUpdates.shared
    @State private var checks = AppUpdates.shared.automaticallyChecks
    @State private var downloads = AppUpdates.shared.automaticallyDownloads
    var body: some View {
        Toggle(L("Automatically check for updates"), isOn: $checks)
            .onChange(of: checks) { updates.automaticallyChecks = checks }
        Toggle(L("Automatically download updates"), isOn: $downloads)
            .disabled(!checks)
            .onChange(of: downloads) { updates.automaticallyDownloads = downloads }
        LabeledContent {
            Button(L("Check for Updates…")) { updates.check() }.disabled(!updates.canCheck)
        } label: {
            Text(String(format: L("Version %@"), Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"))
                .foregroundStyle(.secondary)
        }
    }
}
