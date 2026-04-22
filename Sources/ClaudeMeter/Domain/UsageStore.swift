import Foundation
import Observation

@Observable
@MainActor
final class UsageStore {
    var snapshot: UsageSnapshot = .empty
    var accountLabel: String?      // e.g. "hanseol@example.com · Acme"
    var lastSuccessAt: Date?       // last time /oauth/usage returned 2xx

    nonisolated(unsafe) private let api = AnthropicOAuthClient()
    private var timer: Timer?
    private var started = false

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init() {
        Task { @MainActor in self.start() }
    }

    private static let warmupInterval: Duration = .seconds(5)
    private static let warmupMaxAttempts = 10

    func start() {
        guard !started else { return }
        started = true

        Task { @MainActor in await self.refresh() }

        // Cold-start warmup: the first refresh can fail if the user hasn't
        // answered the Keychain "Always Allow" prompt yet. Retry every 5s
        // (bounded) until the first success, so the panel doesn't sit in
        // "not detected" for up to 60s waiting on the main timer.
        Task { @MainActor [weak self] in
            for _ in 0..<Self.warmupMaxAttempts {
                try? await Task.sleep(for: Self.warmupInterval)
                guard let self, self.lastSuccessAt == nil else { return }
                await self.refresh()
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        // Profile (email, org name) is effectively static. Fetch once per app
        // launch, best-effort — failing here must not block the usage call or
        // surface an error, since the next cycle will retry until it succeeds.
        if accountLabel == nil, let p = try? await api.fetchProfile() {
            let email = p.account.email ?? p.account.displayName ?? ""
            accountLabel = email.isEmpty ? p.organization.name : "\(email) · \(p.organization.name)"
        }

        do {
            let u = try await api.fetchUsage()

            let sessionReset = u.fiveHour?.resetsAt.flatMap { Self.isoFormatter.date(from: $0) }
            let weeklyReset = u.sevenDay?.resetsAt.flatMap { Self.isoFormatter.date(from: $0) }

            snapshot = UsageSnapshot(
                sessionPercent: (u.fiveHour?.utilization ?? 0) / 100.0,
                sessionResetAt: sessionReset,
                weeklyPercent: (u.sevenDay?.utilization ?? 0) / 100.0,
                weeklyResetAt: weeklyReset,
                isLoading: false,
                isLoggedIn: true
            )
            lastSuccessAt = Date()
        } catch OAuthError.missingCredentials {
            snapshot = UsageSnapshot(
                sessionPercent: 0, sessionResetAt: nil,
                weeklyPercent: 0, weeklyResetAt: nil,
                isLoading: false, isLoggedIn: false
            )
            accountLabel = nil
        } catch {
            // Keep stale values. 429 is always suppressed — the panel will
            // surface it via the "Refresh delayed · updated Nm ago" row once
            // the delay crosses the staleness threshold. Other errors keep
            // the one-cycle (60s) grace window so a single transient failure
            // doesn't flash a banner.
            let is429: Bool = {
                if case OAuthError.httpError(429) = error { return true }
                return false
            }()
            let hasRecentSuccess = lastSuccessAt.map { Date().timeIntervalSince($0) < 60 } ?? false
            let suppress = is429 || hasRecentSuccess
            snapshot = UsageSnapshot(
                sessionPercent: snapshot.sessionPercent,
                sessionResetAt: snapshot.sessionResetAt,
                weeklyPercent: snapshot.weeklyPercent,
                weeklyResetAt: snapshot.weeklyResetAt,
                isLoading: false,
                isLoggedIn: snapshot.isLoggedIn,
                errorMessage: suppress ? nil : Self.describe(error)
            )
        }
    }

    private static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "No internet connection."
            case .timedOut:
                return "Request timed out."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Can't reach Anthropic."
            default:
                return "Network error."
            }
        }
        if case OAuthError.refreshFailed(let code) = error {
            return "Auth refresh failed (\(code))."
        }
        if case OAuthError.httpError(let code) = error {
            return "Server error (\(code))."
        }
        return "Couldn't load usage."
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
