import Foundation

/// Computed state shown in the UI, driven by the Claude.ai API.
struct UsageSnapshot: Equatable {
    let sessionPercent: Double     // 0.0-1.0 (from API's utilization / 100)
    let sessionResetAt: Date?
    let weeklyPercent: Double      // 0.0-1.0
    let weeklyResetAt: Date?
    let isLoading: Bool
    let isLoggedIn: Bool
    let errorMessage: String?

    init(
        sessionPercent: Double,
        sessionResetAt: Date?,
        weeklyPercent: Double,
        weeklyResetAt: Date?,
        isLoading: Bool,
        isLoggedIn: Bool,
        errorMessage: String? = nil
    ) {
        self.sessionPercent = sessionPercent
        self.sessionResetAt = sessionResetAt
        self.weeklyPercent = weeklyPercent
        self.weeklyResetAt = weeklyResetAt
        self.isLoading = isLoading
        self.isLoggedIn = isLoggedIn
        self.errorMessage = errorMessage
    }

    static let empty = UsageSnapshot(
        sessionPercent: 0, sessionResetAt: nil,
        weeklyPercent: 0, weeklyResetAt: nil,
        isLoading: true, isLoggedIn: false
    )
}
