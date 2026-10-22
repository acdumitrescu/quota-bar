import Foundation
import SQLite3

/// Local time series of meter and stat values, in a single SQLite file the user can export or delete.
public actor History {
    public struct Sample: Sendable, Hashable {
        public let at: Date
        public let value: Double

        public init(at: Date, value: Double) {
            self.at = at
            self.value = value
        }
    }

    public static let retentionDays = 35
    /// An unchanged value is stored at most this often, so sparklines stay smooth without bloating the file.
    static let unchangedInterval: TimeInterval = 15 * 60

    public nonisolated let url: URL
    // Only touched from actor-isolated methods and deinit.
    private nonisolated(unsafe) var db: OpaquePointer?

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quota", isDirectory: true)
            .appendingPathComponent("history.sqlite")
    }

    public init(url: URL = History.defaultURL) throws {
        self.url = url
        // Owner-only permissions: other local users can't read the folder or the database.
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            throw ProviderError.badResponse("Couldn't open history database.")
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        db = handle
        sqlite3_exec(handle, """
            CREATE TABLE IF NOT EXISTS samples (
                provider TEXT NOT NULL, metric TEXT NOT NULL, ts REAL NOT NULL, value REAL NOT NULL);
            CREATE INDEX IF NOT EXISTS samples_lookup ON samples(provider, metric, ts);
            """, nil, nil, nil)
    }

    deinit { sqlite3_close(db) }

    // MARK: Writing

    public func record(_ provider: ProviderID, metric: String, value: Double, at date: Date) {
        if let last = latest(provider, metric: metric),
           last.value == value, date.timeIntervalSince(last.at) < Self.unchangedInterval {
            return
        }
        run("INSERT INTO samples (provider, metric, ts, value) VALUES (?, ?, ?, ?)",
            [.text(provider.rawValue), .text(metric), .real(date.timeIntervalSince1970), .real(value)])
    }

    /// Stores every meter and stat of a snapshot and prunes old rows.
    public func record(_ snapshot: ProviderSnapshot) {
        for m in snapshot.meters {
            record(snapshot.provider, metric: Self.key(meter: m.id), value: m.percent, at: snapshot.fetchedAt)
        }
        for s in snapshot.stats {
            record(snapshot.provider, metric: Self.key(stat: s.id), value: s.value, at: snapshot.fetchedAt)
        }
        let cutoff = snapshot.fetchedAt.addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        run("DELETE FROM samples WHERE ts < ?", [.real(cutoff.timeIntervalSince1970)])
    }

    public func deleteAll() {
        run("DELETE FROM samples", [])
        sqlite3_exec(db, "VACUUM", nil, nil, nil)
    }

    // MARK: Reading

    public func series(_ provider: ProviderID, metric: String, since: Date) -> [Sample] {
        query("SELECT ts, value FROM samples WHERE provider = ? AND metric = ? AND ts >= ? ORDER BY ts",
              [.text(provider.rawValue), .text(metric), .real(since.timeIntervalSince1970)])
    }

    public func latest(_ provider: ProviderID, metric: String, before: Date = .distantFuture) -> Sample? {
        query("SELECT ts, value FROM samples WHERE provider = ? AND metric = ? AND ts < ? ORDER BY ts DESC LIMIT 1",
              [.text(provider.rawValue), .text(metric), .real(before.timeIntervalSince1970)]).first
    }

    public func exportCSV() -> String {
        var out = "provider,metric,timestamp,value\n"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT provider, metric, ts, value FROM samples ORDER BY ts", -1, &stmt, nil) == SQLITE_OK
        else { return out }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let provider = String(cString: sqlite3_column_text(stmt, 0))
            let metric = String(cString: sqlite3_column_text(stmt, 1))
            let ts = Dates.isoString(Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)))
            out += "\(provider),\(Self.csvField(metric)),\(ts),\(sqlite3_column_double(stmt, 3))\n"
        }
        return out
    }

    /// Metric names can contain text from provider responses: quote them, and defuse leading
    /// `= + - @` so a spreadsheet doesn't run them as formulas.
    static func csvField(_ s: String) -> String {
        var s = s.replacingOccurrences(of: "\"", with: "\"\"")
        if let c = s.first, "=+-@\t\r".contains(c) { s = "'" + s }
        return "\"\(s)\""
    }

    public static func key(meter id: String) -> String { "meter.\(id)" }
    public static func key(stat id: String) -> String { "stat.\(id)" }

    // MARK: Derived

    /// Total of balance *drops* after `since`, measured from the last sample before it.
    /// Rises (top-ups, grants) are ignored.
    public static func spent(_ samples: [Sample], since: Date, previous: Sample? = nil) -> Double {
        var prev = previous?.value ?? samples.last { $0.at < since }?.value
        var total = 0.0
        for s in samples where s.at >= since {
            if let p = prev, s.value < p { total += p - s.value }
            prev = s.value
        }
        return total
    }

    // MARK: SQLite plumbing

    private enum Param { case text(String), real(Double) }

    private func bind(_ stmt: OpaquePointer?, _ params: [Param]) {
        // SQLITE_TRANSIENT: SQLite copies the string before the Swift buffer goes away.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, p) in params.enumerated() {
            switch p {
            case .text(let s): sqlite3_bind_text(stmt, Int32(i + 1), s, -1, transient)
            case .real(let d): sqlite3_bind_double(stmt, Int32(i + 1), d)
            }
        }
    }

    private func run(_ sql: String, _ params: [Param]) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, params)
        sqlite3_step(stmt)
    }

    private func query(_ sql: String, _ params: [Param]) -> [Sample] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, params)
        var out: [Sample] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(Sample(at: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)),
                              value: sqlite3_column_double(stmt, 1)))
        }
        return out
    }
}
