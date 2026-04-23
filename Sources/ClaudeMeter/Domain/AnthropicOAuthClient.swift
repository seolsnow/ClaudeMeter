import Foundation
import Security
import os

private let log = Logger(subsystem: "com.devsisters.claudemeter", category: "OAuth")

struct OAuthCredentials: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Int64
    var scopes: [String]?
    var subscriptionType: String?
    var rateLimitTier: String?
}

struct OAuthProfile: Codable {
    struct Account: Codable {
        let uuid: String
        let email: String?
        let fullName: String?
        let displayName: String?
        enum CodingKeys: String, CodingKey {
            case uuid, email = "email_address"
            case fullName = "full_name", displayName = "display_name"
        }
    }
    struct Org: Codable {
        let uuid: String
        let name: String
        let rateLimitTier: String?
        enum CodingKeys: String, CodingKey {
            case uuid, name
            case rateLimitTier = "rate_limit_tier"
        }
    }
    let account: Account
    let organization: Org
}

struct UsageWindow: Codable {
    let utilization: Double  // 0-100 percentage
    let resetsAt: String?    // ISO8601

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct OAuthUsageResponse: Codable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

enum OAuthError: Error, Equatable {
    case missingCredentials      // Keychain item doesn't exist (Claude Code not set up)
    case keychainAccessDenied    // Keychain item exists but can't be read/parsed
    case authRevoked             // Server returned 401/403 for a Bearer call
    case refreshFailed(Int)
    case httpError(Int)
}

/// Reads Claude Code's OAuth credentials from Keychain and calls api.anthropic.com
/// using Bearer auth. Refreshes the access token when it's close to expiry.
final class AnthropicOAuthClient: @unchecked Sendable {
    private static let service = "Claude Code-credentials"
    private static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    private static let apiBase = URL(string: "https://api.anthropic.com")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let betaHeader = "oauth-2025-04-20"
    private static let decoder = JSONDecoder()

    private let session: URLSession

    // Keychain reads trigger a user consent prompt on ad-hoc-signed builds
    // (cdhash-pinned ACL). Cache once per app launch so the periodic refresh
    // cycle doesn't re-hit Keychain. Refreshed tokens stay in memory; the
    // Claude Code CLI manages the on-disk item.
    private let lock = NSLock()
    private var cachedCreds: OAuthCredentials?

    init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        // Cap at 15s so a hung request can't overlap with the next 60s tick.
        // URLSession's default (60s) would leave the prior request alive when
        // the timer fires again, doubling in-flight load against /oauth/usage.
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func fetchProfile() async throws -> OAuthProfile {
        let token = try await validAccessToken()
        return try await get("/api/oauth/profile", token: token)
    }

    func fetchUsage() async throws -> OAuthUsageResponse {
        let token = try await validAccessToken()
        return try await get("/api/oauth/usage", token: token)
    }

    // MARK: - Token management

    private func validAccessToken() async throws -> String {
        var current: OAuthCredentials
        if let cached = lock.withLock({ cachedCreds }) {
            current = cached
        } else {
            current = try Self.loadCredentials()
            lock.withLock { cachedCreds = current }
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        if current.expiresAt - nowMs < 60_000 {
            current = try await refresh(current)
            let refreshed = current
            lock.withLock { cachedCreds = refreshed }
        }
        return current.accessToken
    }

    private func refresh(_ creds: OAuthCredentials) async throws -> OAuthCredentials {
        var req = URLRequest(url: Self.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": creds.refreshToken,
            "client_id": Self.clientID,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.refreshFailed(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OAuthError.refreshFailed(http.statusCode)
        }

        struct TokenResponse: Codable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int?   // seconds
            let expires_at: Int64? // milliseconds
            let scope: String?
        }
        let decoded = try Self.decoder.decode(TokenResponse.self, from: data)

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let expiresAt: Int64
        if let ms = decoded.expires_at {
            expiresAt = ms
        } else if let secs = decoded.expires_in {
            expiresAt = nowMs + Int64(secs) * 1000
        } else {
            expiresAt = nowMs + 3_600_000  // 1 h fallback
        }

        return OAuthCredentials(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? creds.refreshToken,
            expiresAt: expiresAt,
            scopes: decoded.scope.map { $0.split(separator: " ").map(String.init) } ?? creds.scopes,
            subscriptionType: creds.subscriptionType,
            rateLimitTier: creds.rateLimitTier
        )
    }

    // MARK: - HTTP

    private func get<T: Decodable>(_ path: String, token: String) async throws -> T {
        let url = Self.apiBase.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")

        let startedAt = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
            log.error("GET \(path, privacy: .public) failed in \(ms)ms: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
        guard let http = response as? HTTPURLResponse else {
            log.error("GET \(path, privacy: .public) non-HTTP response in \(ms)ms")
            throw OAuthError.httpError(-1)
        }
        let status = http.statusCode
        if status == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After") ?? "none"
            log.notice("GET \(path, privacy: .public) 429 in \(ms)ms, retry-after=\(retryAfter, privacy: .public)")
            throw OAuthError.httpError(429)
        }
        if status == 401 || status == 403 {
            // Token was accepted syntactically but server rejected it —
            // revoked, expired beyond refresh, or scope stripped. Drop the
            // in-memory copy so the next call re-reads Keychain (where the
            // Claude Code CLI may have stored fresh credentials).
            lock.withLock { cachedCreds = nil }
            log.error("GET \(path, privacy: .public) \(status) in \(ms)ms — auth revoked")
            throw OAuthError.authRevoked
        }
        guard (200..<300).contains(status) else {
            log.error("GET \(path, privacy: .public) \(status) in \(ms)ms")
            throw OAuthError.httpError(status)
        }
        log.info("GET \(path, privacy: .public) 200 in \(ms)ms")
        return try Self.decoder.decode(T.self, from: data)
    }

    // MARK: - Keychain

    static func loadCredentials() throws -> OAuthCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            throw OAuthError.missingCredentials
        }
        guard status == errSecSuccess, let data = item as? Data else {
            // Keychain found something but we couldn't read it — typically
            // errSecAuthFailed / errSecInteractionNotAllowed (the user
            // dismissed the consent prompt on ad-hoc-signed builds).
            throw OAuthError.keychainAccessDenied
        }

        struct Wrapper: Codable {
            let claudeAiOauth: OAuthCredentials
        }
        do {
            return try Self.decoder.decode(Wrapper.self, from: data).claudeAiOauth
        } catch {
            // Credentials blob present but doesn't match our expected shape.
            // Likely a format change in Claude Code CLI; treat as "can't use"
            // rather than "not installed" so the UI tells the user to update.
            throw OAuthError.keychainAccessDenied
        }
    }

}
