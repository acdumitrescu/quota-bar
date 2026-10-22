import AppKit
import Combine
import SwiftUI
import QuotaCore

/// `Quota.app --demo`: made-up numbers for screenshots. No network, Keychain, history or real preferences.
enum Demo {
    static let isOn = CommandLine.arguments.contains("--demo")

    /// Throwaway preferences, wiped on every demo launch.
    static var defaults: UserDefaults { UserDefaults(suiteName: "quota.demo")! }

    static func resetDefaults() {
        defaults.removePersistentDomain(forName: "quota.demo")
        defaults.set(ProviderID.allCases.map(\.rawValue), forKey: "enabled")
        defaults.set(true, forKey: "alertsEnabled")
        defaults.set(true, forKey: "alertOnReset")
    }

    static func snapshots(now: Date = Date()) -> [ProviderID: ProviderSnapshot] {
        let usd = StatUnit.currency("USD")
        let h = 3600.0
        return [
            .claudeSubscription: ProviderSnapshot(
                provider: .claudeSubscription, fetchedAt: now,
                meters: [
                    Meter(id: "claude.session", label: "Session (5 hours)", percent: 42, resetsAt: now + 2.3 * h),
                    Meter(id: "claude.weekly_all", label: "Weekly · all models", percent: 18, resetsAt: now + 74 * h),
                ],
                breakdowns: [Breakdown(title: "This week by app", rows: [
                    Stat(id: "d.code", label: "Claude Code", value: 12, unit: .percent),
                    Stat(id: "d.chat", label: "Claude.ai", value: 6, unit: .percent),
                ])],
                notes: ["Pro plan"]),
            .claudeCode: ProviderSnapshot(
                provider: .claudeCode, fetchedAt: now,
                stats: [
                    Stat(id: "claude-code.today", label: "Today", value: 3_412_000, unit: .tokens),
                    Stat(id: "claude-code.today-output", label: "Output today", value: 48_300, unit: .tokens),
                    Stat(id: "claude-code.week", label: "Last 7 days", value: 18_950_000, unit: .tokens),
                    Stat(id: "claude-code.month", label: "Last 30 days", value: 61_200_000, unit: .tokens),
                ],
                notes: ["Tokens include cache reads and writes."]),
            .deepSeek: ProviderSnapshot(
                provider: .deepSeek, fetchedAt: now,
                stats: [
                    Stat(id: "deepseek.balance", label: "Balance", value: 8.42, unit: usd),
                    Stat(id: "deepseek.used-today", label: "Used today", value: 0.31, unit: usd),
                    Stat(id: "deepseek.used-week", label: "Used last 7 days", value: 1.87, unit: usd),
                ]),
            .openRouter: ProviderSnapshot(
                provider: .openRouter, fetchedAt: now,
                meters: [Meter(id: "openrouter.limit", label: "Key limit", percent: 27, caption: "$7.30 of $10 left")],
                stats: [
                    Stat(id: "openrouter.usage_daily", label: "Used today", value: 0.54, unit: usd),
                    Stat(id: "openrouter.usage_monthly", label: "This month", value: 2.70, unit: usd),
                ]),
            .openAI: ProviderSnapshot(
                provider: .openAI, fetchedAt: now,
                stats: [
                    Stat(id: "openai.cost-today", label: "Cost today", value: 1.12, unit: usd),
                    Stat(id: "openai.tokens-today", label: "Tokens today", value: 640_000, unit: .tokens),
                    Stat(id: "openai.requests-today", label: "Requests today", value: 212, unit: .requests),
                ],
                notes: ["Days are UTC. Costs can lag a few hours behind usage."]),
        ]
    }

    // MARK: Screenshots

    /// Set by the menu panel when it appears, so the tour can open Settings the normal way.
    @MainActor static var openSettings: (() -> Void)?
    /// Drives the Settings tab during the tour.
    @MainActor static let tab = PassthroughSubject<Int, Never>()

    /// `--demo --shots <dir>`: opens the panel, then each Settings tab, saving every visible Quota window
    /// as a PNG in `dir`, then quits. The app draws its own windows, so no Screen Recording permission is needed.
    @MainActor static func startCapturing() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--shots"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? menuBarImage()?.write(to: dir.appendingPathComponent("menubar.png"))
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                for window in NSApp.windows where window.isVisible && window.frame.width > 40 {
                    guard let name = shotName(window), let png = render(window) else { continue }
                    try? png.write(to: dir.appendingPathComponent("\(name).png"))
                }
            }
        }
        Task { @MainActor in
            func pause(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
            await pause(1.5)
            statusButton()?.performClick(nil)
            await pause(2.5)
            openSettings?()
            statusButton()?.performClick(nil)
            for i in 0..<5 {
                await pause(1.5)
                tab.send(i)
            }
            await pause(2)
            NSApp.terminate(nil)
        }
    }

    /// The status item is composited by macOS and can't be drawn in-process, so render the same label
    /// on a menu-bar-like strip instead.
    @MainActor private static func menuBarImage() -> Data? {
        let meters = snapshots()[.claudeSubscription]!.meters
        let strip = HStack(spacing: 14) {
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            MenuBarLabel(meters: meters, style: .percent, warning: false)
            Text("Thu 09:41")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 14).frame(height: 28)
        .background(Color(white: 0.16))
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: strip)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    @MainActor private static func statusButton() -> NSButton? {
        func find(_ view: NSView) -> NSButton? {
            if let b = view as? NSButton, String(describing: type(of: b)).contains("StatusBar") { return b }
            return view.subviews.lazy.compactMap(find).first
        }
        return NSApp.windows.lazy.compactMap { $0.contentView?.superview ?? $0.contentView }.compactMap(find).first
    }

    @MainActor private static func shotName(_ window: NSWindow) -> String? {
        let cls = String(describing: type(of: window))
        if cls.contains("StatusBarWindow") { return nil } // drawn by the system; see menuBarImage()
        if cls.contains("MenuBarExtra") || window.level == .popUpMenu || window.level == .statusBar { return "panel" }
        let title = window.title.lowercased().replacingOccurrences(of: " ", with: "-")
        return title.isEmpty ? nil : "settings-\(title)"
    }

    /// Draws the window (title bar included) over an opaque background, at 2x.
    @MainActor private static func render(_ window: NSWindow) -> Data? {
        guard let view = window.contentView?.superview ?? window.contentView else { return nil }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        let scale = 2.0
        let out = NSImage(size: bounds.size)
        out.addRepresentation({
            let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale),
                                     pixelsHigh: Int(bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)!
            r.size = bounds.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: r)
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                let radius: CGFloat = 10
                NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
                NSColor.windowBackgroundColor.setFill()
                bounds.fill()
                rep.draw(in: bounds)
            }
            NSGraphicsContext.restoreGraphicsState()
            return r
        }())
        return (out.representations.last as? NSBitmapImageRep)?.representation(using: .png, properties: [:])
    }

    /// Smooth made-up 7-day curves for the sparklines.
    static func sparklines(now: Date = Date()) -> [String: [History.Sample]] {
        func curve(_ base: Double, _ amp: Double, _ phase: Double) -> [History.Sample] {
            (0..<56).map { i in
                let t = Double(i)
                return History.Sample(at: now - (55 - t) * 3 * 3600,
                                      value: max(0, base + amp * sin(t / 4 + phase) + t * 0.15))
            }
        }
        return ["claude.session": curve(30, 18, 0), "claude.weekly_all": curve(8, 3, 1),
                "openrouter.limit": curve(18, 4, 2)]
    }
}
