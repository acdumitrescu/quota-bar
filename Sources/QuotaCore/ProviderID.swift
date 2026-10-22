import Foundation

/// Every provider Quota knows about, with the metadata the UI and CLI need.
public enum ProviderID: String, CaseIterable, Codable, Sendable, Identifiable {
    case claudeSubscription = "claude-subscription"
    case claudeCode = "claude-code"
    case deepSeek = "deepseek"
    case openRouter = "openrouter"
    case openAI = "openai"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeSubscription: "Claude subscription"
        case .claudeCode: "Claude Code"
        case .deepSeek: "DeepSeek"
        case .openRouter: "OpenRouter"
        case .openAI: "OpenAI"
        }
    }

    public var summary: String {
        switch self {
        case .claudeSubscription:
            "Session and weekly limits for Claude Pro/Max, read with Claude Code's existing login."
        case .claudeCode:
            "Token counts from Claude Code's local transcripts. No network access."
        case .deepSeek:
            "Account balance. Usage is derived locally from balance changes."
        case .openRouter:
            "Credits used today, this week and this month, plus key limits."
        case .openAI:
            "Organization tokens and cost. Requires an Admin key from an org owner."
        }
    }

    /// True when the data comes from an endpoint that is not publicly documented.
    public var isUnofficial: Bool { self == .claudeSubscription }

    /// True when the user must paste an API key (stored in the Keychain).
    public var needsKey: Bool {
        switch self {
        case .deepSeek, .openRouter, .openAI: true
        case .claudeSubscription, .claudeCode: false
        }
    }

    public var keyPlaceholder: String {
        switch self {
        case .deepSeek: "sk-…"
        case .openRouter: "sk-or-…"
        case .openAI: "sk-admin-…"
        default: ""
        }
    }

    /// Environment variable the CLI reads before falling back to the Keychain.
    public var keyEnvironmentVariable: String {
        "QUOTA_" + rawValue.uppercased().replacingOccurrences(of: "-", with: "_") + "_KEY"
    }

    /// Hosts this provider talks to. Empty means fully offline.
    public var hosts: [String] {
        switch self {
        case .claudeSubscription: ["api.anthropic.com"]
        case .claudeCode: []
        case .deepSeek: ["api.deepseek.com"]
        case .openRouter: ["openrouter.ai"]
        case .openAI: ["api.openai.com"]
        }
    }
}
