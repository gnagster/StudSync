import SwiftUI
import AppKit
import StudSyncCore

enum StudSyncStyle {
    static let accent = Color.accentColor
    /// The fold red from the logo. Reserved for the "new" marker.
    static let fold = Color(red: 0.90, green: 0.04, blue: 0.06)
}

enum SetupStep: Int, CaseIterable {
    case account, folder, courses, review
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

/// Four short pages: connect, folder, courses, first sync. One question per page, one primary action.
struct SetupView: View {
    @Bindable var store: AppStore
    var close: () -> Void = {}
    @State var step: SetupStep = .account
    @State private var folders: [String] = []
    /// The current-semester default applies once, on a first setup; a selection the user cleared stays empty.
    @State private var preselected = false

    static let suggestedFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Stud.IP", isDirectory: true).path

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .account: account
                case .folder: folder
                case .courses: courses
                case .review: firstSync
                }
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)
            if step != .review { FeedbackBar(store: store) }
            footer
        }
        .frame(width: SettingsLayout.width)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $store.showWebLogin) { WebLogin(store: store) }
        .onChange(of: store.preferences.intervalMinutes) { store.save(); store.schedule() }
        // Rerun after setup, the assistant edits the live selection; save it like Settings does.
        .onChange(of: store.preferences.selectedCourses) { if store.preferences.setupComplete { store.save(); store.schedule() } }
        .onChange(of: store.isBusy) { if step == .review { loadFolders() } }
        .refitsWindow(on: "\(step)\(store.isBusy)\(store.signedIn)\(store.messages.count)\(folders.count)")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refreshLaunchAtLogin() }
    }

    // MARK: Pages

    private var account: some View {
        VStack(spacing: 16) {
            Image(nsImage: AppImages.logo).resizable().scaledToFit().frame(width: 56, height: 56).accessibilityHidden(true)
            heading("Connect to Stud.IP", "Sign in with your Universität Göttingen account. Your password stays in your Mac’s Keychain.")
            if store.signedIn {
                Label(String(format: L("Signed in as %@"), store.username.isEmpty ? L("University web login") : store.username),
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary).symbolRenderingMode(.multicolor).padding(.top, 8)
            } else {
                SignInFields(store: store, showsActions: false).padding(.top, 8)
            }
        }
    }

    private var folder: some View {
        VStack(spacing: 16) {
            heading("Where should your courses go?", "StudSync creates one ordinary Finder folder per course.")
            FolderPreview(path: store.preferences.destination,
                          folders: store.visibleCourses.map(\.title).sorted { $0.localizedStandardCompare($1) == .orderedAscending },
                          upcoming: true) {
                Button(L("Change…")) { store.chooseDestination() }.disabled(store.isBusy)
            }
            Text(L("Untouched files update automatically. Local edits are kept; incoming versions appear beside them. Server deletions never delete your files."))
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .onAppear { if store.preferences.destination.isEmpty { store.preferences.destination = Self.suggestedFolder } }
    }

    private var courses: some View {
        VStack(spacing: 16) {
            heading("Which courses?", "Your current semester is already selected. You can change this later in Settings.")
            CoursePicker(store: store, listHeight: 260)
        }
        .onAppear {
            if !preselected, !store.preferences.setupComplete, store.preferences.selectedCourses.isEmpty {
                store.preferences.selectedCourses = Set(store.visibleCourses.map(\.id))
            }
            preselected = true
        }
    }

    private var firstSync: some View {
        VStack(spacing: 16) {
            if store.isBusy {
                heading("Loading your courses", L(store.status))
                ProgressView(value: Double(store.completed), total: Double(max(store.total, 1)))
                    .tint(StudSyncStyle.accent)
                Text("\(store.completed) / \(store.total)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            } else if !store.messages.isEmpty {
                heading("First sync needs attention", "Your setup is saved. StudSync tries again at the next sync.")
                FeedbackBar(store: store).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if store.status == "Up to date" {
                heading("Your courses are in Finder", String(format: L("%lld files from %lld courses are up to date."),
                                                             store.completed, store.preferences.selectedCourses.count))
            } else {
                // Cancelled or stopped without an error message: not a completed first sync.
                heading("First sync was interrupted", "Your setup is saved. StudSync continues at the next sync.")
            }
            FolderPreview(path: store.preferences.destination, folders: folders, upcoming: false, fresh: freshFolders) { EmptyView() }
            SettingsGroup { SyncPreferenceRows(store: store) }
        }
        .onAppear(perform: loadFolders)
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(L(title)).font(.title2.weight(.semibold))
            Text(L(subtitle)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Group {
                if step == .review {
                    Button(L("Close")) { close() }
                } else if step != .account {
                    Button(L("Back")) { step = SetupStep(rawValue: step.rawValue - 1) ?? .account }.disabled(store.isBusy)
                }
            }
            .frame(width: 112, alignment: .leading)
            Spacer()
            HStack(spacing: 8) {
                ForEach(SetupStep.allCases, id: \.rawValue) { item in
                    Circle().fill(item == step ? AnyShapeStyle(StudSyncStyle.accent) : AnyShapeStyle(.quaternary)).frame(width: 6, height: 6)
                }
            }
            .accessibilityElement().accessibilityLabel(String(format: L("Step %lld of %lld"), step.rawValue + 1, SetupStep.allCases.count))
            Spacer()
            primary.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).fixedSize()
                .frame(width: 112, alignment: .trailing)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder private var primary: some View {
        switch step {
        case .account where !store.signedIn:
            Button(L("Sign in")) { store.connect() }.disabled(store.username.isEmpty || store.password.isEmpty || store.isBusy)
        case .account, .folder:
            Button(L("Continue")) { step = SetupStep(rawValue: step.rawValue + 1) ?? .review }.disabled(!store.canContinueSetup(step))
        case .courses:
            Button(L("Sync")) { if store.finishSetup() { step = .review } }
                .disabled(!store.canContinueSetup(step))
        case .review:
            Button(L("Open in Finder")) { store.reveal(); close() }.disabled(store.isBusy)
        }
    }

    // MARK: Data

    private var freshFolders: Set<String> {
        Set(store.changes.filter { Calendar.current.isDateInToday($0.date) }
            .compactMap { StatusPanel.courseName(for: $0.path, root: store.preferences.destination) })
    }

    private func loadFolders() {
        let root = URL(fileURLWithPath: store.preferences.destination, isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

/// A small Finder-style window: the chosen folder and the course folders inside it.
/// While choosing, the course folders are a muted preview; after the first sync they are real and new ones carry the fold-red marker.
struct FolderPreview<Accessory: View>: View {
    let path: String
    let folders: [String]
    let upcoming: Bool
    var fresh: Set<String> = []
    @ViewBuilder let accessory: Accessory
    private let limit = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(for: .folder)).resizable().frame(width: 32, height: 32).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text((path as NSString).lastPathComponent).fontWeight(.medium)
                    Text((path as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                accessory
            }
            .padding(12)
            Divider()
            VStack(spacing: 0) {
                if folders.isEmpty {
                    Text(L(upcoming ? "Your course folders will appear here." : "No course folders yet."))
                        .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 32)
                }
                ForEach(Array(folders.prefix(limit).enumerated()), id: \.offset) { _, name in // course titles can repeat
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(for: .folder)).resizable().frame(width: 16, height: 16)
                            .opacity(upcoming ? 0.5 : 1).accessibilityHidden(true)
                        Text(name).lineLimit(1).foregroundStyle(upcoming ? .secondary : .primary)
                        Spacer(minLength: 8)
                        if fresh.contains(name) { NewMarker() }
                    }
                    .frame(minHeight: 28)
                }
                if folders.count > limit {
                    Text(String(format: L("%lld more"), folders.count - limit)).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading).padding(.leading, 24)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
    }
}
