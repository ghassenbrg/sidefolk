import ApplicationServices
import Charts
import SidefolkCore
import SwiftUI

/// An extension's page (D62), drawn from Sidefolk's own parts: the extension says what is true, this decides how it
/// looks. Every text on it is the extension's, so it is shown verbatim and never styled as Sidefolk's own controls.
struct ExtensionPageView: View {
    var model: ExtensionPageModel

    var body: some View {
        // A page of numbers and charts may use a wide window; a page of switches stays a readable column. Either is
        // centred, so a wide window never leaves the page on one side.
        PageScroll(maxWidth: model.page?.isRich == true ? 1320 : 860) {
            header
            if let page = model.page {
                if let summary = page.summary { SummaryBanner(summary: summary, model: model) }
                if model.info.needsAccessibility || !model.palettes.isEmpty { HostControls(model: model) }
                ForEach(Array(page.runs.enumerated()), id: \.offset) { _, run in
                    if run.count == 1, let section = run.first, section.isWide {
                        SectionView(section: section, model: model)
                    } else {
                        SectionColumns(minWidth: 340, maxColumns: 3, spacing: Theme.Space.xl) {
                            ForEach(Array(run.enumerated()), id: \.offset) { _, section in SectionView(section: section, model: model) }
                        }
                    }
                }
                if !model.alerts.isEmpty { HeadsUps(model: model) }
            } else if let problem = model.problem {
                RowsCard { InlineEmpty(text: LocalizedStringKey(problem), systemImage: "exclamationmark.triangle") }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(Theme.Space.xxl)
            }
        }
        .task(id: model.info.id) { await model.run() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            PageIcon(info: model.info, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: model.info.title).font(Theme.Font.title).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
        }
    }

    private var subtitle: String {
        // "Your Mac, added by Your Mac" says nothing: the extension is named only when the page has another name.
        let from = model.info.extensionName == model.info.title ? nil
            : String(localized: "Added by \(model.info.extensionName)", comment: "Under an extension page's title: the extension it comes from")
        var parts = [from].compactMap { $0 }
        if let problem = model.problem, model.page != nil {
            parts.append(problem)
        } else if let updated = model.updated {
            parts.append(String(localized: "updated \(updated.formatted(date: .omitted, time: .standard))", comment: "When an extension page last refreshed"))
        }
        return parts.joined(separator: " · ")
    }
}

/// The extension's icon, or its page's symbol when it has none, in the shared rounded badge.
struct PageIcon: View {
    var info: ExtensionPageInfo
    var size: CGFloat

    var body: some View {
        ExtensionBadge(look: ExtensionLook(name: info.extensionName, iconPath: info.iconPath, folk: "byte"), size: size,
                       symbol: info.symbol ?? "puzzlepiece.extension")
    }
}

// MARK: Tones

extension ExtensionPage.Tone {
    var color: Color {
        switch self {
        case .good: Theme.success
        case .warn: Theme.sun
        case .bad: Theme.danger
        case .info: Theme.accent
        case .neutral: Theme.inkMuted
        }
    }

    var soft: Color {
        switch self {
        case .good: Theme.successSoft
        case .warn: Theme.sun.opacity(0.22)
        case .bad: Theme.dangerSoft
        case .info: Theme.accentSoft
        case .neutral: Theme.surfaceSunken
        }
    }

    var symbol: String {
        switch self {
        case .good: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .bad: "exclamationmark.octagon.fill"
        case .info: "info.circle.fill"
        case .neutral: "circle.fill"
        }
    }
}

// MARK: Summary

private struct SummaryBanner: View {
    var summary: ExtensionPage.Summary
    var model: ExtensionPageModel
    @State private var pending: Bool?

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: summary.symbol ?? summary.tone.symbol)
                .font(.system(size: 26, weight: .semibold)).foregroundStyle(summary.tone.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: summary.title).font(Theme.Font.heading).foregroundStyle(Theme.ink)
                if !summary.detail.isEmpty {
                    Text(verbatim: summary.detail).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer(minLength: 0)
            // The extension's main switch, as on its Today tile and sidebar row (D67).
            if let control = summary.control {
                switch control.kind {
                case .toggle(let on):
                    Toggle(isOn: Binding(get: { pending ?? on }, set: { new in
                        pending = new
                        Task {
                            await model.run(control, on: new)
                            pending = nil
                        }
                    })) { Text(verbatim: control.label) }
                        .toggleStyle(.switch).labelsHidden()
                        .disabled(pending != nil)
                        .help(Text(verbatim: control.detail ?? control.label))
                case .button:
                    ControlButton(control: control, model: model)
                }
            }
        }
        .padding(Theme.Space.l)
        .background(summary.tone.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(summary.tone.color.opacity(0.35)))
        .accessibilityElement(children: summary.control == nil ? .combine : .contain)
    }
}

