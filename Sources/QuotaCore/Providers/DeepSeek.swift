import Foundation

/// DeepSeek exposes only the current balance (`GET /user/balance`).
/// Usage is derived locally: every balance drop between refreshes counts as spend; rises (top-ups) are ignored.
public struct DeepSeekProvider: UsageProvider {
    public let id = ProviderID.deepSeek

    public init() {}

    public func fetch(_ context: FetchContext) async throws -> ProviderSnapshot {
        let key = try context.requireKey(id)
        let data = try await context.http.get(URL(string: "https://api.deepseek.com/user/balance")!,
                                              headers: ["Authorization": "Bearer \(key)"])
        let balance = try Self.parseBalance(data)
        var snap = ProviderSnapshot(
            provider: id, fetchedAt: context.now,
            stats: [Stat(id: "deepseek.balance", label: "Balance", value: balance.total, unit: .currency(balance.currency))])
        if !balance.isAvailable { snap.notes.append("Balance is too low for API calls.") }

        guard let history = context.history else { return snap }
        let metric = History.key(stat: "deepseek.balance")
        await history.record(id, metric: metric, value: balance.total, at: context.now)

        let cal = Calendar.current
        let today = cal.startOfDay(for: context.now)
        let week = cal.date(byAdding: .day, value: -6, to: today)!
        let samples = await history.series(id, metric: metric, since: week)
        let before = await history.latest(id, metric: metric, before: week)
        snap.stats += [
            Stat(id: "deepseek.used-today", label: "Used today",
                 value: History.spent(samples, since: today), unit: .currency(balance.currency)),
            Stat(id: "deepseek.used-week", label: "Used last 7 days",
                 value: History.spent(samples, since: week, previous: before), unit: .currency(balance.currency)),
        ]
        if before == nil, let first = samples.first {
            snap.notes.append("Tracking since \(first.at.formatted(date: .abbreviated, time: .shortened)). DeepSeek has no usage history, so usage counts from when Quota started watching.")
        }
        return snap
    }

    struct Balance: Equatable {
        let currency: String
        let total: Double
        let isAvailable: Bool
    }

    static func parseBalance(_ data: Data) throws -> Balance {
        struct Response: Decodable {
            struct Info: Decodable { let currency: String; let total_balance: String }
            let is_available: Bool
            let balance_infos: [Info]
        }
        let body = try JSONDecoder().decode(Response.self, from: data)
        // Prefer USD when the account holds several currencies.
        guard let info = body.balance_infos.first(where: { $0.currency == "USD" }) ?? body.balance_infos.first,
              let total = Double(info.total_balance)
        else { throw ProviderError.badResponse("DeepSeek returned no balance.") }
        return Balance(currency: info.currency, total: total, isAvailable: body.is_available)
    }
}
