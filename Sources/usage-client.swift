import Foundation

struct UsageLimit: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let shortTitle: String
    let percent: Double
    let resetsAt: Date?
}

enum UsageClientError: LocalizedError {
    case httpStatus(Int)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .httpStatus(401):
            "Unauthorized (401) — sign in to Claude CLI again"
        case .httpStatus(429):
            "Rate limited (429) — will retry shortly"
        case .httpStatus(let code):
            "Usage service returned HTTP \(code)"
        case .unexpectedResponse:
            "Unexpected usage response format"
        }
    }
}

enum UsageClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let betaHeader = "oauth-2025-04-20"
    static let requestTimeout: TimeInterval = 15

    static func fetchLimits(using credential: ClaudeCredential) async throws -> [UsageLimit] {
        var request = URLRequest(url: endpoint, timeoutInterval: requestTimeout)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageClientError.unexpectedResponse
        }
        guard http.statusCode == 200 else {
            throw UsageClientError.httpStatus(http.statusCode)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageClientError.unexpectedResponse
        }
        let limits = parseLimits(root)
        guard !limits.isEmpty else {
            throw UsageClientError.unexpectedResponse
        }
        return limits
    }

    private static func parseLimits(_ root: [String: Any]) -> [UsageLimit] {
        if let entries = root["limits"] as? [[String: Any]], !entries.isEmpty {
            return entries.enumerated().compactMap { parseLimitEntry($1, index: $0) }
        }
        return parseLegacyBuckets(root)
    }

    private static func parseLimitEntry(_ entry: [String: Any], index: Int) -> UsageLimit? {
        guard let kind = entry["kind"] as? String, let percent = entry["percent"] as? Double else {
            return nil
        }
        return UsageLimit(
            id: "\(kind)-\(index)",
            title: title(forKind: kind, scope: entry["scope"] as? [String: Any]),
            shortTitle: shortTitle(forKind: kind, scope: entry["scope"] as? [String: Any]),
            percent: percent,
            resetsAt: parseDate(entry["resets_at"])
        )
    }

    private static func title(forKind kind: String, scope: [String: Any]?) -> String {
        let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
        switch kind {
        case "session": return "Session (5 hours)"
        case "weekly_all": return "Weekly · all models"
        case "weekly_scoped": return "Weekly · \(model ?? "model")"
        default: return model.map { "\(kind) · \($0)" } ?? kind
        }
    }

    private static func shortTitle(forKind kind: String, scope: [String: Any]?) -> String {
        let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
        switch kind {
        case "session": return "5h"
        case "weekly_all": return "7d"
        case "weekly_scoped": return model ?? "7d·m"
        default: return model ?? kind
        }
    }

    private static func parseLegacyBuckets(_ root: [String: Any]) -> [UsageLimit] {
        let buckets = [("five_hour", "Session (5 hours)", "5h"), ("seven_day", "Weekly · all models", "7d")]
        return buckets.compactMap { key, title, shortTitle in
            guard let bucket = root[key] as? [String: Any], let percent = bucket["utilization"] as? Double else {
                return nil
            }
            return UsageLimit(id: key, title: title, shortTitle: shortTitle, percent: percent, resetsAt: parseDate(bucket["resets_at"]))
        }
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