// MARK: Sections

/// A section lays its parts out by kind: numbers side by side, cards in columns, notes and buttons across.
private struct SectionView: View {
    var section: ExtensionPage.Section
    var model: ExtensionPageModel

    private enum Group: Identifiable {
        case gauges([ExtensionPage.Block]), stats([ExtensionPage.Block]), cards([ExtensionPage.Block]), notes([ExtensionPage.Note]), asks([ExtensionPage.Ask])
        case switches([ExtensionPage.Control]), buttons([ExtensionPage.Control])
        /// Choices, fields and lists (D68), drawn in ExtensionPageInputs.swift.
        case inputs([ExtensionPage.Block])
        var id: String {
            switch self {
            case .gauges(let b): "g\(b.count)\(b.hashValue)"
            case .stats(let b): "m\(b.count)\(b.hashValue)"
            case .cards(let b): "c\(b.count)\(b.hashValue)"
            case .notes(let n): "n\(n.count)\(n.hashValue)"
            case .asks(let a): "a\(a.count)\(a.hashValue)"
            case .switches(let c): "s\(c.count)\(c.hashValue)"
            case .buttons(let c): "b\(c.count)\(c.hashValue)"
            case .inputs(let b): "i\(b.count)\(b.hashValue)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            if section.title != nil || hasCharts {
                HStack {
                    if let title = section.title { Text(verbatim: title).font(Theme.Font.heading).foregroundStyle(Theme.ink) }
                    Spacer(minLength: Theme.Space.s)
                    if hasCharts { windowPicker }
                }
            }
            ForEach(groups) { group in
                switch group {
                // Rings in one row and numbers in the next, each row filling the width (D67).
                case .gauges(let blocks), .stats(let blocks):
                    CardGrid(minWidth: 150, maxColumns: 6, spacing: Theme.Space.m) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in BlockView(block: b, model: model) }
                    }
                case .cards(let blocks):
                    CardGrid(minWidth: 340, maxColumns: 3, spacing: Theme.Space.m) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in BlockView(block: b, model: model) }
                    }
                case .notes(let notes):
                    VStack(alignment: .leading, spacing: Theme.Space.s) { ForEach(Array(notes.enumerated()), id: \.offset) { _, n in NoteView(note: n) } }
                case .switches(let controls):
                    RowsCard {
                        ForEach(Array(controls.enumerated()), id: \.offset) { _, c in SwitchRow(control: c, model: model) }
                    }
                case .buttons(let controls):
                    FlowRow(spacing: Theme.Space.s) {
                        ForEach(Array(controls.enumerated()), id: \.offset) { _, c in ControlButton(control: c, model: model) }
                    }
                case .inputs(let blocks):
                    ExtensionPageInputs(blocks: blocks, model: model)
                case .asks(let asks):
                    FlowRow(spacing: Theme.Space.s) {
                        ForEach(Array(asks.enumerated()), id: \.offset) { _, a in
                            Button { model.ask(a.ask) } label: { Label { Text(verbatim: a.label) } icon: { Image(systemName: "sparkles") } }
                                .buttonStyle(.sf(.secondary))
                                .help(Text(verbatim: a.ask))
                        }
                    }
                }
            }
        }
    }

    private var hasCharts: Bool { section.blocks.contains { if case .chart = $0 { true } else { false } } }

    private var windowPicker: some View {
        Picker(selection: Binding(get: { model.window }, set: { model.window = $0 })) {
            Text("10 min", comment: "Chart window: the last ten minutes").tag(ExtensionPageModel.Window.tenMinutes)
            Text("1 hour", comment: "Chart window: the last hour").tag(ExtensionPageModel.Window.hour)
            Text("24 hours", comment: "Chart window: the last day").tag(ExtensionPageModel.Window.day)
        } label: { EmptyView() }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
    }

    /// Consecutive parts of one kind stay together, in the order the extension gave them.
    private var groups: [Group] {
        var out: [Group] = []
        for block in section.blocks {
            switch block {
            case .gauge:
                if case .gauges(let b) = out.last { out[out.count - 1] = .gauges(b + [block]) } else { out.append(.gauges([block])) }
            case .stat:
                if case .stats(let b) = out.last { out[out.count - 1] = .stats(b + [block]) } else { out.append(.stats([block])) }
            case .chart, .bars, .facts:
                if case .cards(let b) = out.last { out[out.count - 1] = .cards(b + [block]) } else { out.append(.cards([block])) }
            case .note(let n):
                if case .notes(let ns) = out.last { out[out.count - 1] = .notes(ns + [n]) } else { out.append(.notes([n])) }
            case .ask(let a):
                if case .asks(let as_) = out.last { out[out.count - 1] = .asks(as_ + [a]) } else { out.append(.asks([a])) }
            case .choice, .field, .list:
                if case .inputs(let b) = out.last { out[out.count - 1] = .inputs(b + [block]) } else { out.append(.inputs([block])) }
            case .control(let c):
                if case .toggle = c.kind {
                    if case .switches(let cs) = out.last { out[out.count - 1] = .switches(cs + [c]) } else { out.append(.switches([c])) }
                } else if case .buttons(let cs) = out.last {
                    out[out.count - 1] = .buttons(cs + [c])
                } else {
                    out.append(.buttons([c]))
                }
            }
        }
        return out
    }
}

