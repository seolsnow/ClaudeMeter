import SwiftUI
import WebKit

struct DetailPanelView: View {
    @Bindable var store: UsageStore
    let settings: Settings
    let onQuit: () -> Void

    @State private var nowTick: Date = Date()
    @State private var launchAtLogin: Bool = false
    @AppStorage("showSessionInMenuBar") private var showSession: Bool = true
    @AppStorage("showWeeklyInMenuBar") private var showWeekly: Bool = true
    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.snapshot.isLoggedIn && !store.snapshot.isLoading {
                loginSection
                Divider()
            } else {
                sessionSection
                Divider()
                weeklySection
                Divider()
                if let errorMessage = store.snapshot.errorMessage {
                    errorBanner(errorMessage)
                }
            }
            footerSection
        }
        .padding(14)
        .frame(width: 320)
        .onReceive(tickTimer) { nowTick = $0 }
        .task { await store.refresh() }
        .onAppear { launchAtLogin = settings.launchAtLogin }
    }

    // MARK: - Sections

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not logged in to Claude")
                .font(.headline)
            Text("Log in to view your usage.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Log in to Claude") {
                LoginWindowController.shared.open {
                    Task { await store.refresh() }
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Session (5h)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Menu Bar", isOn: $showSession)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption2)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(percentInt(store.snapshot.sessionPercent))%")
                    .font(.system(size: 28, weight: .semibold)).monospacedDigit()
                Spacer()
                if store.snapshot.isLoading {
                    ProgressView().scaleEffect(0.6)
                }
            }
            ProgressBarView(percent: store.snapshot.sessionPercent, width: 290, height: 6)
            Text(resetText(store.snapshot.sessionResetAt))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Weekly (7d)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Menu Bar", isOn: $showWeekly)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption2)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(percentInt(store.snapshot.weeklyPercent))%")
                    .font(.system(size: 28, weight: .semibold)).monospacedDigit()
                Spacer()
                if store.snapshot.isLoading {
                    ProgressView().scaleEffect(0.6)
                }
            }
            ProgressBarView(percent: store.snapshot.weeklyPercent, width: 290, height: 6)
            Text(resetText(store.snapshot.weeklyResetAt))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var footerSection: some View {
        VStack(spacing: 8) {
            // Org picker (compact)
            if store.snapshot.isLoggedIn && store.organizations.count > 1 {
                Picker("Org", selection: Binding(
                    get: { store.orgId ?? "" },
                    set: { store.setOrganization($0) }
                )) {
                    ForEach(store.organizations) { org in
                        Text(org.name).tag(org.uuid)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.caption)
            }

            HStack {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onChange(of: launchAtLogin) { _, val in settings.setLaunchAtLogin(val) }

                Spacer()

                if store.snapshot.isLoggedIn {
                    Button("Log out") { logOut() }
                        .font(.caption)
                }
            }

            HStack {
                Button("Refresh") { Task { await store.refresh() } }
                Spacer()
                Text("ClaudeMeter")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit", action: onQuit)
            }
        }
    }

    // MARK: - Helpers

    private func percentInt(_ p: Double) -> Int { Int((p * 100).rounded()) }

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    private func resetText(_ resetAt: Date?) -> String {
        guard let resetAt else { return "No reset time available." }
        let remaining = resetAt.timeIntervalSince(nowTick)
        if remaining <= 0 { return "Resetting now." }
        return "Resets at \(Self.resetFormatter.string(from: resetAt))"
    }

    private func logOut() {
        // Clear only claude.ai cookies from HTTPCookieStorage
        let cookieStorage = HTTPCookieStorage.shared
        for cookie in cookieStorage.cookies(for: URL(string: "https://claude.ai")!) ?? [] {
            cookieStorage.deleteCookie(cookie)
        }
        // Clear only claude.ai cookies from WKWebView (preserve Google session for quick re-login)
        let store = self.store
        let wkCookieStore = WKWebsiteDataStore.default().httpCookieStore
        wkCookieStore.getAllCookies { cookies in
            let group = DispatchGroup()
            for cookie in cookies where cookie.domain.contains("claude.ai") {
                group.enter()
                wkCookieStore.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                Task { @MainActor in
                    await store.refresh()
                }
            }
        }
    }
}
