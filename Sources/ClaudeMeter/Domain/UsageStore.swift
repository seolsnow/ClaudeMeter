import Foundation
import Observation

@Observable
@MainActor
final class UsageStore {
    var snapshot: UsageSnapshot = .empty
    var organizations: [Organization] = []

    nonisolated(unsafe) private let api = ClaudeAPIClient()
    private var timer: Timer?
    private(set) var orgId: String?

    private var started = false

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init() {
        orgId = UserDefaults.standard.string(forKey: "selectedOrgId")
        Task { @MainActor in
            self.start()
        }
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
        let orgsResult: [Organization]
        do {
            orgsResult = try await api.fetchOrganizations()
        } catch {
            let isAuthError = error is DecodingError || (error as? APIError) == .sessionInvalid
            if isAuthError || !snapshot.isLoggedIn {
                orgId = nil
                UserDefaults.standard.removeObject(forKey: "selectedOrgId")
                snapshot = UsageSnapshot(
                    sessionPercent: 0, sessionResetAt: nil,
                    weeklyPercent: 0, weeklyResetAt: nil,
                    isLoading: false, isLoggedIn: false
                )
            } else {
                // Network/server failure while logged in — keep stale data, surface error.
                snapshot = UsageSnapshot(
                    sessionPercent: snapshot.sessionPercent,
                    sessionResetAt: snapshot.sessionResetAt,
                    weeklyPercent: snapshot.weeklyPercent,
                    weeklyResetAt: snapshot.weeklyResetAt,
                    isLoading: false,
                    isLoggedIn: true,
                    errorMessage: Self.describe(error)
                )
            }
            return
        }

        guard !orgsResult.isEmpty else {
            snapshot = UsageSnapshot(
                sessionPercent: 0, sessionResetAt: nil,
                weeklyPercent: 0, weeklyResetAt: nil,
                isLoading: false, isLoggedIn: false
            )
            return
        }

        organizations = orgsResult

        // Reset saved orgId if it no longer belongs to current account
        if let saved = orgId, !orgsResult.contains(where: { $0.uuid == saved }) {
            orgId = nil
            UserDefaults.standard.removeObject(forKey: "selectedOrgId")
        }

        // Auto-select org: try each until one returns actual usage data
        if orgId == nil {
            for org in organizations {
                if let usage = try? await api.fetchUsage(orgId: org.uuid),
                   usage.fiveHour != nil || usage.sevenDay != nil {
                    orgId = org.uuid
                    UserDefaults.standard.set(org.uuid, forKey: "selectedOrgId")
                    break
                }
            }
        }

        guard let orgId else {
            snapshot = UsageSnapshot(
                sessionPercent: 0, sessionResetAt: nil,
                weeklyPercent: 0, weeklyResetAt: nil,
                isLoading: false, isLoggedIn: true
            )
            return
        }

        do {
            let usage = try await api.fetchUsage(orgId: orgId)

            let sessionReset = usage.fiveHour?.resetsAt.flatMap { Self.isoFormatter.date(from: $0) }
            let weeklyReset = usage.sevenDay?.resetsAt.flatMap { Self.isoFormatter.date(from: $0) }

            snapshot = UsageSnapshot(
                sessionPercent: (usage.fiveHour?.utilization ?? 0) / 100.0,
                sessionResetAt: sessionReset,
                weeklyPercent: (usage.sevenDay?.utilization ?? 0) / 100.0,
                weeklyResetAt: weeklyReset,
                isLoading: false,
                isLoggedIn: true
            )
        } catch {
            snapshot = UsageSnapshot(
                sessionPercent: snapshot.sessionPercent,
                sessionResetAt: snapshot.sessionResetAt,
                weeklyPercent: snapshot.weeklyPercent,
                weeklyResetAt: snapshot.weeklyResetAt,
                isLoading: false,
                isLoggedIn: true,
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
                return "Can't reach Claude.ai."
            default:
                return "Network error."
            }
        }
        return "Couldn't load usage."
    }

    func setOrganization(_ newOrgId: String) {
        orgId = newOrgId
        UserDefaults.standard.set(newOrgId, forKey: "selectedOrgId")
        Task { await refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
