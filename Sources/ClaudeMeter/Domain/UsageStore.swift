import Foundation
import Observation

@Observable
@MainActor
final class UsageStore {
    var snapshot: UsageSnapshot = .empty
    var accountLabel: String?      // e.g. "hanseol@example.com · Acme"

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

    func start() {
        guard !started else { return }
        started = true

        Task { await refresh() }

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        do {
            async let profile = api.fetchProfile()
            async let usage = api.fetchUsage()
            let (p, u) = try await (profile, usage)

            let email = p.account.email ?? p.account.displayName ?? ""
            accountLabel = email.isEmpty ? p.organization.name : "\(email) · \(p.organization.name)"

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
        } catch OAuthError.missingCredentials {
            snapshot = UsageSnapshot(
                sessionPercent: 0, sessionResetAt: nil,
                weeklyPercent: 0, weeklyResetAt: nil,
                isLoading: false, isLoggedIn: false
            )
            accountLabel = nil
        } catch {
            // Network/server failure — keep stale values, surface error.
            snapshot = UsageSnapshot(
                sessionPercent: snapshot.sessionPercent,
                sessionResetAt: snapshot.sessionResetAt,
                weeklyPercent: snapshot.weeklyPercent,
                weeklyResetAt: snapshot.weeklyResetAt,
                isLoading: false,
                isLoggedIn: snapshot.isLoggedIn,
                errorMessage: Self.describe(error)
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
