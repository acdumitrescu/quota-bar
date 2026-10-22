import Foundation
import Testing
@testable import QuotaCore

// All fixtures below are made-up data.

private let now = Dates.parseISO("2030-03-15T12:00:00Z")!

@Suite struct DatesTests {
    @Test func parsesMicrosecondTimestamps() {
        let d = Dates.parseISO("2030-03-15T14:49:59.622218+00:00")
        #expect(d == Dates.parseISO("2030-03-15T14:49:59.622Z"))
    }

    @Test func parsesPlainTimestamps() {
        #expect(Dates.parseISO("2030-03-15T00:00:00Z") != nil)
    }
}

@Suite struct ClaudeSubscriptionTests {
    @Test func parsesLimitsArray() throws {
        let json = """
        {"limits":[
          {"kind":"session","percent":19,"resets_at":"2030-03-15T14:49:59.622218+00:00","scope":null},
          {"kind":"weekly_all","percent":7,"resets_at":"2030-03-20T13:59:59.622243+00:00","scope":null}],
         "seven_day_breakdown":{"rows":[
          {"key":"claude_code","display_name":"Claude Code","percent":30},
          {"key":"chat","display_name":"Chats","percent":70},
          {"key":"other","display_name":"Other","percent":0}]}}
        """
        let snap = try ClaudeSubscriptionProvider.parse(Data(json.utf8), plan: "pro", now: now)
        #expect(snap.meters.map(\.id) == ["claude.session", "claude.weekly_all"])
        #expect(snap.meters[0].percent == 19)
        #expect(snap.meters[0].resetsAt != nil)
        #expect(snap.breakdowns.first?.rows.map(\.label) == ["Chats", "Claude Code"])
        #expect(snap.notes == ["Pro plan"])
    }

    @Test func fallsBackToFlatWindows() throws {
        let json = """
        {"five_hour":{"utilization":55.0,"resets_at":"2030-03-15T14:00:00+00:00"},
         "seven_day":{"utilization":12.0,"resets_at":"2030-03-20T14:00:00+00:00"},
         "seven_day_opus":null}
        """
        let snap = try ClaudeSubscriptionProvider.parse(Data(json.utf8), plan: nil, now: now)
        #expect(snap.meters.map(\.percent) == [55, 12])
    }

    @Test func rejectsResponseWithoutLimits() {
        #expect(throws: ProviderError.self) {
            try ClaudeSubscriptionProvider.parse(Data("{}".utf8), plan: nil, now: now)
        }
    }

    @Test func decodesCredentialsWithoutExposingOtherFields() {
        let json = #"{"claudeAiOauth":{"accessToken":"test-token","expiresAt":1900000000000,"subscriptionType":"max"},"other":{}}"#
        let creds = ClaudeSubscriptionProvider.decodeCredentials(Data(json.utf8))
        #expect(creds?.accessToken == "test-token")
        #expect(creds?.plan == "max")
        #expect(creds?.expiresAt == Date(timeIntervalSince1970: 1_900_000_000))
    }

    @Test func expiredLoginFailsBeforeAnyRequest() async {
        let provider = ClaudeSubscriptionProvider {
            ClaudeCredentials(accessToken: "x", expiresAt: now.addingTimeInterval(-60), plan: nil)
        }
        let ctx = FetchContext(secrets: EmptySecrets(), history: nil, now: now)
        await #expect(throws: ProviderError.self) { try await provider.fetch(ctx) }
    }
}

@Suite struct ClaudeCodeLogsTests {
    @Test func parsesUsageLine() {
        let line = #"{"timestamp":"2030-03-15T10:00:00.000Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-opus-5-5","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":5}}}"#
        let parsed = LogScanner.parse(line: Data(line.utf8))
        #expect(parsed?.0 == "msg_1|req_1")
        #expect(parsed?.1.total == 1115)
        #expect(parsed?.1.output == 5)
    }

    @Test func ignoresLinesWithoutUsage() {
        #expect(LogScanner.parse(line: Data(#"{"type":"user","message":{"content":"hi"}}"#.utf8)) == nil)
        #expect(LogScanner.parse(line: Data(#"{"message":{"model":"<synthetic>","usage":{}}}"#.utf8)) == nil)
    }

    @Test func scansIncrementallyAndDedupes() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = dir.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = project.appendingPathComponent("session.jsonl")
        // Real clock here: the scanner skips files whose modification date is outside its window.
        let now = Date()
        let stamp = Dates.isoString(now.addingTimeInterval(-60))
        let line = { (id: String) in
            #"{"timestamp":"\#(stamp)","requestId":"r","message":{"id":"\#(id)","model":"claude-haiku-5-5","usage":{"input_tokens":1,"output_tokens":1}}}"# + "\n"
        }
        // Same message logged twice (one line per content block) plus a partial line still being written.
        try (line("a") + line("a") + #"{"timestamp":"#).write(to: file, atomically: true, encoding: .utf8)

        let scanner = LogScanner(roots: [dir])
        #expect(try await scanner.scan(now: now).count == 1)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        // Completes the partial line as a non-usage line, then adds a new message.
        try handle.write(contentsOf: Data(("\"x\"}\n" + line("b")).utf8))
        try handle.close()
        let entries = try await scanner.scan(now: now)
        #expect(entries.count == 2)

        let snap = ClaudeCodeLogsProvider.summarize(entries, now: now, calendar: .current)
        #expect(snap.stats.first { $0.id == "claude-code.week" }?.value == 4)
    }

