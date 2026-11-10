import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers
import StudSyncCore

let appResourceBundle = Bundle.main.resourceURL
    .flatMap { Bundle(url: $0.appendingPathComponent("StudSync_StudSyncApp.bundle")) } ?? .module

/// Strings come from the app bundle; README screenshots switch it to render each language.
nonisolated(unsafe) var localizationBundle = appResourceBundle

func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: localizationBundle, comment: "")
}

struct StatusPanel: View {
    @Bindable var store: AppStore
    @State private var folders: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if store.isBusy && store.total > 0 {
                ProgressView(value: Double(store.completed), total: Double(store.total)) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(store.completed) / \(store.total)").monospacedDigit()
                }
                .padding(.horizontal, 4).tint(StudSyncStyle.accent)
            }
            if !store.messages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.messages, id: \.self) { message in
                        Label {
                            Text(L(message)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                    }
                }
                .font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading).panelGroup()
            }
            recentChanges
            if !folders.isEmpty { courseFolders }
            footer
        }
        .padding(16).frame(width: 360)
        .background(MenuBarPanelAnchor())
        .onAppear(perform: loadFolders)
        .onChange(of: store.changes.count) { loadFolders() }
        .onChange(of: store.preferences.destination) { loadFolders() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppImages.logo)
                .resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("StudSync").font(.headline)
                HStack(spacing: 4) {
                    Image(systemName: statusSymbol).foregroundStyle(statusColor)
                        .symbolEffect(.rotate, isActive: store.isBusy)
                    Text(L(store.paused ? "Paused" : store.status)).foregroundStyle(.secondary).lineLimit(1)
                }.font(.caption)
            }
            Spacer(minLength: 8)
            PanelGlassContainer {
                HStack(spacing: 8) {
                    panelButton(store.isBusy ? "xmark" : "arrow.clockwise", help: store.isBusy ? "Cancel" : "Sync now") {
                        if store.isBusy { store.cancel() } else { store.sync() }
                    }
                    .disabled(!store.isBusy && !store.canSync).keyboardShortcut("r")
                    panelButton(store.paused ? "play" : "pause", help: store.paused ? "Resume" : "Pause") {
                        store.setPaused(!store.paused)
                    }.disabled(store.isBusy)
                    Menu {
                        Button(L("Open in Finder")) { store.reveal() }.disabled(store.preferences.destination.isEmpty)
                        Button(L(store.preferences.setupComplete ? "Settings…" : "Set up StudSync…")) { AppWindows.show(store) }
                            .keyboardShortcut(",")
                        Button(L("Start onboarding")) { AppWindows.showOnboarding(store) }.disabled(store.isBusy)
                        Button(L("Check for Updates…")) { AppUpdates.shared.check() }.disabled(!AppUpdates.shared.canCheck)
                        Divider()
                        Button(L("Quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
                    } label: {
                        Image(systemName: "ellipsis").panelCircle()
                    }
                    .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain)
                    .fixedSize().help(L("More")).accessibilityLabel(L("More"))
                }
            }
        }
    }

    private var statusSymbol: String {
        if store.needsAttention { return "exclamationmark.triangle.fill" }
        if store.paused { return "pause.circle.fill" }
        if store.isBusy { return "arrow.triangle.2.circlepath" }
        return store.status == "Up to date" ? "checkmark.circle.fill" : "circle.fill"
    }

    private var statusColor: Color {
        if store.needsAttention { return .orange }
        if store.isBusy { return StudSyncStyle.accent }
        return !store.paused && store.status == "Up to date" ? .green : .secondary
    }

    private var recentChanges: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.changes.isEmpty {
                ContentUnavailableView(L("No changes yet"), systemImage: "doc", description: Text(L("Downloaded files will appear here.")))
                    .frame(maxWidth: .infinity).frame(height: 120)
            } else {
                ForEach(Self.dayGroups(Array(store.changes.prefix(6))), id: \.day) { group in
                    groupLabel(Self.dayTitle(group.day))
                    ForEach(group.changes) { change in
                        PanelRow(help: "Reveal in Finder", action: { store.reveal(change.path) }) { changeLabel(change) }
                    }
                }
            }
        }.padding(4).panelGroup()
    }

    private func groupLabel(_ title: String) -> some View {
        Text(title).font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4)
    }

    private func changeLabel(_ change: Change) -> some View {
        HStack(spacing: 8) {
            Group {
                if change.conflict {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 15)).foregroundStyle(.orange)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (change.name as NSString).pathExtension) ?? .data))
                        .resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                }
            }.frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(change.name).lineLimit(1).truncationMode(.middle)
                Text(change.conflict ? L("Local edits preserved") : Self.courseName(for: change.path, root: store.preferences.destination) ?? "")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(change.date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }.frame(minHeight: 32)
    }

    private var courseFolders: some View {
        let fresh = Dictionary(grouping: store.changes.filter { Calendar.current.isDateInToday($0.date) }) {
            Self.courseName(for: $0.path, root: store.preferences.destination) ?? ""
        }
        return VStack(alignment: .leading, spacing: 0) {
            groupLabel(L("Courses"))
            let rows = ForEach(folders, id: \.self) { folder in
                PanelRow(help: "Open in Finder", action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: store.preferences.destination).appendingPathComponent(folder, isDirectory: true))
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder").font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 20)
                        Text(folder).lineLimit(1)
                        Spacer(minLength: 8)
                        if let count = fresh[folder]?.count {
                            NewMarker()
                            Text(String(format: L("%lld new"), count)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }.frame(minHeight: 24)
                }
            }
            // Rows are 32 pt; beyond the limit the list scrolls so the panel stays on screen.
            if folders.count > Self.visibleFolders {
                ScrollView { VStack(spacing: 0) { rows } }.frame(height: (CGFloat(Self.visibleFolders) + 0.5) * 32)
            } else {
                rows
            }
        }.padding(4).panelGroup()
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text(String(format: L("Synced %@"), store.preferences.lastSync.map { $0.formatted(date: .omitted, time: .shortened) } ?? L("Not yet")))
            if let next = store.nextSync {
                Text("·")
                Text(String(format: L("Next %@"), next.formatted(date: .omitted, time: .shortened)))
            }
            Spacer(minLength: 8)
            if store.bytes > 0 { Text(ByteCountFormatter.string(fromByteCount: store.bytes, countStyle: .file)) }
        }
        .font(.caption).foregroundStyle(.secondary).monospacedDigit().padding(.horizontal, 8)
    }

    private func panelButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).panelCircle() }
            .buttonStyle(.plain).help(L(help)).accessibilityLabel(L(help))
    }

    private func loadFolders() {
        let destination = store.preferences.destination
        guard !destination.isEmpty, let urls = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: destination, isDirectory: true), includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { folders = []; return }
        folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static let visibleFolders = 6

    static func courseName(for path: String, root: String) -> String? {
        guard !root.isEmpty else { return nil }
        let base = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL.pathComponents
        let parts = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard parts.count > base.count + 1, Array(parts.prefix(base.count)) == base else { return nil }
        return parts[base.count]
    }

    static func dayGroups(_ changes: [Change], calendar: Calendar = .current) -> [(day: Date, changes: [Change])] {
        var groups: [(day: Date, changes: [Change])] = []
        for change in changes {
            let day = calendar.startOfDay(for: change.date)
            if groups.last?.day == day { groups[groups.count - 1].changes.append(change) }
            else { groups.append((day, [change])) }
        }
        return groups
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium; formatter.timeStyle = .none; formatter.doesRelativeDateFormatting = true
        return formatter
    }()
    static func dayTitle(_ day: Date) -> String { dayFormatter.string(from: day) }
}

