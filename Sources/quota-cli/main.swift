import Foundation
import QuotaCore

let usage = """
usage: quota [provider ...] [--json]

Prints current usage for each provider. With no arguments, shows the offline
Claude Code logs, the Claude subscription, and every provider with a key.

providers: \(ProviderID.allCases.map(\.rawValue).joined(separator: ", "))
keys:      read from QUOTA_<PROVIDER>_KEY (e.g. QUOTA_OPENROUTER_KEY), else the Keychain
"""

let args = CommandLine.arguments.dropFirst()
if args.contains("-h") || args.contains("--help") { print(usage); exit(0) }
let json = args.contains("--json")
let secrets = EnvironmentOrKeychainStore()

var selected: [ProviderID] = []
for arg in args where !arg.hasPrefix("-") {
    guard let id = ProviderID(rawValue: arg) else {
        FileHandle.standardError.write(Data("unknown provider: \(arg)\n\n\(usage)\n".utf8))
        exit(2)
    }
    selected.append(id)
}
if selected.isEmpty {
    selected = ProviderID.allCases.filter { !$0.needsKey || secrets.secret(for: $0) != nil }
}

let registry = ProviderRegistry()
let context = FetchContext(secrets: secrets, history: nil)
var output: [[String: Any]] = []

for id in selected {
    guard let provider = registry[id] else { continue }
    do {
        let snap = try await provider.fetch(context)
        if json {
            output.append([
                "provider": id.rawValue,
                "meters": snap.meters.map { m -> [String: Any] in
                    var o: [String: Any] = ["id": m.id, "label": m.label, "percent": m.percent]
                    if let r = m.resetsAt { o["resets_at"] = ISO8601DateFormatter().string(from: r) }
                    return o
                },
                "stats": snap.stats.map { ["id": $0.id, "label": $0.label, "value": $0.value] },
            ])
        } else {
            print("\(id.displayName)\(id.isUnofficial ? " (unofficial)" : "")")
            for m in snap.meters {
                print("  \(m.label): \(Format.value(m.percent, .percent))  \(Format.reset(m.resetsAt) ?? m.caption ?? "")")
            }
            for s in snap.stats { print("  \(s.label): \(Format.value(s.value, s.unit))") }
            for b in snap.breakdowns {
                print("  \(b.title):")
                for r in b.rows.prefix(5) { print("    \(r.label): \(Format.value(r.value, r.unit))") }
            }
            for n in snap.notes { print("  · \(n)") }
        }
    } catch {
        if json {
            output.append(["provider": id.rawValue, "error": error.localizedDescription])
        } else {
            print("\(id.displayName)\n  error: \(error.localizedDescription)")
        }
    }
}

if json, let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]) {
    print(String(decoding: data, as: UTF8.self))
}
