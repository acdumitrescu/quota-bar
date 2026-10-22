import Charts
import QuotaCore
import SwiftUI

struct MenuPanel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if settings.enabled.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(settings.enabled) { id in
                            ProviderCard(id: id, state: model.states[id], sparklines: model.sparklines)
                            if id != settings.enabled.last { Divider() }
                        }
                    }
                    .padding(14)
                }
                .frame(maxHeight: 560)
            }
            Divider()
            footer.padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to Quota").font(.headline)
            Text("Turn on the providers you use. Everything stays on this Mac; Quota only contacts the services you enable.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Choose providers…") { showSettings() }
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let t = model.lastRefresh {
                Text("Updated \(t.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise").accessibilityLabel("Refresh")
            }
            .disabled(model.isRefreshing)
            .keyboardShortcut("r")
            Button { showSettings() } label: {
                Image(systemName: "gearshape").accessibilityLabel("Settings")
            }
            .keyboardShortcut(",")
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power").accessibilityLabel("Quit Quota")
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
    }

    private func showSettings() {
        // Menu bar apps have no Dock icon, so bring the app forward before opening the window.
        NSApp.activate()
        openSettings()
    }
}

struct ProviderCard: View {
    let id: ProviderID
    let state: AppModel.ProviderState?
    let sparklines: [String: [History.Sample]]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(id.displayName).font(.headline)
                if id.isUnofficial { Badge(text: "Unofficial") }
                Spacer()
                if state == nil { ProgressView().controlSize(.small) }
            }
            if let error = state?.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let snap = state?.snapshot {
                ForEach(snap.meters) { MeterRow(meter: $0, samples: sparklines[$0.id] ?? []) }
                if !snap.stats.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                        ForEach(snap.stats) { s in
                            GridRow {
                                Text(s.label).foregroundStyle(.secondary)
                                Text(Format.value(s.value, s.unit))
                                    .monospacedDigit().fontWeight(.medium)
                                    .gridColumnAlignment(.trailing)
                            }
                            .font(.callout)
                        }
                    }
                }
                ForEach(snap.breakdowns, id: \.title) { BreakdownView(breakdown: $0) }
                ForEach(snap.notes, id: \.self) {
                    Text($0).font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct MeterRow: View {
    let meter: Meter
    let samples: [History.Sample]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(meter.label)
                Spacer()
                Text("\(Int(meter.percent.rounded()))%").monospacedDigit().fontWeight(.semibold)
            }
            ProgressView(value: min(max(meter.percent, 0), 100), total: 100)
                .tint(meter.percent >= 90 ? .red : meter.percent >= 70 ? .orange : .accentColor)
            HStack {
                if let caption = Format.reset(meter.resetsAt) ?? meter.caption {
                    Text(caption).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if samples.count > 2 { Sparkline(samples: samples).frame(width: 90, height: 16) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct Sparkline: View {
    let samples: [History.Sample]

    var body: some View {
        Chart(samples, id: \.at) {
            LineMark(x: .value("Time", $0.at), y: .value("Percent", $0.value))
                .interpolationMethod(.stepEnd)
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Last 7 days")
    }
}

struct BreakdownView: View {
    let breakdown: Breakdown
    @State private var expanded = false

    var body: some View {
        let rows = expanded ? breakdown.rows : Array(breakdown.rows.prefix(3))
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(breakdown.title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if breakdown.rows.count > 3 {
                    Button(expanded ? "Less" : "All \(breakdown.rows.count)") { expanded.toggle() }
                        .buttonStyle(.link).font(.caption)
                }
            }
            ForEach(rows) { r in
                HStack {
                    Text(r.label).lineLimit(1)
                    Spacer()
                    Text(Format.value(r.value, r.unit)).monospacedDigit()
                }
                .font(.caption)
                .padding(.leading, 8)
            }
        }
    }
}

struct Badge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
    }
}
