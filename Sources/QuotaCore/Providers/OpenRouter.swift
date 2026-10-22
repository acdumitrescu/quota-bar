import Foundation

/// OpenRouter key usage via the documented `GET /api/v1/key`. Amounts are credits (1 credit = 1 USD); windows are UTC.
public struct OpenRouterProvider: UsageProvider {
    public let id = ProviderID.openRouter

    public init() {}

    public func fetch(_ context: FetchContext) async throws -> ProviderSnapshot {
        let key = try context.requireKey(id)
        let data = try await context.http.get(URL(string: "https://openrouter.ai/api/v1/key")!,
                                              headers: ["Authorization": "Bearer \(key)"])
        return try Self.parse(data, now: context.now)
    }

    static func parse(_ data: Data, now: Date) throws -> ProviderSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = root["data"] as? [String: Any]
        else { throw ProviderError.badResponse("Unexpected response from OpenRouter.") }
        let num = { (k: String) in (d[k] as? NSNumber)?.doubleValue }
        let usd = StatUnit.currency("USD")

        var stats: [Stat] = []
        for (key, label) in [("usage_daily", "Used today"), ("usage_weekly", "This week"),
                             ("usage_monthly", "This month"), ("usage", "All time")] {
            if let v = num(key) { stats.append(Stat(id: "openrouter.\(key)", label: label, value: v, unit: usd)) }
        }
        if let remaining = num("limit_remaining") {
            stats.append(Stat(id: "openrouter.limit_remaining", label: "Limit remaining", value: remaining, unit: usd))
        }

        var meters: [Meter] = []
        if let limit = num("limit"), limit > 0, let remaining = num("limit_remaining") {
            let reset = (d["limit_reset"] as? String).map { "Resets \($0)" }
            meters.append(Meter(id: "openrouter.limit", label: "Key limit",
                                percent: max(0, (limit - remaining) / limit * 100), caption: reset ?? "Never resets"))
        }
        if let free = d["free_model_daily_requests"] as? [String: Any],
           let used = (free["used"] as? NSNumber)?.doubleValue, let cap = (free["limit"] as? NSNumber)?.doubleValue, cap > 0 {
            meters.append(Meter(id: "openrouter.free-daily", label: "Free-model requests today",
                                percent: used / cap * 100, resetsAt: Dates.utcCalendar.startOfDay(for: now).addingTimeInterval(86_400),
                                caption: "\(Int(used)) of \(Int(cap))"))
        }

        var notes: [String] = []
        if let label = d["label"] as? String, !label.isEmpty { notes.append("Key: \(label)") }
        if d["is_free_tier"] as? Bool == true { notes.append("Free tier") }
        return ProviderSnapshot(provider: .openRouter, fetchedAt: now, meters: meters, stats: stats, notes: notes)
    }
}
