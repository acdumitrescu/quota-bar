import Foundation

/// OpenAI organization usage and costs. Requires an Admin key (created by an org owner); project keys are rejected.
/// Endpoints: `/v1/organization/usage/completions` and `/v1/organization/costs`. Buckets are UTC days.
public struct OpenAIProvider: UsageProvider {
    public let id = ProviderID.openAI

    public init() {}

    public func fetch(_ context: FetchContext) async throws -> ProviderSnapshot {
        let key = try context.requireKey(id)
        let utc = Dates.utcCalendar
        let monthStart = Dates.startOfMonth(context.now, calendar: utc)
        let start = String(Int(monthStart.timeIntervalSince1970))

        async let usage = pages(path: "usage/completions",
                                query: [("start_time", start), ("bucket_width", "1d"), ("limit", "31"), ("group_by", "model")],
                                key: key, http: context.http, parse: Self.parseUsage)
        async let costs = pages(path: "costs",
                                query: [("start_time", start), ("bucket_width", "1d"), ("limit", "31")],
                                key: key, http: context.http, parse: Self.parseCosts)
        return try await Self.summarize(usage: usage, costs: costs, now: context.now)
    }

    struct UsageRow: Equatable { let day: Date; let model: String?; let input: Int; let output: Int; let requests: Int }
    struct CostRow: Equatable { let day: Date; let value: Double; let currency: String }

    static func summarize(usage: [UsageRow], costs: [CostRow], now: Date) -> ProviderSnapshot {
        let today = Dates.utcCalendar.startOfDay(for: now)
        let currency = (costs.first?.currency ?? "usd").uppercased()
        let costToday = costs.filter { $0.day >= today }.reduce(0) { $0 + $1.value }
        let costMonth = costs.reduce(0) { $0 + $1.value }
        let todayRows = usage.filter { $0.day >= today }
        var byModel: [String: Int] = [:]
        for r in usage { byModel[r.model ?? "other", default: 0] += r.input + r.output }

        return ProviderSnapshot(
            provider: .openAI, fetchedAt: now,
            stats: [
                Stat(id: "openai.cost-today", label: "Cost today", value: costToday, unit: .currency(currency)),
                Stat(id: "openai.cost-month", label: "Cost this month", value: costMonth, unit: .currency(currency)),
                Stat(id: "openai.tokens-today", label: "Tokens today",
                     value: Double(todayRows.reduce(0) { $0 + $1.input + $1.output }), unit: .tokens),
                Stat(id: "openai.tokens-month", label: "Tokens this month",
                     value: Double(usage.reduce(0) { $0 + $1.input + $1.output }), unit: .tokens),
                Stat(id: "openai.requests-today", label: "Requests today",
                     value: Double(todayRows.reduce(0) { $0 + $1.requests }), unit: .requests),
            ],
            breakdowns: byModel.isEmpty ? [] : [Breakdown(
                title: "This month by model",
                rows: byModel.sorted { $0.value > $1.value }.map {
                    Stat(id: "openai.model.\($0.key)", label: $0.key, value: Double($0.value), unit: .tokens)
                })],
            notes: ["Days are UTC. Costs can lag a few hours behind usage."])
    }

    // MARK: Wire format

    static func parseUsage(_ data: Data) throws -> (rows: [UsageRow], next: String?) {
        let (buckets, next) = try buckets(data)
        let rows = buckets.flatMap { day, results in
            results.map { r in
                UsageRow(day: day, model: r["model"] as? String,
                         input: (r["input_tokens"] as? NSNumber)?.intValue ?? 0,
                         output: (r["output_tokens"] as? NSNumber)?.intValue ?? 0,
                         requests: (r["num_model_requests"] as? NSNumber)?.intValue ?? 0)
            }
        }
        return (rows, next)
    }

    static func parseCosts(_ data: Data) throws -> (rows: [CostRow], next: String?) {
        let (buckets, next) = try buckets(data)
        let rows = buckets.flatMap { day, results in
            results.compactMap { r -> CostRow? in
                guard let amount = r["amount"] as? [String: Any],
                      let value = (amount["value"] as? NSNumber)?.doubleValue else { return nil }
                return CostRow(day: day, value: value, currency: amount["currency"] as? String ?? "usd")
            }
        }
        return (rows, next)
    }

    private static func buckets(_ data: Data) throws -> ([(Date, [[String: Any]])], String?) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["data"] as? [[String: Any]]
        else { throw ProviderError.badResponse("Unexpected response from OpenAI.") }
        let buckets = list.compactMap { b -> (Date, [[String: Any]])? in
            guard let start = (b["start_time"] as? NSNumber)?.doubleValue else { return nil }
            return (Date(timeIntervalSince1970: start), b["results"] as? [[String: Any]] ?? [])
        }
        let hasMore = root["has_more"] as? Bool ?? true
        let next = hasMore ? root["next_page"] as? String : nil
        return (buckets, next?.isEmpty == false ? next : nil)
    }

    private func pages<Row: Sendable>(path: String, query: [(String, String)], key: String, http: HTTPClient,
                                      parse: (Data) throws -> (rows: [Row], next: String?)) async throws -> [Row] {
        var all: [Row] = []
        var page: String?
        var guardCount = 0
        repeat {
            var comps = URLComponents(string: "https://api.openai.com/v1/organization/\(path)")!
            comps.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
                + (page.map { [URLQueryItem(name: "page", value: $0)] } ?? [])
            let data = try await http.get(comps.url!, headers: ["Authorization": "Bearer \(key)"])
            let parsed = try parse(data)
            all += parsed.rows
            page = parsed.next
            guardCount += 1
        } while page != nil && guardCount < 10
        return all
    }
}
