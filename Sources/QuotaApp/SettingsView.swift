import AppKit
import QuotaCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            ProvidersTab().tabItem { Label("Providers", systemImage: "square.stack.3d.up") }
            DisplayTab().tabItem { Label("Display", systemImage: "menubar.rectangle") }
            AlertsTab().tabItem { Label("Alerts", systemImage: "bell") }
            PrivacyTab().tabItem { Label("Privacy", systemImage: "lock.shield") }
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 460)
    }
}

// MARK: - Providers

struct ProvidersTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            ForEach(ProviderID.allCases) { ProviderRow(id: $0) }
            if settings.enabled.count > 1 {
                Section("Order in the menu") {
                    ForEach(settings.enabled) { id in
                        HStack {
                            Text(id.displayName)
                            Spacer()
                            Button { settings.move(id, by: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(id == settings.enabled.first)
                                .accessibilityLabel("Move \(id.displayName) up")
                            Button { settings.move(id, by: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(id == settings.enabled.last)
                                .accessibilityLabel("Move \(id.displayName) down")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ProviderRow: View {
    let id: ProviderID
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var model: AppModel
    @State private var draft = ""

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { settings.isEnabled(id) }, set: { on in
                settings.setEnabled(id, on)
                Task { await model.refresh() }
            })) {
                HStack(spacing: 6) {
                    Text(id.displayName)
                    if id.isUnofficial { Badge(text: "Unofficial") }
                }
            }
            Text(id.summary).font(.caption).foregroundStyle(.secondary)
            if id.isUnofficial {
                Text("Uses an endpoint that isn't publicly documented and may stop working. Reads Claude Code's login read-only; it's never copied or refreshed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if id.needsKey {
                HStack {
                    SecureField(model.keyStatus[id] == true ? "Saved in Keychain" : id.keyPlaceholder, text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                    Button("Save") { model.saveKey(draft, for: id); draft = "" }
                        .disabled(draft.isEmpty)
                    if model.keyStatus[id] == true {
                        Button("Remove", role: .destructive) { model.saveKey("", for: id) }
                    }
                }
            }
            Text(id.hosts.isEmpty ? "Network: none" : "Network: \(id.hosts.joined(separator: ", "))")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Display

struct DisplayTab: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Picker("Menu bar", selection: $settings.menuBarStyle) {
                ForEach(AppSettings.MenuBarStyle.allCases) { Text($0.title).tag($0) }
            }
            Picker("Main meter", selection: $settings.menuBarMeter) {
                Text("Automatic").tag(String?.none)
                ForEach(model.allMeters) { Text($0.label).tag(String?.some($0.id)) }
            }
            Toggle("Also show the paired meter (e.g. weekly next to session)", isOn: $settings.showSecondMeter)
            Picker("Refresh every", selection: $settings.refreshMinutes) {
                ForEach(AppSettings.refreshChoices, id: \.self) { Text("\($0) min").tag($0) }
            }
            .onChange(of: settings.refreshMinutes) { model.startLoop() }
            Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Alerts

struct AlertsTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Show notifications", isOn: $settings.alertsEnabled)
            Section("When a limit reaches") {
                ForEach(AppSettings.thresholdChoices, id: \.self) { t in
                    Toggle("\(t)%", isOn: Binding(
                        get: { settings.alertThresholds.contains(t) },
                        set: { on in
                            settings.alertThresholds = on ? (settings.alertThresholds + [t]).sorted()
                                                          : settings.alertThresholds.filter { $0 != t }
                        }))
                }
                Toggle("When a limit resets", isOn: $settings.alertOnReset)
            }
            .disabled(!settings.alertsEnabled)
            Section("Low balance") {
                LowBalanceField(statID: "deepseek.balance", label: "DeepSeek below")
                LowBalanceField(statID: "openrouter.limit_remaining", label: "OpenRouter limit below")
            }
            .disabled(!settings.alertsEnabled)
            Text("Notifications are generated on this Mac. Nothing is sent anywhere.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct LowBalanceField: View {
    let statID: String
    let label: String
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TextField(label, value: Binding(
            get: { settings.lowBalance[statID] },
            set: { settings.lowBalance[statID] = $0 }), format: .number, prompt: Text("off"))
    }
}

// MARK: - Privacy

struct PrivacyTab: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var model: AppModel
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                Label("No accounts, analytics, telemetry or crash reporting.", systemImage: "eye.slash")
                Label("API keys are stored only in your Keychain (this Mac only, never iCloud).", systemImage: "key")
                Label("Quota only contacts the providers you turn on:", systemImage: "network")
                Text(enabledHosts).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Section("History") {
                Toggle("Keep local history for sparklines and DeepSeek usage", isOn: $settings.keepHistory)
                LabeledContent("Stored at") {
                    Text(model.history.map { Format.tildePath($0.url) } ?? "unavailable")
                        .font(.caption.monospaced()).textSelection(.enabled)
                }
                HStack {
                    Button("Show in Finder") {
                        if let url = model.history?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    Button("Export CSV…") { export() }
                }
            }
            Section {
                Button("Delete all Quota data…", role: .destructive) { confirmDelete = true }
                Text("Removes history, saved API keys and preferences. Claude Code's own login is not touched.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all Quota data?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await model.deleteAllData() } }
        } message: {
            Text("History, API keys in Keychain and preferences will be removed. This can't be undone.")
        }
    }

    private var enabledHosts: String {
        let hosts = settings.enabled.flatMap(\.hosts)
        return hosts.isEmpty ? "none" : hosts.joined(separator: "\n")
    }

    private func export() {
        Task {
            let csv = await model.exportCSV()
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "quota-history.csv"
            panel.allowedContentTypes = [.commaSeparatedText]
            NSApp.activate()
            if panel.runModal() == .OK, let url = panel.url {
                try? csv.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

// MARK: - About

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 40))
            Text("Quota").font(.title2.bold())
            Text("Version \(QuotaInfo.version)").foregroundStyle(.secondary)
            Text("Local-first AI usage in your menu bar.\nOpen source under the MIT License.")
                .multilineTextAlignment(.center).font(.callout)
            Text("Not affiliated with Anthropic, DeepSeek, OpenRouter or OpenAI.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
