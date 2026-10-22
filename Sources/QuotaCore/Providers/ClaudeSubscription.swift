import Foundation

public struct ClaudeCredentials: Sendable {
    public let accessToken: String
    public let expiresAt: Date?
    public let plan: String?
}

/// Claude Pro/Max limits — the same numbers as `/usage` in Claude Code.
///
/// UNOFFICIAL: `api.anthropic.com/api/oauth/usage` is not publicly documented and may change.
/// Uses Claude Code's existing login read-only: the token is never refreshed, rewritten, stored or logged.
public struct ClaudeSubscriptionProvider: UsageProvider {
    public let id = ProviderID.claudeSubscription
    private let readCredentials: @Sendable () throws -> ClaudeCredentials

    public init(readCredentials: @escaping @Sendable () throws -> ClaudeCredentials = ClaudeSubscriptionProvider.systemCredentials) {
        self.readCredentials = readCredentials
    }

    public func fetch(_ context: FetchContext) async throws -> ProviderSnapshot {
        let creds = try readCredentials()
        if let exp = creds.expiresAt, exp < context.now {
            throw ProviderError.unauthorized("Claude Code login expired. Use Claude Code once to refresh it.")
        }
        let data: Data
        do {
            data = try await context.http.get(
                URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                headers: ["Authorization": "Bearer \(creds.accessToken)", "anthropic-beta": "oauth-2025-04-20"])
        } catch ProviderError.unauthorized {
            throw ProviderError.unauthorized("Claude Code login was rejected. Use Claude Code once to refresh it.")
        }
        return try Self.parse(data, plan: creds.plan, now: context.now)
    }

    static func parse(_ data: Data, plan: String?, now: Date) throws -> ProviderSnapshot {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.badResponse("Unexpected response from Claude usage endpoint.")
        }
        var meters: [Meter] = []
        for l in obj["limits"] as? [[String: Any]] ?? [] {
            guard let kind = l["kind"] as? String, let pct = (l["percent"] as? NSNumber)?.doubleValue else { continue }
            let scope = l["scope"] as? String
            meters.append(Meter(id: "claude." + kind + (scope.map { ".\($0)" } ?? ""),
                                label: label(kind: kind, scope: scope), percent: pct,
                                resetsAt: (l["resets_at"] as? String).flatMap(Dates.parseISO)))
        }
        // Older response shape: flat windows with `utilization`.
        if meters.isEmpty {
            for (key, kind) in [("five_hour", "session"), ("seven_day", "weekly_all"),
                                ("seven_day_opus", "weekly_opus"), ("seven_day_sonnet", "weekly_sonnet")] {
                guard let w = obj[key] as? [String: Any], let pct = (w["utilization"] as? NSNumber)?.doubleValue else { continue }
                meters.append(Meter(id: "claude." + kind, label: label(kind: kind, scope: nil), percent: pct,
                                    resetsAt: (w["resets_at"] as? String).flatMap(Dates.parseISO)))
            }
        }
        guard !meters.isEmpty else {
            throw ProviderError.badResponse("Claude usage response had no limits. The format may have changed.")
        }

        let rows = ((obj["seven_day_breakdown"] as? [String: Any])?["rows"] as? [[String: Any]] ?? [])
            .compactMap { r -> Stat? in
                guard let name = r["display_name"] as? String, let pct = (r["percent"] as? NSNumber)?.doubleValue, pct > 0
                else { return nil }
                return Stat(id: "claude.breakdown.\(r["key"] as? String ?? name)", label: name, value: pct, unit: .percent)
            }
            .sorted { $0.value > $1.value }

        return ProviderSnapshot(
            provider: .claudeSubscription, fetchedAt: now, meters: meters,
            breakdowns: rows.isEmpty ? [] : [Breakdown(title: "This week by app", rows: rows)],
            notes: plan.map { ["\($0.capitalized) plan"] } ?? [])
    }

    static func label(kind: String, scope: String?) -> String {
        let base: String = switch kind {
        case "session": "Session (5 hours)"
        case "weekly_all": "Weekly · all models"
        case "weekly_opus": "Weekly · Opus"
        case "weekly_sonnet": "Weekly · Sonnet"
        default: kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return scope.map { "\(base) · \($0)" } ?? base
    }

    // MARK: Credentials

    /// macOS: the "Claude Code-credentials" Keychain item, read via /usr/bin/security (already trusted by
    /// that item, so no repeated prompts). Fallback: `~/.claude/.credentials.json` as used on other platforms.
    @Sendable public static func systemCredentials() throws -> ClaudeCredentials {
        if let data = try? securityCLI(), let creds = decodeCredentials(data) { return creds }
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: file), let creds = decodeCredentials(data) { return creds }
        throw ProviderError.notConfigured("Claude Code login not found. Install Claude Code and run `claude` to log in.")
    }

    static func decodeCredentials(_ data: Data) -> ClaudeCredentials? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        let exp = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return ClaudeCredentials(accessToken: token, expiresAt: exp, plan: oauth["subscriptionType"] as? String)
    }

    private static func securityCLI() throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ProviderError.notConfigured("No Claude Code login in Keychain.") }
        return data
    }
}