/// StudSync's signature: new material is marked with the fold red from the logo, and red means nothing else.
struct NewMarker: View {
    var body: some View {
        Circle().fill(StudSyncStyle.fold).frame(width: 6, height: 6).accessibilityLabel(L("New"))
    }
}

private struct PanelRow<Content: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            content.padding(.horizontal, 8).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }.help(L(help))
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Liquid Glass on macOS 26 when built with the macOS 26 SDK; plain content otherwise.
private struct PanelGlassContainer<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { GlassEffectContainer(spacing: 8) { content } } else { content }
        #else
        content
        #endif
    }
}

private extension View {
    /// Uniform, untinted round control: neutral glass on macOS 26, a quiet fill otherwise.
    func panelCircle() -> some View { modifier(PanelCircle()) }

    /// A quiet content group: one surface step above the panel, no glass on glass.
    func panelGroup() -> some View {
        background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PanelCircle: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @ViewBuilder func body(content: Content) -> some View {
        let label = content.font(.system(size: 13, weight: .medium)).foregroundStyle(isEnabled ? .primary : .tertiary)
            .frame(width: 28, height: 28).contentShape(Circle())
        #if compiler(>=6.2)
        if #available(macOS 26, *) { label.glassEffect(.regular.interactive(), in: .circle) } else { label.background(.quinary, in: Circle()) }
        #else
        label.background(.quinary, in: Circle())
        #endif
    }
}

struct WebLogin: View {
    @Bindable var store: AppStore
    @State private var webView = WKWebView()
    var body: some View {
        VStack(spacing: 0) {
            WebContent(webView: webView)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("Finish the official university sign-in, then continue.")).font(.caption)
                    Spacer()
                    Button(L("Cancel")) { store.cancel(); store.showWebLogin = false }
                    Button(L("Continue")) {
                        let attempt = store.webLoginAttempt
                        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                            Task { @MainActor in
                                store.adoptWebSession(cookies, attempt: attempt)
                            }
                        }
                    }.buttonStyle(.borderedProminent).disabled(store.isBusy)
                }
                ForEach(store.messages, id: \.self) { message in
                    Text(L(message)).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }.padding()
        }.frame(width: 760, height: 660)
        .onAppear { webView.load(URLRequest(url: StudIPClient.origin.appendingPathComponent("dispatch.php/my_courses"))) }
    }
}
struct WebContent: NSViewRepresentable {
    var webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) { }
}
