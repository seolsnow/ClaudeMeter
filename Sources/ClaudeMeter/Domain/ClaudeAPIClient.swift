import Foundation

struct Organization: Codable, Identifiable {
    let uuid: String
    let name: String
    var id: String { uuid }
}

struct UsageResponse: Codable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

struct UsageWindow: Codable {
    let utilization: Double  // 0-100 percentage
    let resetsAt: String?    // ISO8601

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

final class ClaudeAPIClient: @unchecked Sendable {
    private let baseURL = "https://claude.ai"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        self.session = URLSession(configuration: config)
    }

    private func apiRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai/", forHTTPHeaderField: "Referer")
        return request
    }

    func fetchOrganizations() async throws -> [Organization] {
        guard let url = URL(string: "\(baseURL)/api/organizations") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await session.data(for: apiRequest(url: url))
        return try JSONDecoder().decode([Organization].self, from: data)
    }

    func fetchUsage(orgId: String) async throws -> UsageResponse {
        guard let url = URL(string: "\(baseURL)/api/organizations/\(orgId)/usage") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await session.data(for: apiRequest(url: url))
        return try JSONDecoder().decode(UsageResponse.self, from: data)
    }
}
