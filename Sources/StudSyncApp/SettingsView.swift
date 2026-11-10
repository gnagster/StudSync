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

enum SettingsLayout {
    static let width: CGFloat = 460
    static let rowHeight: CGFloat = 36
}

/// One tab of the preferences window, sized to its content. Each tab owns the side effects of the values it edits.
struct SettingsTabView: View {
    let tab: SettingsTab
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch tab {
            case .general: general
            case .account: account
            case .courses: CoursePicker(store: store)
            case .history: SyncHistory(store: store)
            case .updates: SettingsGroup { UpdatePreferences() }
            }
            FeedbackList(store: store)
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .frame(width: SettingsLayout.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: store.preferences.intervalMinutes) { if tab == .general { store.save(); store.schedule() } }
        .onChange(of: store.preferences.selectedCourses) { if tab == .courses { store.save(); store.schedule() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if tab == .general { store.refreshLaunchAtLogin() }
        }
        .sheet(isPresented: Binding(get: { tab == .account && store.showWebLogin }, set: { store.showWebLogin = $0 })) { WebLogin(store: store) }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsGroup { SyncFolderRow(store: store) }
            Caption("Untouched files update automatically. Local edits are kept; incoming versions appear beside them. Server deletions never delete your files.")
            SettingsGroup { SyncPreferenceRows(store: store) }.padding(.top, 8)
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountRows(store: store)
            Caption("Credentials stay in your Mac’s Keychain. StudSync reuses your session and attempts one re-login when it expires.")
        }
    }
}

// MARK: Building blocks

/// A rounded group of rows separated by hairlines, like a grouped form but sized to its content.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().padding(.leading, 12) }
                    row
                }
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing
    var body: some View {
        HStack(spacing: 12) {
            Text(L(title))
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 12).frame(minHeight: SettingsLayout.rowHeight)
    }
}

struct Caption: View {
    let key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(L(key)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 12)
    }
}

// MARK: Rows

struct SyncFolderRow: View {
    @Bindable var store: AppStore
    var body: some View {
        SettingsRow(title: "Sync folder") {
            HStack(spacing: 8) {
                if store.preferences.destination.isEmpty {
                    Text(L("No folder selected")).foregroundStyle(.secondary)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(for: .folder)).resizable().frame(width: 16, height: 16).accessibilityHidden(true)
                    Text((store.preferences.destination as NSString).abbreviatingWithTildeInPath)
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(store.preferences.destination)
                }
                Button(L("Choose…")) { store.chooseDestination() }.disabled(store.isBusy)
            }
        }
    }
}

struct SyncPreferenceRows: View {
    @Bindable var store: AppStore
    @AppStorage(FileNotifications.enabledKey) private var notify = true
    var body: some View {
        SettingsRow(title: "Sync") {
            Picker(L("Sync"), selection: $store.preferences.intervalMinutes) {
                Text(L("Manually")).tag(0)
                Text(L("Every 15 minutes")).tag(15)
                Text(L("Hourly")).tag(60)
                Text(L("Every 4 hours")).tag(240)
            }
            .labelsHidden().fixedSize().disabled(store.isBusy)
        }
        SettingsRow(title: "Start at Login") {
            Toggle(L("Start at Login"), isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(store.isBusy)
        }
        if store.launchAtLoginStatus == .requiresApproval {
            SettingsRow(title: "Allow StudSync in System Settings to finish enabling Start at Login.") {
                Button(L("Open Login Items…")) { SMAppService.openSystemSettingsLoginItems() }
            }
            .font(.caption)
        }
        SettingsRow(title: "Notify about new files") {
            Toggle(L("Notify about new files"), isOn: $notify).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

/// Signed in: who and how. Signed out (or switching): the sign-in fields.
struct AccountRows: View {
    @Bindable var store: AppStore
    @State private var switching = false
    var body: some View {
        if store.signedIn && !switching {
            SettingsGroup {
                SettingsRow(title: "Account") {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(store.username.isEmpty ? L("University web login") : store.username).foregroundStyle(.secondary)
                    }
                }
                SettingsRow(title: "University") { Text("Göttingen · Stud.IP").foregroundStyle(.secondary) }
                SettingsRow(title: "Use another account") {
                    Button(L("Sign in again…")) { switching = true }.disabled(store.isBusy)
                }
            }
        } else {
            SignInFields(store: store)
        }
    }
}

struct SignInFields: View {
    @Bindable var store: AppStore
    var showsActions = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup {
                SettingsRow(title: "Username") {
                    TextField(L("Username"), text: $store.username, prompt: Text(L("Without email suffix")))
                        .labelsHidden().textFieldStyle(.plain).multilineTextAlignment(.trailing)
                        .textContentType(.username).disabled(store.isBusy)
                }
                SettingsRow(title: "Password") {
                    SecureField(L("Password"), text: $store.password, prompt: Text(L("Required")))
                        .labelsHidden().textFieldStyle(.plain).multilineTextAlignment(.trailing)
                        .textContentType(.password).disabled(store.isBusy)
                        .onSubmit { if !store.username.isEmpty && !store.password.isEmpty && !store.isBusy { store.connect() } }
                }
            }
            HStack {
                Button(L("University web login…")) { store.showWebLogin = true }.buttonStyle(.link).disabled(store.isBusy)
                Spacer()
                if showsActions {
                    if store.isBusy { ProgressView().controlSize(.small) }
                    Button(L("Sign in")) { store.connect() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(store.username.isEmpty || store.password.isEmpty || store.isBusy)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

/// Searchable course selection with whole-row checkboxes, shared by Settings and onboarding.
struct CoursePicker: View {
    @Bindable var store: AppStore
    var listHeight: CGFloat = 288
    @State private var query = ""

    private var shown: [Course] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? store.visibleCourses : store.visibleCourses.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }
    private var allShownSelected: Bool {
        !shown.isEmpty && shown.allSatisfy { store.preferences.selectedCourses.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("Search"), text: $query, prompt: Text(L("Search courses"))).textFieldStyle(.plain).labelsHidden()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                            .buttonStyle(.plain).help(L("Clear"))
                    }
                }
                .padding(.horizontal, 8).frame(height: 28)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator.opacity(0.6)))
                Picker(L("Semester"), selection: Binding(get: { store.semesterID }, set: { store.refreshCourses(semesterID: $0) })) {
                    Text(L("All semesters")).tag("")
                    ForEach(store.semesters) { term in Text(term.title).tag(term.id) }
                }
                .labelsHidden().fixedSize()
                Button { store.refreshCourses() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help(L("Refresh courses"))
            }
            .disabled(!store.signedIn || store.isBusy)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if shown.isEmpty {
                        Text(L(!store.signedIn ? "Sign in to load your current courses."
                               : query.isEmpty ? "No courses found in this semester. Try another semester or refresh." : "No matching courses"))
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(24)
                    }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, course in
                        if index > 0 { Divider().padding(.leading, 40) }
                        CourseRow(title: course.title, selected: store.preferences.selectedCourses.contains(course.id)) {
                            if store.preferences.selectedCourses.contains(course.id) { store.preferences.selectedCourses.remove(course.id) }
                            else { store.preferences.selectedCourses.insert(course.id) }
                        }
                        .disabled(store.isBusy)
                    }
                }
            }
            .frame(height: shown.isEmpty ? 96 : min(listHeight, CGFloat(shown.count) * (SettingsLayout.rowHeight + 1)))
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator.opacity(0.6)))
            .onChange(of: shown.count) { (NSApp.keyWindow?.contentViewController as? SettingsTabController)?.fitWindow(animate: true) }

            HStack(spacing: 12) {
                Text(String(format: L("%lld selected"), store.preferences.selectedCourses.count)).monospacedDigit()
                Spacer()
                Button(L(allShownSelected ? "Clear shown" : "Select shown")) {
                    if allShownSelected { store.preferences.selectedCourses.subtract(shown.map(\.id)) }
                    else { store.preferences.selectedCourses.formUnion(shown.map(\.id)) }
                }
                .buttonStyle(.link).disabled(shown.isEmpty)
            }
            .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 4)
            .disabled(!store.signedIn || store.isBusy)
        }
    }
}

