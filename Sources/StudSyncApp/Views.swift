import SwiftUI
import AppKit
import WebKit
import StudSyncCore

let appResourceBundle = Bundle.main.resourceURL
    .flatMap { Bundle(url: $0.appendingPathComponent("StudSync_StudSyncApp.bundle")) } ?? .module

func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: appResourceBundle, comment: "")
}

struct StatusPanel: View {
    @Bindable var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(nsImage: AppImages.logo)
                    .resizable().scaledToFit().frame(width: 32, height: 32).accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text("StudSync").font(.headline)
                    Text(L(store.paused ? "Paused" : store.status)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if store.isBusy { ProgressView().controlSize(.small) }
            }
            if store.isBusy && store.total > 0 {
                ProgressView(value: Double(store.completed), total: Double(store.total))
                Text("\(store.completed) / \(store.total)").font(.caption).monospacedDigit()
            }
            HStack {
                stat("Last sync", value: store.preferences.lastSync.map { $0.formatted(date: .omitted, time: .shortened) } ?? L("Not yet"))
                Spacer()
                stat("Next sync", value: store.nextSync.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                Spacer()
                stat("Courses", value: String(store.preferences.selectedCourses.count))
            }
            if store.bytes > 0 { Text(ByteCountFormatter.string(fromByteCount: store.bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
            ForEach(store.messages, id: \.self) { message in
                Text(L(message)).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(L(store.isBusy ? "Cancel" : "Sync now")) {
                    if store.isBusy { store.cancel() } else { store.sync() }
                }.buttonStyle(.borderedProminent).disabled(!store.isBusy && !store.canSync)
                Button(L(store.paused ? "Resume" : "Pause")) { store.setPaused(!store.paused) }.disabled(store.isBusy)
                Spacer()
                Button { store.reveal() } label: { Image(systemName: "folder") }.help(L("Open in Finder")).disabled(store.preferences.destination.isEmpty)
            }
            Divider()
            Text(L("Recent changes")).font(.subheadline.bold())
            if store.changes.isEmpty {
                ContentUnavailableView(L("No changes yet"), systemImage: "checkmark.circle", description: Text(L("Downloaded files will appear here.")))
                    .frame(height: 110)
            } else {
                ForEach(store.changes.prefix(5)) { change in
                    Button { store.reveal(change.path) } label: {
                        HStack(alignment: .top) {
                            Image(systemName: change.conflict ? "exclamationmark.triangle" : "doc.badge.arrow.up")
                                .foregroundStyle(change.conflict ? .orange : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(change.name).lineLimit(1)
                                Text(change.conflict ? L("Local edits preserved") : change.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).help(L("Reveal in Finder"))
                }
            }
            Divider()
            HStack {
                Button(L(store.preferences.setupComplete ? "Settings…" : "Set up StudSync…")) { AppWindows.show(store) }
                Spacer()
                Button(L("Quit")) { NSApp.terminate(nil) }
            }.font(.caption)
        }.padding(18).frame(width: 380).tint(StudSyncStyle.accent)
            .background(MenuBarPanelAnchor())
    }
    private func stat(_ key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(key)).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.bold()).monospacedDigit()
        }
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
                        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                            Task { @MainActor in
                                guard store.showWebLogin else { return }
                                store.adoptWebSession(cookies)
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
