import Foundation

public enum Format {
    public static func value(_ value: Double, _ unit: StatUnit) -> String {
        switch unit {
        case .tokens, .requests: compact(value)
        case .percent: "\(Int(value.rounded()))%"
        case .currency(let code): money(value, code)
        }
    }

    public static func compact(_ n: Double) -> String {
        switch abs(n) {
        case 1e9...: String(format: "%.2fB", n / 1e9)
        case 1e6...: String(format: "%.1fM", n / 1e6)
        case 1e3...: String(format: "%.1fK", n / 1e3)
        default: String(Int(n))
        }
    }

    public static func money(_ v: Double, _ code: String) -> String {
        let symbol = ["USD": "$", "CNY": "¥", "EUR": "€"][code.uppercased()] ?? code.uppercased() + " "
        return symbol + String(format: abs(v) < 0.01 && v != 0 ? "%.4f" : "%.2f", v)
    }

    /// "resets in 2h 14m" within a day, otherwise "resets Mon 16:59".
    public static func reset(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let minutes = Int(date.timeIntervalSince(now) / 60)
        if minutes <= 0 { return "resetting now" }
        if minutes < 60 { return "resets in \(minutes)m" }
        if minutes < 24 * 60 { return "resets in \(minutes / 60)h \(minutes % 60)m" }
        return "resets " + date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// Replaces the home directory with "~" so paths in the UI and screenshots don't reveal the user name.
    public static func tildePath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
