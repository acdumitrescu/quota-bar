import Foundation
import QuotaCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    struct ProviderState {
        var snapshot: ProviderSnapshot?
        var error: String?
        var updatedAt: Date?
    }

    @Published private(set) var states: [ProviderID: ProviderState] = [:]
    /// 7-day series per meter id, for sparklines.
    @Published private(set) var sparklines: [String: [History.Sample]] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var keyStatus: [ProviderID: Bool] = [:]
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var message: String?

    let settings: AppSettings
    let keychain = KeychainStore()
    let history: History?
    private let registry = ProviderRegistry()
    private let notifier = Notifier()
    private var loop: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
        if Demo.isOn {
            history = nil
            states = Demo.snapshots().mapValues { ProviderState(snapshot: $0, updatedAt: Date()) }
            sparklines = Demo.sparklines()
            keyStatus = Dictionary(uniqueKeysWithValues: ProviderID.allCases.filter(\.needsKey).map { ($0, true) })
            lastRefresh = Date()
            Demo.startCapturing()
            return
        }
        history = try? History()
        reloadKeyStatus()
        startLoop()
    }

    // MARK: Refresh

    func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let minutes = max(1, self?.settings.refreshMinutes ?? 5)
                try? await Task.sleep(for: .seconds(minutes * 60))
            }
        }
    }

    func refresh() async {
        guard !isRefreshing, !Demo.isOn else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let enabled = settings.enabled
        let context = FetchContext(secrets: keychain, history: settings.keepHistory ? history : nil)
        let providers = enabled.compactMap { registry[$0] }

        let results = await withTaskGroup(of: (ProviderID, ProviderSnapshot?, String?).self) { group in
            for provider in providers {
                group.addTask {
                    do { return (provider.id, try await provider.fetch(context), nil) }
                    catch { return (provider.id, nil, error.localizedDescription) }
                }
            }
            var out: [(ProviderID, ProviderSnapshot?, String?)] = []
            for await r in group { out.append(r) }
            return out
        }

        let now = Date()
        for (id, snapshot, error) in results {
            var state = states[id] ?? ProviderState()
            if let snapshot { state.snapshot = snapshot }
            state.error = error
            state.updatedAt = now
            states[id] = state
            if let snapshot {
                if settings.keepHistory { await history?.record(snapshot) }
                notifier.evaluate(snapshot, settings: settings)
            }
        }
        // Drop providers that were turned off.
        states = states.filter { enabled.contains($0.key) }
        lastRefresh = now
        await loadSparklines()
    }

    private func loadSparklines() async {
        guard settings.keepHistory, let history else { sparklines = [:]; return }
        let since = Date().addingTimeInterval(-7 * 86_400)
        var out: [String: [History.Sample]] = [:]
        for (id, state) in states {
            for m in state.snapshot?.meters ?? [] {
                out[m.id] = await history.series(id, metric: History.key(meter: m.id), since: since)
            }
        }
        sparklines = out
    }

    // MARK: Menu bar

    var allMeters: [Meter] {
        settings.enabled.flatMap { states[$0]?.snapshot?.meters ?? [] }
    }

    var primaryMeters: [Meter] {
        let meters = allMeters
        guard !meters.isEmpty else { return [] }
        let first = meters.first { $0.id == settings.menuBarMeter } ?? meters[0]
        guard settings.showSecondMeter else { return [first] }
        // Pair the session meter with the weekly one from the same provider when available.
        let second = meters.first { $0.id != first.id && $0.id.hasPrefix(first.id.split(separator: ".").first.map(String.init) ?? "") }
        return [first] + (second.map { [$0] } ?? [])
    }

    var hasErrors: Bool { states.values.contains { $0.error != nil } }

    // MARK: Keys

    func reloadKeyStatus() {
        keyStatus = Dictionary(uniqueKeysWithValues: ProviderID.allCases.filter(\.needsKey).map { ($0, keychain.hasSecret(for: $0)) })
    }

    func saveKey(_ key: String, for id: ProviderID) {
        guard !Demo.isOn else { return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        keychain.setSecret(trimmed.isEmpty ? nil : trimmed, for: id)
        reloadKeyStatus()
        Task { await refresh() }
    }

    // MARK: Data controls

    func exportCSV() async -> String { await history?.exportCSV() ?? "" }

    func deleteAllData() async {
        guard !Demo.isOn else { return }
        await history?.deleteAll()
        keychain.removeAll()
        settings.reset()
        notifier.reset()
        states = [:]
        sparklines = [:]
        reloadKeyStatus()
    }

    func setLaunchAtLogin(_ on: Bool) {
        guard !Demo.isOn else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            message = "Launch at login failed: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