private struct BlockView: View {
    var block: ExtensionPage.Block
    var model: ExtensionPageModel

    var body: some View {
        switch block {
        case .gauge(let g): GaugeView(gauge: g)
        case .stat(let s): StatView(stat: s)
        case .chart(let c): ChartCard(chart: c, model: model)
        case .bars(let b): BarsCard(bars: b)
        case .facts(let f): FactsCard(facts: f)
        case .note(let n): NoteView(note: n)
        case .ask, .control, .choice, .field, .list: EmptyView()
        }
    }
}

// MARK: Parts

private struct GaugeView: View {
    var gauge: ExtensionPage.Gauge

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            ZStack {
                Circle().stroke(Theme.surfaceSunken, lineWidth: 9)
                Circle().trim(from: 0, to: max(0.004, gauge.fraction))
                    .stroke(gauge.tone.color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(Theme.Motion.spring(0.5), value: gauge.fraction)
                Text(verbatim: gauge.value).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 12).monospacedDigit()
            }
            .frame(width: 92, height: 92)
            VStack(spacing: 1) {
                Text(verbatim: gauge.label).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                if let caption = gauge.caption {
                    Text(verbatim: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2).multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(Theme.Space.m)
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(gauge.label) \(gauge.value)" + (gauge.caption.map { ", \($0)" } ?? "")))
    }
}

private struct StatView: View {
    var stat: ExtensionPage.Stat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: stat.label).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            HStack(spacing: 6) {
                if stat.tone != .neutral { Circle().fill(stat.tone.color).frame(width: 8, height: 8) }
                Text(verbatim: stat.value).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.7).monospacedDigit()
            }
            if let caption = stat.caption {
                Text(verbatim: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Theme.Space.m)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

private struct NoteView: View {
    var note: ExtensionPage.Note

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Image(systemName: note.tone.symbol).foregroundStyle(note.tone == .neutral ? Theme.inkFaint : note.tone.color)
            Text(verbatim: note.text).font(Theme.Font.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s + 2)
        .background(note.tone.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
    }
}

private struct CardTitle: View {
    var title: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
            if let caption { Text(verbatim: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

extension ExtensionPageModel.Window {
    /// Where the time axis marks fall: a label every few minutes or hours, never crowded.
    var tick: (unit: Calendar.Component, count: Int) {
        switch self {
        case .tenMinutes: (.minute, 2)
        case .hour: (.minute, 15)
        case .day: (.hour, 6)
        }
    }
}

/// Colors for a chart's lines, in order.
private let seriesColors: [Color] = [Theme.accent, Theme.coral, Theme.mint, Theme.sun]

private struct ChartCard: View {
    var chart: ExtensionPage.Chart
    var model: ExtensionPageModel

    private struct Point: Identifiable {
        var series: String
        var t: Date
        var v: Double
        var id: String { "\(series)\(t.timeIntervalSince1970)" }
    }

    var body: some View {
        let points = chart.series.flatMap { s in model.points(chart: chart.id, series: s.key).map { Point(series: s.label, t: $0.t, v: $0.v) } }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .top) {
                Text(verbatim: chart.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                Spacer(minLength: Theme.Space.s)
                // The value now, by line, in the line's color: the legend and the reading at once.
                HStack(spacing: Theme.Space.s) {
                    ForEach(Array(chart.series.enumerated()), id: \.offset) { i, s in
                        HStack(spacing: 4) {
                            Circle().fill(seriesColors[i % seriesColors.count]).frame(width: 7, height: 7)
                            Text(verbatim: chart.series.count > 1 ? "\(s.label) \(s.display ?? "")" : (s.display ?? ""))
                                .font(Theme.Font.captionStrong).foregroundStyle(Theme.ink).monospacedDigit()
                        }
                    }
                }
            }
            Chart(points) { p in
                AreaMark(x: .value(Self.time, p.t), y: .value(Self.amount, p.v), series: .value(Self.line, p.series), stacking: .unstacked)
                    .foregroundStyle(by: .value(Self.line, p.series)).opacity(0.12).interpolationMethod(.monotone)
                LineMark(x: .value(Self.time, p.t), y: .value(Self.amount, p.v), series: .value(Self.line, p.series))
                    .foregroundStyle(by: .value(Self.line, p.series)).interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .chartForegroundStyleScale(domain: chart.series.map(\.label), range: Array(seriesColors.prefix(max(1, chart.series.count))))
            .chartLegend(.hidden)
            .chartYScale(domain: 0...(chart.max ?? max(0.001, (points.map(\.v).max() ?? 1) * 1.15)))
            .chartXScale(domain: Date().addingTimeInterval(-model.window.seconds)...Date())
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel { if let v = value.as(Double.self) { Text(verbatim: Self.axis(v, unit: chart.unit)) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: model.window.tick.unit, count: model.window.tick.count)) { _ in
                    AxisGridLine().foregroundStyle(Theme.line.opacity(0.5))
                    AxisValueLabel(format: model.window == .day ? .dateTime.hour() : .dateTime.hour().minute(), collisionResolution: .greedy)
                }
            }
            .frame(height: 140)
            .overlay {
                if points.count < 2 {
                    Text("Collecting…", comment: "A chart that has too few readings yet").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                }
            }
            if let caption = chart.caption {
                Text(verbatim: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(Theme.Space.m)
        .cardSurface()
    }

    // The marks' own names, which nobody reads (the legend is hidden): plain strings, kept out of the catalog.
    static let time = "time", amount = "value", line = "series"

    static func axis(_ v: Double, unit: String?) -> String {
        let number = v >= 10 || v == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)
        guard let unit else { return number }
        return unit == "%" ? number + "%" : "\(number) \(unit)"
    }
}

private struct BarsCard: View {
    var bars: ExtensionPage.Bars

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            CardTitle(title: bars.title, caption: bars.caption)
            if bars.items.isEmpty {
                Text("Nothing to show right now.", comment: "An extension page's list of bars is empty")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
            }
            ForEach(Array(bars.items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: item.label).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: Theme.Space.s)
                        Text(verbatim: item.value).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted).monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.surfaceSunken)
                            Capsule().fill(item.tone == .neutral ? Theme.accent : item.tone.color)
                                .frame(width: max(4, geo.size.width * item.fraction))
                        }
                    }
                    .frame(height: 6)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Theme.Space.m)
        .cardSurface()
    }
}

