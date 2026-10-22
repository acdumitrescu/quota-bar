import AppKit
import QuotaCore
import SwiftUI

@main
struct QuotaApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var model: AppModel

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: AppModel(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environmentObject(model)
                .environmentObject(settings)
        } label: {
            MenuBarLabel(meters: model.primaryMeters, style: settings.menuBarStyle, warning: model.hasErrors)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(settings)
        }
    }
}

struct MenuBarLabel: View {
    let meters: [Meter]
    let style: AppSettings.MenuBarStyle
    let warning: Bool

    var body: some View {
        let text = meters.map { "\(Int($0.percent.rounded()))%" }.joined(separator: " · ")
        switch style {
        case .iconOnly:
            Image(systemName: warning ? "gauge.with.dots.needle.67percent" : "gauge.with.dots.needle.33percent")
        case .ring:
            HStack(spacing: 4) {
                Image(nsImage: Self.ring(meters.first?.percent ?? 0))
                if !text.isEmpty { Text(text).monospacedDigit() }
            }
        case .percent:
            HStack(spacing: 3) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                Text(text.isEmpty ? "–" : text).monospacedDigit()
            }
        }
    }

    /// Menu bar labels only render Image and Text, so the ring is drawn into a template image.
    static func ring(_ percent: Double) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 2, dy: 2)
            let track = NSBezierPath(ovalIn: inset)
            track.lineWidth = 2
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()
            let fraction = min(max(percent / 100, 0), 1)
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: inset.width / 2,
                          startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
            arc.lineWidth = 2
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
