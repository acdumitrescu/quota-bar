import Foundation

enum Dates {
    /// RFC 3339 with or without fractional seconds. Microsecond precision
    /// ("…59.622218+00:00") isn't accepted by ISO8601DateFormatter, so it is trimmed to milliseconds.
    static func parseISO(_ string: String) -> Date? {
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = frac.date(from: string) { return date }

        if let dot = string.firstIndex(of: "."),
           let zone = string[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let digits = string[string.index(after: dot)..<zone].prefix(3)
            if let date = frac.date(from: String(string[..<dot]) + "." + digits + String(string[zone...])) {
                return date
            }
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    static func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }
}