private struct FactsCard: View {
    var facts: ExtensionPage.Facts
    @Environment(\.pixelLength) private var pixel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let title = facts.title { CardTitle(title: title) }
            VStack(spacing: 0) {
                ForEach(Array(facts.items.enumerated()), id: \.offset) { i, fact in
                    if i > 0 { Rectangle().fill(Theme.line).frame(height: pixel * 2) }
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                        Text(verbatim: fact.label).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                        Spacer(minLength: Theme.Space.s)
                        Text(verbatim: fact.value).font(Theme.Font.body).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 7)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Theme.Space.m)
        .cardSurface()
    }
}

// MARK: Switches and buttons

/// A switch that runs the extension's tool as the person; it shows the new state at once and the page's next read
/// confirms it.
private struct SwitchRow: View {
    var control: ExtensionPage.Control
    var model: ExtensionPageModel
    @State private var pending: Bool?

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            if let symbol = control.symbol { Image(systemName: symbol).foregroundStyle(Theme.inkMuted).frame(width: 20) }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: control.label).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                if let detail = control.detail {
                    Text(verbatim: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.m)
            Toggle(isOn: Binding(get: { pending ?? isOn }, set: { on in
                pending = on
                Task {
                    await model.run(control, on: on)
                    pending = nil
                }
            })) { Text(verbatim: control.label) }
                .toggleStyle(.switch).labelsHidden()
                .disabled(pending != nil)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
    }

    private var isOn: Bool { if case .toggle(let on) = control.kind { on } else { false } }
}

