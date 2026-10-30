import Charts
import SidefolkCore
import SwiftUI

/// An extension's page (D62), drawn from Sidefolk's own parts: the extension says what is true, this decides how it
/// looks. Every text on it is the extension's, so it is shown verbatim and never styled as Sidefolk's own controls.
struct ExtensionPageView: View {
    var model: ExtensionPageModel

    var body: some View {
        PageScroll(maxWidth: 940) {
            header
            if let page = model.page {
                if let summary = page.summary { SummaryBanner(summary: summary) }
                ForEach(Array(page.sections.enumerated()), id: \.offset) { _, section in
                    SectionView(section: section, model: model)
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
        let from = String(localized: "Added by \(model.info.extensionName)", comment: "Under an extension page's title: the extension it comes from")
        guard let updated = model.updated else { return from }
        if let problem = model.problem, model.page != nil {
            return "\(from) · \(problem)"
        }
        return "\(from) · " + String(localized: "updated \(updated.formatted(date: .omitted, time: .standard))",
                                     comment: "When an extension page last refreshed")
    }
}

/// The extension's icon, or its page's symbol when it has none.
struct PageIcon: View {
    var info: ExtensionPageInfo
    var size: CGFloat

    var body: some View {
        if let path = info.iconPath, let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            IconTile(symbol: info.symbol ?? "puzzlepiece.extension", folk: "byte", size: size)
        }
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
        }
        .padding(Theme.Space.l)
        .background(summary.tone.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(summary.tone.color.opacity(0.35)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Sections

/// A section lays its parts out by kind: numbers side by side, cards in columns, notes and buttons across.
private struct SectionView: View {
    var section: ExtensionPage.Section
    var model: ExtensionPageModel

    private enum Group: Identifiable {
        case metrics([ExtensionPage.Block]), cards([ExtensionPage.Block]), notes([ExtensionPage.Note]), asks([ExtensionPage.Ask])
        var id: String {
            switch self {
            case .metrics(let b): "m\(b.count)\(b.hashValue)"
            case .cards(let b): "c\(b.count)\(b.hashValue)"
            case .notes(let n): "n\(n.count)\(n.hashValue)"
            case .asks(let a): "a\(a.count)\(a.hashValue)"
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
                case .metrics(let blocks):
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Space.m, alignment: .top)], alignment: .leading,
                              spacing: Theme.Space.m) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in BlockView(block: b, model: model) }
                    }
                case .cards(let blocks):
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: Theme.Space.m, alignment: .top)], alignment: .leading,
                              spacing: Theme.Space.m) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in BlockView(block: b, model: model) }
                    }
                case .notes(let notes):
                    VStack(alignment: .leading, spacing: Theme.Space.s) { ForEach(Array(notes.enumerated()), id: \.offset) { _, n in NoteView(note: n) } }
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
            case .gauge, .stat:
                if case .metrics(let b) = out.last { out[out.count - 1] = .metrics(b + [block]) } else { out.append(.metrics([block])) }
            case .chart, .bars, .facts:
                if case .cards(let b) = out.last { out[out.count - 1] = .cards(b + [block]) } else { out.append(.cards([block])) }
            case .note(let n):
                if case .notes(let ns) = out.last { out[out.count - 1] = .notes(ns + [n]) } else { out.append(.notes([n])) }
            case .ask(let a):
                if case .asks(let as_) = out.last { out[out.count - 1] = .asks(as_ + [a]) } else { out.append(.asks([a])) }
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
        case .ask: EmptyView()
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
        .frame(maxWidth: .infinity)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .cardSurface()
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

/// Buttons in rows that wrap, in reading order.
private struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1] = (last.items + [i], last.width + spacing + size.width, max(last.height, size.height))
            } else {
                rows.append(([i], size.width, size.height))
            }
        }
        return rows
    }
}
