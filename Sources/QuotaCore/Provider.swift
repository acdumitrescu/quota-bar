import Foundation

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetch(_ context: FetchContext) async throws -> ProviderSnapshot
}

public protocol SecretStore: Sendable {
    func secret(for provider: ProviderID) -> String?
}

public struct FetchContext: Sendable {
    public let http: HTTPClient
    public let secrets: any SecretStore
    /// Local history; nil when running without persistence (e.g. the CLI).
    public let history: History?
    public let now: Date

    public init(http: HTTPClient = HTTPClient(), secrets: any SecretStore, history: History?, now: Date = Date()) {
        self.http = http
        self.secrets = secrets
        self.history = history
        self.now = now
    }

    func requireKey(_ provider: ProviderID) throws -> String {
        guard let key = secrets.secret(for: provider), !key.isEmpty else {
            throw ProviderError.notConfigured(
                "No \(provider.displayName) API key. Add one in Settings, or set \(provider.keyEnvironmentVariable) for the CLI.")
        }
        return key
    }
}

/// One long-lived instance of each provider (some keep state between refreshes).
public struct ProviderRegistry: Sendable {
    public let providers: [ProviderID: any UsageProvider]

    public init(providers: [any UsageProvider] = ProviderRegistry.defaults()) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    }

    public static func defaults() -> [any UsageProvider] {
        [ClaudeSubscriptionProvider(), ClaudeCodeLogsProvider(), DeepSeekProvider(),
         OpenRouterProvider(), OpenAIProvider()]
    }

    public subscript(id: ProviderID) -> (any UsageProvider)? { providers[id] }
}
