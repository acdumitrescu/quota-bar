import Foundation
import QuotaCore

/// Non-secret preferences, stored in UserDefaults. API keys never go here (see KeychainStore).
@MainActor
final class AppSettings: ObservableObject {
    enum MenuBarStyle: String, CaseIterable, Identifiable {
        case percent, ring, iconOnly
        var id: String { rawValue }
        var title: String {
            switch self {
            case .percent: "Icon and percentage"
            case .ring: "Ring and percentage"
            case .iconOnly: "Icon only"
            }
        }
    }

    private let defaults = Demo.isOn ? Demo.defaults : UserDefaults.standard

    /// Every provider is off until the user turns it on.
    @Published var enabled: [ProviderID] { didSet { save("enabled", enabled.map(\.rawValue)) } }
    @Published var refreshMinutes: Int { didSet { save("refreshMinutes", refreshMinutes) } }
    @Published var menuBarStyle: MenuBarStyle { didSet { save("menuBarStyle", menuBarStyle.rawValue) } }
    /// Meter id shown in the menu bar; nil means "first meter of the first enabled provider".
    @Published var menuBarMeter: String? { didSet { save("menuBarMeter", menuBarMeter) } }
    @Published var showSecondMeter: Bool { didSet { save("showSecondMeter", showSecondMeter) } }

    @Published var alertsEnabled: Bool { didSet { save("alertsEnabled", alertsEnabled) } }
    @Published var alertThresholds: [Int] { didSet { save("alertThresholds", alertThresholds) } }
    @Published var alertOnReset: Bool { didSet { save("alertOnReset", alertOnReset) } }
    /// Low-balance floors keyed by stat id (e.g. "deepseek.balance").
    @Published var lowBalance: [String: Double] { didSet { save("lowBalance", lowBalance) } }
    @Published var keepHistory: Bool { didSet { save("keepHistory", keepHistory) } }

    static let refreshChoices = [1, 3, 5, 15, 30]
    static let thresholdChoices = [50, 80, 95]

    init() {
        enabled = (defaults.stringArray(forKey: "enabled") ?? []).compactMap(ProviderID.init(rawValue:))
        refreshMinutes = defaults.object(forKey: "refreshMinutes") as? Int ?? 5
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: "menuBarStyle") ?? "") ?? .percent
        menuBarMeter = defaults.string(forKey: "menuBarMeter")
        showSecondMeter = defaults.object(forKey: "showSecondMeter") as? Bool ?? true
        alertsEnabled = defaults.bool(forKey: "alertsEnabled")
        alertThresholds = defaults.array(forKey: "alertThresholds") as? [Int] ?? [80, 95]
        alertOnReset = defaults.bool(forKey: "alertOnReset")
        lowBalance = defaults.dictionary(forKey: "lowBalance") as? [String: Double] ?? [:]
        keepHistory = defaults.object(forKey: "keepHistory") as? Bool ?? true
    }

    func isEnabled(_ id: ProviderID) -> Bool { enabled.contains(id) }

    func setEnabled(_ id: ProviderID, _ on: Bool) {
        if on, !enabled.contains(id) {
            enabled.append(id)
        } else if !on {
            enabled.removeAll { $0 == id }
        }
    }

    func move(_ id: ProviderID, by offset: Int) {
        guard let i = enabled.firstIndex(of: id) else { return }
        let j = min(max(i + offset, 0), enabled.count - 1)
        enabled.swapAt(i, j)
    }

    /// Wipes every preference Quota stored (used by "Delete all data").
    func reset() {
        if let domain = Bundle.main.bundleIdentifier { defaults.removePersistentDomain(forName: domain) }
        enabled = []
        menuBarMeter = nil
        alertsEnabled = false
        lowBalance = [:]
    }

    private func save(_ key: String, _ value: Any?) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