private struct ControlButton: View {
    var control: ExtensionPage.Control
    var model: ExtensionPageModel
    @State private var running = false

    var body: some View {
        Button {
            running = true
            Task {
                await model.run(control, on: nil)
                running = false
            }
        } label: {
            if let symbol = control.symbol {
                Label { Text(verbatim: control.label) } icon: { Image(systemName: symbol) }
            } else {
                Text(verbatim: control.label)
            }
        }
        .buttonStyle(.sf(style))
        .disabled(running)
        .help(control.detail.map { Text(verbatim: $0) } ?? Text(verbatim: control.label))
    }

    private var style: SFButtonStyle.Kind {
        guard case .button(let s) = control.kind else { return .secondary }
        return switch s {
        case .primary: .primary
        case .secondary: .secondary
        case .destructive: .destructive
        }
    }
}

// MARK: What Sidefolk does for it

/// The palette's shortcut, changeable here, and Accessibility when the extension pastes or keeps the person active:
/// Sidefolk's own part of the page, not the extension's (D63).
private struct HostControls: View {
    var model: ExtensionPageModel
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if !model.palettes.isEmpty {
                RowsCard {
                    ForEach(model.palettes) { p in PaletteSettingsRow(info: p) }
                }
            }
            if model.info.needsAccessibility, !trusted {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Image(systemName: "hand.raised.fill").foregroundStyle(Theme.sun)
                    Group {
                        if model.palettes.isEmpty {
                            Text("To keep you active in other apps, Sidefolk needs Accessibility.", comment: "On an extension page that keeps the person active")
                        } else {
                            Text("To paste for you, Sidefolk needs Accessibility. Until then, what you choose is copied and you paste it yourself.",
                                 comment: "On an extension page whose palette pastes")
                        }
                    }
                        .font(Theme.Font.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Space.s)
                    Button("Allow…") {
                        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.sf(.secondary))
                }
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s + 2)
                .background(Theme.sun.opacity(0.18), in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
                .task {
                    // Picks up the switch in System Settings without reopening the page.
                    while !Task.isCancelled, !trusted {
                        try? await Task.sleep(for: .seconds(2))
                        trusted = AXIsProcessTrusted()
                    }
                }
            }
        }
    }
}

// MARK: Heads-ups

/// The extension's watchers as switches: on, it checks every five minutes and the companion speaks up.
private struct HeadsUps: View {
    var model: ExtensionPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            SectionHeader(title: "Heads-ups", folk: "scout")
            Text("Switch one on and your companion tells you when it happens. Each checks every five minutes.")
                .font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
            RowsCard {
                ForEach(model.alerts) { alert in
                    HStack(spacing: Theme.Space.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: alert.kind.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                            if !alert.kind.description.isEmpty {
                                Text(verbatim: alert.kind.description).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: Theme.Space.m)
                        Toggle(isOn: Binding(get: { alert.watcherId != nil }, set: { on in Task { await model.setAlert(alert, on: on) } })) {
                            Text(verbatim: alert.kind.title)
                        }
                        .toggleStyle(.switch).labelsHidden()
                    }
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.s + 2)
                }
            }
            if let problem = model.alertProblem {
                Text(verbatim: problem).font(Theme.Font.caption).foregroundStyle(Theme.danger)
            }
        }
    }
}
