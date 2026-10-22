import Foundation
import QuotaCore
import UserNotifications

/// Local notifications only (nothing leaves the Mac). Each alert fires once per limit window.
@MainActor
final class Notifier {
    private let defaults = UserDefaults.standard
    private let firedKey = "firedAlerts"
    private var authorized = false

    /// UNUserNotificationCenter crashes outside an app bundle (e.g. `swift run`).
    private var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func evaluate(_ snapshot: ProviderSnapshot, settings: AppSettings) {
        guard settings.alertsEnabled, available else { return }
        var fired = Set(defaults.stringArray(forKey: firedKey) ?? [])
        var toSend: [(String, String, String)] = []

        for m in snapshot.meters {
            let window = m.resetsAt.map { String(Int($0.timeIntervalSince1970 / 3600)) } ?? "none"
            for t in settings.alertThresholds.sorted(by: >) where m.percent >= Double(t) {
                let key = "\(m.id)|\(window)|\(t)"
                if fired.insert(key).inserted {
                    toSend.append((key, "\(snapshot.provider.displayName): \(m.label) at \(Int(m.percent))%",
                                   Format.reset(m.resetsAt) ?? m.caption ?? ""))
                }
                break // only the highest crossed threshold
            }
            // Reset alert: the window changed after we had alerted on the previous one.
            if settings.alertOnReset, m.percent < 1,
               fired.contains(where: { $0.hasPrefix("\(m.id)|") && !$0.contains("|\(window)|") }) {
                fired = fired.filter { !$0.hasPrefix("\(m.id)|") }
                toSend.append(("\(m.id)|reset|\(window)", "\(snapshot.provider.displayName): \(m.label) reset", "Back to 0%."))
            }
        }

        let day = String(Int(Date().timeIntervalSince1970 / 86_400))
        for s in snapshot.stats {
            guard let floor = settings.lowBalance[s.id], s.value < floor else { continue }
            let key = "\(s.id)|low|\(day)"
            if fired.insert(key).inserted {
                toSend.append((key, "\(snapshot.provider.displayName): low balance",
                               "\(s.label) is \(Format.value(s.value, s.unit))."))
            }
        }

        // Keep the list from growing forever.
        defaults.set(Array(fired.suffix(500)), forKey: firedKey)
        guard !toSend.isEmpty else { return }
        Task { await send(toSend) }
    }

    func requestPermission() async -> Bool {
        guard available else { return false }
        authorized = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        return authorized
    }

    func reset() { defaults.removeObject(forKey: firedKey) }

    private func send(_ items: [(String, String, String)]) async {
        if !authorized, !(await requestPermission()) { return }
        for (id, title, body) in items {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }
}
