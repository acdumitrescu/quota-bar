import Foundation

public enum StatUnit: Sendable, Hashable {
    case tokens
    case requests
    case percent
    case currency(String)
}

/// A limit that fills up and resets (e.g. "Session 42%, resets in 2h").
public struct Meter: Sendable, Identifiable, Hashable {
    public let id: String
    public let label: String
    public let percent: Double
    public let resetsAt: Date?
    public let caption: String?

    public init(id: String, label: String, percent: Double, resetsAt: Date? = nil, caption: String? = nil) {
        self.id = id
        self.label = label
        self.percent = percent
        self.resetsAt = resetsAt
        self.caption = caption
    }
}

/// A single number (tokens today, balance, cost this month…).
public struct Stat: Sendable, Identifiable, Hashable {
    public let id: String
    public let label: String
    public let value: Double
    public let unit: StatUnit

    public init(id: String, label: String, value: Double, unit: StatUnit) {
        self.id = id
        self.label = label
        self.value = value
        self.unit = unit
    }
}

/// A titled list of rows, e.g. tokens by model.
public struct Breakdown: Sendable, Hashable {
    public let title: String
    public let rows: [Stat]

    public init(title: String, rows: [Stat]) {
        self.title = title
        self.rows = rows
    }
}

public struct ProviderSnapshot: Sendable {
    public let provider: ProviderID
    public let fetchedAt: Date
    public var meters: [Meter]
    public var stats: [Stat]
    public var breakdowns: [Breakdown]
    public var notes: [String]

    public init(provider: ProviderID, fetchedAt: Date, meters: [Meter] = [], stats: [Stat] = [],
                breakdowns: [Breakdown] = [], notes: [String] = []) {
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.meters = meters
        self.stats = stats
        self.breakdowns = breakdowns
        self.notes = notes
    }
}

public enum ProviderError: LocalizedError, Sendable, Equatable {
    case notConfigured(String)
    case unauthorized(String)
    case http(Int)
    case hostNotAllowed(String)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let m), .unauthorized(let m), .badResponse(let m): m
        case .http(429): "Rate limited by the provider (HTTP 429). Quota will try again on the next refresh."
        case .http(let code): "Request failed (HTTP \(code))."
        case .hostNotAllowed(let host): "Blocked request to \(host): host is not on Quota's allowlist."
        }
    }
}
