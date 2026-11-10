import SwiftUI
import AppKit
import ServiceManagement
import StudSyncCore

enum StudSyncStyle {
    static let accent = Color.accentColor
    static let fold = Color(red: 0.90, green: 0.04, blue: 0.06)
}

enum SetupStep: Int, CaseIterable {
    case account, folder, courses, review
    var title: String {
        switch self {
        case .account: "Connect your university"
        case .folder: "Choose your Finder folder"
        case .courses: "Choose courses"
        case .review: "Ready for your first sync"
        }
    }
}

extension AppStore {
    func canContinueSetup(_ step: SetupStep) -> Bool {
        guard !isBusy, signedIn else { return false }
        switch step {
        case .account: return true
        case .folder: return !preferences.destination.isEmpty
        case .courses, .review: return canStartSync
        }
    }
}

struct SetupView: View {
    @Bindable var store: AppStore
    @State private var step: SetupStep = .account
    private var onboarding: Bool { !store.preferences.setupComplete }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if onboarding {
                    steps
                    switch step {
                    case .account: account
                    case .folder: folder
                    case .courses: courses
                    case .review: review; preferences
                    }
                } else {
                    account; folder; courses; preferences
                }
                if !onboarding || step == .review { updatePreferences }
                Text(L("StudSync stays in your menu bar when this window closes."))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(26)
        }
        .safeAreaInset(edge: .top, spacing: 0) { feedback }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if onboarding { navigation }
        }
        .tint(StudSyncStyle.accent)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refreshLaunchAtLogin() }
        .onChange(of: store.preferences.intervalMinutes) { store.save(); store.schedule() }
        .onChange(of: store.preferences.selectedCourses) { store.save(); store.schedule() }
        .sheet(isPresented: $store.showWebLogin) { WebLogin(store: store) }
    }

    private var header: some View {
        HStack(spacing: 18) {
            Image(nsImage: AppImages.logo)
                .resizable().scaledToFit().frame(width: 72, height: 72).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(L(onboarding ? "Welcome to StudSync" : "Your courses, in Finder.")).font(.largeTitle.bold())
                Text(L("Universität Göttingen · Stud.IP")).font(.subheadline).foregroundStyle(.secondary)
                Capsule().fill(StudSyncStyle.fold).frame(width: 32, height: 4).accessibilityHidden(true)
            }
        }
    }

    private var steps: some View {
        HStack(spacing: 8) {
            ForEach(SetupStep.allCases, id: \.rawValue) { item in
                VStack(spacing: 6) {
                    Image(systemName: item.rawValue < step.rawValue ? "checkmark.circle.fill" : "\(item.rawValue + 1).circle.fill")
                        .font(.title2).foregroundStyle(item.rawValue <= step.rawValue ? StudSyncStyle.accent : Color.secondary)
                    Text(L(item.title)).font(.caption).multilineTextAlignment(.center)
                        .foregroundStyle(item == step ? .primary : .secondary)
                }.frame(maxWidth: .infinity)
            }
        }.accessibilityElement(children: .combine)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L(title)).font(.headline)
            content()
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(StudSyncStyle.accent.opacity(0.15)))
    }

    private var account: some View {
        card("Connect your university") {
            TextField(L("Username (without email suffix)"), text: $store.username)
                .textContentType(.username).disabled(store.isBusy)
            SecureField(L("Password"), text: $store.password).textContentType(.password).disabled(store.isBusy)
                .onSubmit { if !store.username.isEmpty && !store.password.isEmpty && !store.isBusy { store.connect() } }
            HStack {
                Button(L("Sign in")) { store.connect() }
                    .buttonStyle(.borderedProminent).disabled(store.username.isEmpty || store.password.isEmpty || store.isBusy)
                Button(L("University web login…")) { store.showWebLogin = true }.disabled(store.isBusy)
                if store.signedIn { Label(L("Connected"), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
            }
            Text(L("Credentials stay in your Mac’s Keychain. StudSync reuses your session and attempts one re-login when it expires."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var folder: some View {
        card("Choose your Finder folder") {
            Label(store.preferences.destination.isEmpty ? L("No folder selected") : store.preferences.destination, systemImage: "folder")
                .foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Button(L("Choose…")) { store.chooseDestination() }.disabled(store.isBusy)
            Text(L("Untouched files update automatically. Local edits are kept; incoming versions appear beside them. Server deletions never delete your files."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var courses: some View {
        card("Choose courses") {
            HStack {
                Picker(L("Semester"), selection: Binding(get: { store.semesterID }, set: { store.refreshCourses(semesterID: $0) })) {
                    Text(L("All semesters")).tag("")
                    ForEach(store.semesters) { term in Text(term.title).tag(term.id) }
                }
                Button { store.refreshCourses() } label: { Image(systemName: "arrow.clockwise") }.help(L("Refresh courses"))
            }.disabled(!store.signedIn || store.isBusy)
            HStack {
                Text(L("Selected courses") + ": \(store.preferences.selectedCourses.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Select shown")) { store.preferences.selectedCourses.formUnion(store.visibleCourses.map(\.id)) }
                Button(L("Clear shown")) { store.preferences.selectedCourses.subtract(store.visibleCourses.map(\.id)) }
            }.font(.caption).disabled(!store.signedIn || store.isBusy)
            if store.visibleCourses.isEmpty {
                Text(L(store.signedIn ? "No courses found in this semester. Try another semester or refresh." : "Sign in to load your current courses."))
                    .foregroundStyle(.secondary).font(.callout)
            }
            ForEach(store.visibleCourses) { course in
                Toggle(course.title, isOn: Binding(get: { store.preferences.selectedCourses.contains(course.id) }, set: { selected in
                    if selected { store.preferences.selectedCourses.insert(course.id) } else { store.preferences.selectedCourses.remove(course.id) }
                })).disabled(store.isBusy)
            }
            Text(L("Selections from other semesters stay selected and sync in the background."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var review: some View {
        card("Ready for your first sync") {
            Label(store.username.isEmpty ? L("University web login") : store.username, systemImage: "person.crop.circle")
            Label(store.preferences.destination, systemImage: "folder").textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Label(L("Selected courses") + ": \(store.preferences.selectedCourses.count)", systemImage: "books.vertical")
            Text(L("Start your first sync. You can change these choices later in Settings."))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var preferences: some View {
        card("Sync preferences") {
            Picker(L("Sync"), selection: $store.preferences.intervalMinutes) {
                Text(L("Manually")).tag(0)
                Text(L("Every 15 minutes")).tag(15)
                Text(L("Hourly")).tag(60)
                Text(L("Every 4 hours")).tag(240)
            }
            Toggle(L("Start at Login"), isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
            if store.launchAtLoginStatus == .requiresApproval {
                Text(L("Allow StudSync in System Settings to finish enabling Start at Login.")).font(.caption).foregroundStyle(.secondary)
                Button(L("Open Login Items…")) { SMAppService.openSystemSettingsLoginItems() }
            }
        }.disabled(store.isBusy)
    }

    private var updatePreferences: some View {
        card("App updates") {
            UpdatePreferences()
        }
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L(store.paused ? "Paused" : store.status)).font(.subheadline)
                Spacer()
                if store.isBusy {
                    ProgressView().controlSize(.small)
                    Button(L("Cancel")) { store.cancel() }
                } else if !onboarding {
                    Button(L("Sync now")) { store.sync() }.buttonStyle(.borderedProminent).disabled(!store.canSync)
                }
            }
            if store.isBusy && store.total > 0 { ProgressView(value: Double(store.completed), total: Double(store.total)) }
            ForEach(store.messages, id: \.self) { message in
                Label(L(message), systemImage: "info.circle").font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }.padding(.horizontal, 26).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading).background(.bar)
    }

    private var navigation: some View {
        HStack {
            Button(L("Back")) { step = SetupStep(rawValue: step.rawValue - 1) ?? .account }
                .disabled(step == .account || store.isBusy)
            Spacer()
            if step == .review {
                Button(L("Start syncing")) { store.finishSetup() }
                    .buttonStyle(.borderedProminent).disabled(!store.canContinueSetup(step)).keyboardShortcut(.defaultAction)
            } else {
                Button(L("Continue")) { step = SetupStep(rawValue: step.rawValue + 1) ?? .review }
                    .buttonStyle(.borderedProminent).disabled(!store.canContinueSetup(step)).keyboardShortcut(.defaultAction)
            }
        }.padding(.horizontal, 26).padding(.vertical, 16).background(.bar)
    }
}

private struct UpdatePreferences: View {
    private let updates = AppUpdates.shared
    @State private var checks = AppUpdates.shared.automaticallyChecks
    @State private var downloads = AppUpdates.shared.automaticallyDownloads
    var body: some View {
        Toggle(L("Automatically check for updates"), isOn: $checks)
            .onChange(of: checks) { updates.automaticallyChecks = checks }
        Toggle(L("Automatically download updates"), isOn: $downloads)
            .disabled(!checks)
            .onChange(of: downloads) { updates.automaticallyDownloads = downloads }
        Button(L("Check for Updates…")) { updates.check() }.disabled(!updates.canCheck)
    }
}
