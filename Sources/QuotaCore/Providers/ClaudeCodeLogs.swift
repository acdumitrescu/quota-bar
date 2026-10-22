import Foundation

/// Token counts from Claude Code's local transcripts (`<config>/projects/**/*.jsonl`). Never touches the network.
public struct ClaudeCodeLogsProvider: UsageProvider {
    public let id = ProviderID.claudeCode
    private let scanner: LogScanner

    public init(roots: [URL] = ClaudeCodeLogsProvider.defaultRoots()) {
        scanner = LogScanner(roots: roots)
    }

    /// Honors CLAUDE_CONFIG_DIR (comma-separated) like Claude Code itself, else ~/.claude.
    public static func defaultRoots() -> [URL] {
        let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? ""
        let dirs = env.split(separator: ",").map { URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces)) }
        let bases = dirs.isEmpty ? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")] : dirs
        return bases.map { $0.appendingPathComponent("projects", isDirectory: true) }
    }

    public func fetch(_ context: FetchContext) async throws -> ProviderSnapshot {
        let entries = try await scanner.scan(now: context.now)
        return Self.summarize(entries, now: context.now, calendar: .current)
    }

    static func summarize(_ entries: [LogScanner.Entry], now: Date, calendar: Calendar) -> ProviderSnapshot {
        let today = calendar.startOfDay(for: now)
        let week = calendar.date(byAdding: .day, value: -6, to: today)!
        let month = calendar.date(byAdding: .day, value: -29, to: today)!

        var todayTotal = 0, todayOutput = 0, weekTotal = 0, monthTotal = 0
        var byModel: [String: Int] = [:]
        for e in entries where e.at >= month {
            monthTotal += e.total
            if e.at >= week { weekTotal += e.total; byModel[e.model, default: 0] += e.total }
            if e.at >= today { todayTotal += e.total; todayOutput += e.output }
        }
        let rows = byModel.sorted { $0.value > $1.value }.map {
            Stat(id: "claude-code.model.\($0.key)", label: $0.key.replacingOccurrences(of: "claude-", with: ""),
                 value: Double($0.value), unit: .tokens)
        }
        return ProviderSnapshot(
            provider: .claudeCode, fetchedAt: now,
            stats: [
                Stat(id: "claude-code.today", label: "Today", value: Double(todayTotal), unit: .tokens),
                Stat(id: "claude-code.today-output", label: "Output today", value: Double(todayOutput), unit: .tokens),
                Stat(id: "claude-code.week", label: "Last 7 days", value: Double(weekTotal), unit: .tokens),
                Stat(id: "claude-code.month", label: "Last 30 days", value: Double(monthTotal), unit: .tokens),
            ],
            breakdowns: rows.isEmpty ? [] : [Breakdown(title: "Last 7 days by model", rows: rows)],
            notes: ["Tokens include cache reads and writes."])
    }
}

/// Incremental transcript reader: remembers how far each file was read and only parses new lines.
public actor LogScanner {
    public struct Entry: Sendable, Equatable {
        public let at: Date
        public let model: String
        public let total: Int
        public let output: Int
    }

    static let windowDays = 30

    private let roots: [URL]
    private var offsets: [URL: UInt64] = [:]
    /// Keyed by message id + request id: one API response is logged once per content block.
    private var entries: [String: Entry] = [:]

    init(roots: [URL]) {
        self.roots = roots
    }

    func scan(now: Date) throws -> [Entry] {
        let existing = roots.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else {
            throw ProviderError.notConfigured("No Claude Code logs found in \(roots.map(Format.tildePath).joined(separator: ", ")).")
        }
        let cutoff = now.addingTimeInterval(-Double(Self.windowDays) * 86_400)
        for file in existing.flatMap({ Self.transcripts(in: $0, modifiedSince: cutoff) }) {
            readNewLines(file)
        }
        entries = entries.filter { $0.value.at >= cutoff }
        return Array(entries.values)
    }

    private func readNewLines(_ file: URL) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        var start = offsets[file] ?? 0
        if size < start { start = 0 } // file was truncated or replaced
        guard size > start else { return }
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(),
              let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return }

        // Only consume complete lines; a partially written last line is picked up next time.
        let complete = data[data.startIndex...lastNewline]
        for line in complete.split(separator: UInt8(ascii: "\n")) {
            if let (key, entry) = Self.parse(line: Data(line)) { entries[key] = entry }
        }
        offsets[file] = start + UInt64(complete.count)
    }

    static func parse(line: Data) -> (String, Entry)? {
        // Cheap pre-filter before JSON parsing: most lines carry no usage.
        guard line.range(of: Data("\"usage\"".utf8)) != nil,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any],
              let model = msg["model"] as? String, model.hasPrefix("claude"),
              let at = (obj["timestamp"] as? String).flatMap(Dates.parseISO)
        else { return nil }

        let int = { (k: String) in (usage[k] as? NSNumber)?.intValue ?? 0 }
        let output = int("output_tokens")
        let total = int("input_tokens") + int("cache_creation_input_tokens") + int("cache_read_input_tokens") + output
        let key = (msg["id"] as? String ?? UUID().uuidString) + "|" + (obj["requestId"] as? String ?? "")
        return (key, Entry(at: at, model: model, total: total, output: output))
    }

    private static func transcripts(in root: URL, modifiedSince cutoff: Date) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        var out: [URL] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true, (values?.contentModificationDate ?? .distantPast) >= cutoff {
                out.append(url)
            }
        }
        return out
    }
}
