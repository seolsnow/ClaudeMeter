import SwiftUI

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
                setupSection
                Divider()
            } else {
                sessionSection
                Divider()
                weeklySection
                if let account = store.accountLabel {
                    Divider()
                    accountBanner(account)
                }
                if let errorMessage = store.snapshot.errorMessage {
                    Divider()
                    errorBanner(errorMessage)
                }
            }
            footerSection
        }
        .padding(14)
        .frame(width: 320)
        .onReceive(tickTimer) { nowTick = $0 }
        .task {
            if let last = store.lastSuccessAt, Date().timeIntervalSince(last) < 60 { return }
            await store.refresh()
        }
        .onAppear { launchAtLogin = settings.launchAtLogin }
    }

    // MARK: - Sections

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Code not detected")
                .font(.headline)
            Text("ClaudeMeter reads usage from the Claude Code CLI's Keychain credentials.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Install Claude Code and run `claude` once to sign in, then click Retry.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry") { Task { await store.refresh() } }
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

    private func accountBanner(_ label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
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
        HStack {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: launchAtLogin) { _, val in settings.setLaunchAtLogin(val) }
            Spacer()
            Text("ClaudeMeter")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit", action: onQuit)
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

}
