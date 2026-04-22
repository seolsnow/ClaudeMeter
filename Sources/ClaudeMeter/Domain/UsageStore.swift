import Foundation
import Observation

/// Why the panel is showing the setup (not-logged-in) branch. Lets the view
/// pick a message that reflects the actual failure mode instead of always
/// saying "Claude Code not detected."
enum SetupReason {
    case notDetected       // No Keychain item — Claude Code not installed/logged-in
    case accessDenied      // Keychain item present but can't read/parse it
    case authRevoked       // Server rejected a syntactically-valid token (401/403)
}

@Observable
@MainActor
final class UsageStore {
    var snapshot: UsageSnapshot = .empty
    var accountLabel: String?      // e.g. "hanseol@example.com · Acme"
    var lastSuccessAt: Date?       // last time /oauth/usage returned 2xx
    var setupReason: SetupReason?  // only meaningful when snapshot.isLoggedIn == false

    private let api = AnthropicOAuthClient()
    private var timer: Timer?
    private var started = false
    private var inflightRefresh: Task<Void, Never>?
    private var profileAttempts = 0
    private static let profileMaxAttempts = 3

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

    // Coalesces concurrent callers (60s timer, panel-open .task, warmup loop).
    // Without this, a single 429 event can amplify into several parallel
    // /oauth/usage hits when the timer fires while a previous request is still
    // in flight, compounding rate-limit pressure.
    func refresh() async {
        if let inflight = inflightRefresh {
            await inflight.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh()
        }
        inflightRefresh = task
        await task.value
        inflightRefresh = nil
    }

    private func performRefresh() async {
        do {
            let u = try await api.fetchUsage()

            // Profile (email, org name) is effectively static. Only attempt
            // after usage succeeds, so a 429 burst on /oauth/usage doesn't
            // also burn our budget on /oauth/profile. Cap attempts so a
            // permanently-failing profile endpoint doesn't poll forever.
            if accountLabel == nil, profileAttempts < Self.profileMaxAttempts {
                profileAttempts += 1
                if let p = try? await api.fetchProfile() {
                    let email = p.account.email ?? p.account.displayName ?? ""
                    accountLabel = email.isEmpty ? p.organization.name : "\(email) · \(p.organization.name)"
                }
            }

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
            setupReason = nil
        } catch OAuthError.missingCredentials {
            enterSetupState(.notDetected)
        } catch OAuthError.keychainAccessDenied {
            enterSetupState(.accessDenied)
        } catch OAuthError.authRevoked {
            enterSetupState(.authRevoked)
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

    private func enterSetupState(_ reason: SetupReason) {
        snapshot = UsageSnapshot(
            sessionPercent: 0, sessionResetAt: nil,
            weeklyPercent: 0, weeklyResetAt: nil,
            isLoading: false, isLoggedIn: false
        )
        accountLabel = nil
        setupReason = reason
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
