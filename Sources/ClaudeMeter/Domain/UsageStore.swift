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
        // fetchOrganizations doubles as a login check — reuse the result
        guard let orgs = try? await api.fetchOrganizations(), !orgs.isEmpty else {
            snapshot = UsageSnapshot(
                sessionPercent: 0, sessionResetAt: nil,
                weeklyPercent: 0, weeklyResetAt: nil,
                isLoading: false, isLoggedIn: false
            )
            return
        }

        if organizations.isEmpty {
            organizations = orgs
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
                isLoggedIn: true
            )
        }
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