private struct CourseRow: View {
    let title: String
    let selected: Bool
    let toggle: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16)).foregroundStyle(selected ? AnyShapeStyle(StudSyncStyle.accent) : AnyShapeStyle(.tertiary))
                    .frame(width: 16)
                Text(title).lineLimit(1).truncationMode(.tail).foregroundStyle(selected ? .primary : .secondary)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12).frame(height: SettingsLayout.rowHeight)
            .background(Color.primary.opacity(hovering ? 0.05 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SyncHistory: View {
    @Bindable var store: AppStore
    var body: some View {
        if store.changes.isEmpty {
            ContentUnavailableView(L("No changes yet"), systemImage: "doc", description: Text(L("Downloaded files will appear here.")))
                .frame(height: 200)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(store.changes.enumerated()), id: \.element.id) { index, change in
                        if index > 0 { Divider().padding(.leading, 44) }
                        Button { store.reveal(change.path) } label: {
                            HStack(spacing: 12) {
                                Group {
                                    if change.conflict {
                                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                                    } else {
                                        Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (change.name as NSString).pathExtension) ?? .data))
                                            .resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                                    }
                                }.frame(width: 20)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(change.name).lineLimit(1).truncationMode(.middle)
                                    Text(change.conflict ? L("Local edits preserved")
                                         : StatusPanel.courseName(for: change.path, root: store.preferences.destination) ?? "")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(change.date, format: .dateTime.day().month().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .padding(.horizontal, 12).frame(height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help(L("Reveal in Finder"))
                    }
                }
            }
            .frame(height: 352)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator.opacity(0.6)))
        }
    }
}

/// Progress and errors below a tab's content; nothing when there is nothing to say.
struct FeedbackList: View {
    @Bindable var store: AppStore
    var body: some View {
        if store.isBusy || !store.messages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if store.isBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L(store.status)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button(L("Cancel")) { store.cancel() }.controlSize(.small)
                    }
                }
                ForEach(store.messages, id: \.self) { message in
                    Label {
                        Text(L(message)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
            }
            .font(.callout).padding(.horizontal, 4)
        }
    }
}

/// Status, progress and errors along the bottom edge of a window.
struct FeedbackBar: View {
    @Bindable var store: AppStore
    var body: some View {
        if store.isBusy || !store.messages.isEmpty {
            FeedbackList(store: store)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading).background(.bar)
        }
    }
}

struct UpdatePreferences: View {
    private let updates = AppUpdates.shared
    @State private var checks = AppUpdates.shared.automaticallyChecks
    @State private var downloads = AppUpdates.shared.automaticallyDownloads
    var body: some View {
        SettingsRow(title: "Automatically check for updates") {
            Toggle(L("Automatically check for updates"), isOn: $checks).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .onChange(of: checks) { updates.automaticallyChecks = checks }
        }
        SettingsRow(title: "Automatically download updates") {
            Toggle(L("Automatically download updates"), isOn: $downloads).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .disabled(!checks)
                .onChange(of: downloads) { updates.automaticallyDownloads = downloads }
        }
        SettingsRow(title: String(format: L("Version %@"), Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")) {
            Button(L("Check for Updates…")) { updates.check() }.disabled(!updates.canCheck)
        }
    }
}