    @Test func missingLogFolderIsNotConfigured() async {
        let scanner = LogScanner(roots: [URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")])
        await #expect(throws: ProviderError.self) { try await scanner.scan(now: now) }
    }
}

@Suite struct DeepSeekTests {
    @Test func prefersUSDBalance() throws {
        let json = """
        {"is_available":true,"balance_infos":[
          {"currency":"CNY","total_balance":"70.00","granted_balance":"0.00","topped_up_balance":"70.00"},
          {"currency":"USD","total_balance":"9.50","granted_balance":"0.50","topped_up_balance":"9.00"}]}
        """
        let b = try DeepSeekProvider.parseBalance(Data(json.utf8))
        #expect(b == .init(currency: "USD", total: 9.5, isAvailable: true))
    }
}

@Suite struct OpenRouterTests {
    @Test func parsesKeyUsageAndLimit() throws {
        let json = """
        {"data":{"label":"test","limit":20,"limit_remaining":15,"limit_reset":"monthly",
          "usage":42.5,"usage_daily":1.25,"usage_weekly":4,"usage_monthly":5,"is_free_tier":false,
          "free_model_daily_requests":{"used":10,"limit":50,"remaining":40}}}
        """
        let snap = try OpenRouterProvider.parse(Data(json.utf8), now: now)
        #expect(snap.stats.first { $0.id == "openrouter.usage_daily" }?.value == 1.25)
        #expect(snap.meters.first { $0.id == "openrouter.limit" }?.percent == 25)
        #expect(snap.meters.first { $0.id == "openrouter.free-daily" }?.percent == 20)
    }

    @Test func unlimitedKeyHasNoLimitMeter() throws {
        let json = #"{"data":{"limit":null,"limit_remaining":null,"usage":3,"usage_daily":0}}"#
        let snap = try OpenRouterProvider.parse(Data(json.utf8), now: now)
        #expect(snap.meters.isEmpty)
    }
}

@Suite struct OpenAITests {
    @Test func summarizesUsageAndCosts() throws {
        let today = Int(Dates.utcCalendar.startOfDay(for: now).timeIntervalSince1970)
        let yesterday = today - 86_400
        let usage = """
        {"object":"page","data":[
          {"start_time":\(yesterday),"end_time":\(today),"results":[{"model":"gpt-x","input_tokens":100,"output_tokens":50,"num_model_requests":2}]},
          {"start_time":\(today),"end_time":\(today + 86_400),"results":[{"model":"gpt-x","input_tokens":10,"output_tokens":5,"num_model_requests":1},
                                                                      {"model":"gpt-y","input_tokens":1,"output_tokens":1,"num_model_requests":1}]}],
         "has_more":false,"next_page":null}
        """
        let costs = """
        {"data":[{"start_time":\(yesterday),"results":[{"amount":{"value":0.5,"currency":"usd"}}]},
                 {"start_time":\(today),"results":[{"amount":{"value":0.25,"currency":"usd"}}]}],
         "has_more":true,"next_page":"page_2"}
        """
        let u = try OpenAIProvider.parseUsage(Data(usage.utf8))
        let c = try OpenAIProvider.parseCosts(Data(costs.utf8))
        #expect(u.next == nil)
        #expect(c.next == "page_2")

        let snap = OpenAIProvider.summarize(usage: u.rows, costs: c.rows, now: now)
        let v = { (id: String) in snap.stats.first { $0.id == id }?.value }
        #expect(v("openai.cost-today") == 0.25)
        #expect(v("openai.cost-month") == 0.75)
        #expect(v("openai.tokens-today") == 17)
        #expect(v("openai.tokens-month") == 167)
        #expect(v("openai.requests-today") == 2)
        #expect(snap.breakdowns.first?.rows.first?.label == "gpt-x")
    }
}

@Suite struct HTTPClientTests {
    @Test func blocksHostsOutsideAllowlist() async {
        await #expect(throws: ProviderError.hostNotAllowed("example.com")) {
            try await HTTPClient().get(URL(string: "https://example.com/")!, headers: [:])
        }
    }

    @Test func allowlistIsExactlyTheProviderHosts() {
        #expect(HTTPClient.allowedHosts == ["api.anthropic.com", "api.deepseek.com", "openrouter.ai", "api.openai.com"])
    }
}

struct EmptySecrets: SecretStore {
    func secret(for provider: ProviderID) -> String? { nil }
}
