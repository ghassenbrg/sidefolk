import ApplicationServices
import Charts
import SidefolkCore
import SwiftUI

/// An extension's page (D62), drawn from Sidefolk's own parts: the extension says what is true, this decides how it
/// looks. Every text on it is the extension's, so it is shown verbatim and never styled as Sidefolk's own controls.
struct ExtensionPageView: View {
    var model: ExtensionPageModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let page = model.page, page.workspace { PageWorkspace(page: page, model: model) } else { scrolling }
        }
        .environment(\.cardDress, cardDress)
        .environment(\.pageAccent, pageAccent)
        .environment(\.pageSelected, pageSelected)
        .environment(\.pageAccentWords, model.page?.dress?.accent?.words(scheme) ?? .white)
        .environment(\.pageWell, model.page?.dress?.well?.color(scheme))
        .tint(pageAccent)
        .pageConsent(model: model)
        .task(id: model.info.id) { await model.run() }
    }

    private var scrolling: some View {
        // A page of numbers and charts may use a wide window; a page of switches stays a readable column. Either is
        // centred, so a wide window never leaves the page on one side.
        PageScroll(maxWidth: model.page?.maxWidth.map { CGFloat($0) } ?? (model.page?.isRich == true ? 1320 : 860), bleed: model.page?.bleed == true) {
            // Told to the program, which may draw to it (D105): the column it fills, wherever the window puts it.
            Color.clear.frame(height: 0).frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { model.setWidth($0) }
            // What went wrong with a click, and the words a click just copied, are Sidefolk's to say whatever the page draws (D105).
            if model.page?.bare == true, let problem = model.problem {
                NoteView(note: ExtensionPage.Note(text: problem, tone: .bad))
            }
            if let copied = model.copied {
                Label { Text("Copied: \(copied)", comment: "An extension's page: the exact words a button just put on the clipboard") } icon: { Image(systemName: "doc.on.clipboard") }
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2)
            }
            // A hero with a scene carries the page's title itself (D100), large; a bare page draws its own head (D105).
            if model.page?.hero?.scene == nil, model.page?.bare != true { header }
            // A page led by its own head has the way back there, with the same key.
            if let back = model.page?.back, model.state.canGoBack, model.page?.leadsWithBar != true {
                Button { Task { await model.go(PageGo(back: true)) } } label: {
                    Label { Text(ext: back) } icon: { Image(systemName: "chevron.backward") }
                }
                .buttonStyle(.sf(.quiet))
                .keyboardShortcut("[", modifiers: .command)
                // A page out to its edges draws its own way back: this keeps the key and VoiceOver's name for it.
                .frame(height: model.page?.bleed == true ? 0 : nil)
                .opacity(model.page?.bleed == true ? 0 : 1)
            }
            if let updates = model.updates, let entry = updates.addonUpdate(for: model.info.extensionId) {
                AddonUpdateStrip(entry: entry, updates: updates)
            }
            if let page = model.page {
                // A hero leading the page says what the summary would, larger and with its actions (D74).
                if let summary = page.summary, page.hero == nil, !page.bare { SummaryBanner(summary: summary, model: model) }
                // Under the page's own head when it has one, so what it needs from macOS doesn't stand above its name.
                if !page.leadsWithBar, showsHostControls(page) { HostControls(model: model, quiet: page.quietHost) }
                PageRegions(spacing: page.bleed ? 0 : page.isComposed ? Theme.Space.l : Theme.Space.xl) {
                    ForEach(Array(page.regions.enumerated()), id: \.offset) { i, part in
                        Group {
                            if part.sections.first?.row != nil, part.sections.count > 1 {
                                PageRowView(sections: part.sections, model: model)
                            } else if part.sections.count == 1, let section = part.sections.first, section.isWide || part.region != .main {
                                SectionView(section: section, model: model)
                            } else {
                                // Beside a side column the main one is narrower: two small sections to a row at most.
                                SectionColumns(minWidth: 340, maxColumns: page.hasSide ? 2 : 3, spacing: Theme.Space.xl) {
                                    ForEach(Array(part.sections.enumerated()), id: \.offset) { _, section in SectionView(section: section, model: model) }
                                }
                            }
                        }
                        .pageRegion(part.region)
                        // On a page out to its edges a scene keeps its own margins; what Sidefolk draws keeps Sidefolk's.
                        .padding(page.bleed && !part.sections.allSatisfy(\.isOnlyScenes) ? Theme.Space.xl : 0)
                        if i == 0, page.leadsWithBar, showsHostControls(page) { HostControls(model: model, quiet: page.quietHost).pageRegion(.top) }
                    }
                }
                if !model.alerts.isEmpty, !page.placesHeadsUps { HeadsUps(model: model) }
                // A bare page's head is the extension's own: whose page this is stays Sidefolk's to say.
                if page.bare {
                    Text("Added by \(model.info.extensionName)", comment: "Under an extension page's title: the extension it comes from")
                        .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                        .padding(page.bleed ? Theme.Space.l : 0)
                }
            } else if let problem = model.problem {
                RowsCard { InlineEmpty(label: Text(ext: problem), systemImage: "exclamationmark.triangle") }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(Theme.Space.xxl)
            }
        } ground: {
            PageGround(dress: model.page?.dress, model: model)
        }
    }

    /// What's selected: a dress's own colour, or a page's own accent (D126). A dress with neither keeps its look.
    private var pageSelected: Color? {
        if let dress = model.page?.dress {
            return dress.selected?.color(scheme) ?? (dress.accent == nil ? model.page?.accent.last.flatMap { Color(extensionHex: $0) } : nil)
        }
        return model.page?.accent.last.flatMap { Color(extensionHex: $0) }
    }

    private func showsHostControls(_ page: ExtensionPage) -> Bool {
        guard !page.placesHostControls else { return false }
        return (!model.palettes.isEmpty && !page.quietHost) || (model.info.needsAccessibility && !AXIsProcessTrusted())
    }

    /// A dressed page's filled buttons and switches (D108).
    private var pageAccent: Color? {
        if let dressed = model.page?.dress?.accent { return Color(extensionHex: scheme == .dark ? dressed.dark : dressed.light) }
        return model.page?.accent.first.flatMap { Color(extensionHex: $0) }
    }

    /// A dressed page's cards (D108).
    private var cardDress: CardDress? {
        guard let dress = model.page?.dress, let card = dress.card, let fill = Color(extensionHex: scheme == .dark ? card.dark : card.light) else { return nil }
        return CardDress(fill: fill, line: dress.line.flatMap { Color(extensionHex: scheme == .dark ? $0.dark : $0.light) })
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            PageIcon(info: model.info, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(ext: model.info.title).font(Theme.Font.title).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                    .homePageTitle()
                Text(subtitle).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
        }
    }

    private var subtitle: String {
        // "Tea Timer, added by Tea Timer" says nothing: the extension is named only when the page has another name.
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
    /// Readable as text as well as on icons, gauges and dots: an extension's "info" is the link colour, not the
    /// accent fill, which can be too light to read.
    var color: Color { Theme.color(.page(self)) }

    var soft: Color { Theme.soft(.page(self)) }

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
                Text(ext: summary.title).font(Theme.Font.heading).foregroundStyle(Theme.ink)
                if !summary.detail.isEmpty {
                    Text(ext: summary.detail).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
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
                    })) { Text(ext: control.label) }
                        .toggleStyle(.switch).labelsHidden()
                        .disabled(pending != nil)
                        .help(Text(ext: control.detail ?? control.label))
                case .button:
                    PageButton(control: control, model: model)
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
struct SectionView: View {
    var section: ExtensionPage.Section
    var model: ExtensionPageModel

    private enum Group: Identifiable {
        case gauges([ExtensionPage.Block]), stats([ExtensionPage.Block]), cards([ExtensionPage.Block]), notes([ExtensionPage.Note]), asks([ExtensionPage.Ask])
        case switches([ExtensionPage.Control]), buttons([ExtensionPage.Control])
        /// Choices, fields and lists (D68), drawn in ExtensionPageInputs.swift.
        case inputs([ExtensionPage.Block])
        case hero(ExtensionPage.Hero), transport(ExtensionPage.Transport)
        /// The richer parts (D100), each on its own, drawn in ExtensionPageRich.swift.
        case rich(ExtensionPage.Block)
        case metrics([ExtensionPage.Block]), askRows([ExtensionPage.Ask]), wideButton(ExtensionPage.Control)
        var id: String {
            switch self {
            case .gauges(let b): "g\(b.count)\(b.hashValue)"
            case .stats(let b): "m\(b.count)\(b.hashValue)"
            case .cards(let b): "c\(b.count)\(b.hashValue)"
            case .notes(let n): "n\(n.count)\(n.hashValue)"
            case .asks(let a): "a\(a.count)\(a.hashValue)"
            case .switches(let c): "s\(c.count)\(c.hashValue)"
            case .buttons(let c): "b\(c.count)\(c.hashValue)"
            // By what they are, not what they hold: a search box keeps the keyboard, and a list its place, as the rows change.
            case .inputs(let b): "i" + b.map(\.inputIdentity).joined(separator: "|")
            case .hero(let h): "h\(h.hashValue)"
            case .transport(let t): "t\(t.hashValue)"
            case .rich(let b): "r\(b.hashValue)"
            case .metrics(let b): "x\(b.count)\(b.hashValue)"
            case .askRows(let a): "q\(a.count)\(a.hashValue)"
            case .wideButton(let c): "w\(c.hashValue)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            if let title = section.title, section.collapsed != nil {
                // Folded under its title until opened (D74): settings most people never change.
                Button {
                    withAnimation(Theme.Motion.ease(0.18)) { model.toggleOpen(title) }
                } label: {
                    HStack(spacing: Theme.Space.s) {
                        Image(systemName: "chevron.forward").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.inkMuted)
                            .rotationEffect(.degrees(open ? 90 : 0))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ext: title).font(Theme.Font.heading).foregroundStyle(Theme.ink)
                            if let detail = section.detail {
                                Text(ext: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Theme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.sfBare)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(open ? Text("Unfolded", comment: "Spoken state of a section of an extension page that folds: open now")
                                         : Text("Folded", comment: "Spoken state of a section of an extension page that folds: closed now"))
            } else if let banner = section.banner, let title = section.title {
                banded(title, banner)
            } else if section.title != nil || hasCharts {
                HStack {
                    if let picture = section.picture {
                        PagePictureView(picture: picture, model: model, side: 56).frame(width: 28, height: 28).clipShape(Circle())
                    }
                    if let status = section.status { Circle().fill(status == .neutral ? Theme.inkFaint : status.color).frame(width: 10, height: 10) }
                    if section.card || section.joined {
                        // In a card there's room for its line under the title, whole.
                        VStack(alignment: .leading, spacing: 3) {
                            if let title = section.title { Text(ext: title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader) }
                            if let detail = section.detail { Text(ext: detail).font(Theme.Font.body).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true) }
                        }
                    } else {
                        if let title = section.title { Text(ext: title).font(Theme.Font.heading).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader) }
                        if let detail = section.detail { Text(ext: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1) }
                    }
                    Spacer(minLength: Theme.Space.s)
                    if hasCharts { windowPicker }
                    ForEach(Array(section.accessories.enumerated()), id: \.offset) { _, accessory in PageSectionAccessory(block: accessory, model: model) }
                }
            }
            if open { content }
        }
        .modifier(SectionCardModifier(on: section.card))
    }

    /// Its title on a band in the extension's colour, with its picture or a symbol at the start.
    private func banded(_ title: String, _ banner: ExtensionPage.Section.Banner) -> some View {
        let tint = Color(extensionHex: banner.tint) ?? Theme.accent
        return HStack(spacing: 8) {
            if let picture = section.picture {
                PagePictureView(picture: picture, model: model, side: 48).frame(width: 24, height: 24).clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            } else if let symbol = banner.symbol {
                Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(tint).frame(width: 24, height: 24)
            }
            Text(ext: title).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.16))))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .accessibilityAddTraits(.isHeader)
    }

    /// A section that folds is open once the person opened it, or when the extension doesn't fold it.
    private var open: Bool {
        guard let title = section.title, let collapsed = section.collapsed else { return true }
        // The person's click turns the extension's default over.
        return model.opened.contains(title) == collapsed
    }

    @ViewBuilder private var content: some View {
        ForEach(groups) { group in
            // Its last part stands at the foot of the card, however tall the row made it.
            if section.pinLast, group.id == groups.last?.id { Spacer(minLength: 0) }
            switch group {
            // Rings in one row and numbers in the next, each row filling the width (D67).
            case .gauges(let blocks), .stats(let blocks):
                CardGrid(minWidth: 150, maxColumns: 6, spacing: Theme.Space.m) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in BlockView(block: b, model: model) }
                }
            case .cards(let blocks):
                CardGrid(minWidth: section.card ? 220 : 340, maxColumns: 3, spacing: section.card ? Theme.Space.l : Theme.Space.m) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in BlockView(block: b, model: model) }
                }
            case .metrics(let blocks):
                CardGrid(minWidth: 180, maxColumns: blocks.count, spacing: Theme.Space.m) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in if case .metric(let m) = b { PageMetricView(metric: m, model: model) } }
                }
            case .askRows(let asks):
                PageAskRows(asks: asks, model: model)
            case .wideButton(let control):
                PageButton(control: control, model: model, large: true)
            case .notes(let notes):
                VStack(alignment: .leading, spacing: Theme.Space.s) { ForEach(Array(notes.enumerated()), id: \.offset) { _, n in NoteView(note: n, model: model) } }
            case .switches(let controls):
                RowsCard {
                    ForEach(Array(controls.enumerated()), id: \.offset) { _, c in SwitchRow(control: c, model: model) }
                }
            case .buttons(let controls):
                FlowRow(spacing: Theme.Space.s) {
                    ForEach(Array(controls.enumerated()), id: \.offset) { _, c in PageButton(control: c, model: model) }
                }
            case .inputs(let blocks):
                ExtensionPageInputs(blocks: blocks, model: model)
            case .hero(let h):
                HeroView(hero: h, model: model)
            case .transport(let t):
                TransportView(transport: t, model: model)
            case .rich(let b):
                RichBlockView(block: b, model: model)
            case .asks(let asks):
                FlowRow(spacing: Theme.Space.s) {
                    ForEach(Array(asks.enumerated()), id: \.offset) { _, a in
                        Button { model.ask(a.ask) } label: { Label { Text(ext: a.label) } icon: { Image(systemName: "sparkles") } }
                            .buttonStyle(.sf(.secondary))
                            .help(Text(ext: a.ask))
                    }
                }
            }
        }
    }

    private var hasCharts: Bool { section.blocks.contains { if case .chart = $0 { true } else { false } } }

    @ViewBuilder private var windowPicker: some View {
        // In a card, as the page's other small choices look.
        if section.card {
            PageWindowPills(model: model)
        } else {
            defaultWindowPicker
        }
    }

    private var defaultWindowPicker: some View {
        SegmentedPicker(Text("Chart window", comment: "What the 10 min / 1 hour / 24 hours choice above a chart is, read by VoiceOver"),
                        selection: Binding(get: { model.window }, set: { model.window = $0 }), segments: [
            .init(ExtensionPageModel.Window.tenMinutes, Text("10 min", comment: "Chart window: the last ten minutes")),
            .init(ExtensionPageModel.Window.hour, Text("1 hour", comment: "Chart window: the last hour")),
            .init(ExtensionPageModel.Window.day, Text("24 hours", comment: "Chart window: the last day")),
        ], small: true)
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
            case .metric:
                if case .metrics(let b) = out.last { out[out.count - 1] = .metrics(b + [block]) } else { out.append(.metrics([block])) }
            case .ask(let a) where a.row:
                if case .askRows(let as_) = out.last { out[out.count - 1] = .askRows(as_ + [a]) } else { out.append(.askRows([a])) }
            case .ask(let a):
                if case .asks(let as_) = out.last { out[out.count - 1] = .asks(as_ + [a]) } else { out.append(.asks([a])) }
            case .choice, .field, .list:
                if case .inputs(let b) = out.last { out[out.count - 1] = .inputs(b + [block]) } else { out.append(.inputs([block])) }
            case .hero(let h):
                out.append(.hero(h))
            case .transport(let t):
                out.append(.transport(t))
            case .stats, .cards, .tabs, .badges, .recent, .settings, .scene, .table, .steps, .tree, .bar, .nav, .notice, .ticks, .heading, .headsUps, .hostControls, .preview:
                out.append(.rich(block))
            case .control(let c) where c.fill:
                out.append(.wideButton(c))
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
        case .bars(let b): BarsCard(bars: b, model: model)
        case .facts(let f): FactsCard(facts: f)
        case .note(let n): NoteView(note: n)
        case .ask, .control, .choice, .field, .list, .hero, .transport, .stats, .cards, .tabs, .badges, .recent, .settings, .scene, .table, .steps, .tree, .bar, .nav, .notice, .ticks, .metric, .heading, .headsUps, .hostControls, .preview: EmptyView()
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
                Text(ext: gauge.value).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 12).monospacedDigit()
            }
            .frame(width: 92, height: 92)
            VStack(spacing: 1) {
                Text(ext: gauge.label).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                if let caption = gauge.caption {
                    Text(ext: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2).multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(Theme.Space.m)
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(ext: "\(gauge.label) \(gauge.value)" + (gauge.caption.map { ", \($0)" } ?? "")))
    }
}

private struct StatView: View {
    var stat: ExtensionPage.Stat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(ext: stat.label).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            HStack(spacing: 6) {
                if stat.tone != .neutral { Circle().fill(stat.tone.color).frame(width: 8, height: 8) }
                Text(ext: stat.value).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.7).monospacedDigit()
            }
            if let caption = stat.caption {
                Text(ext: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Theme.Space.m)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

struct NoteView: View {
    var note: ExtensionPage.Note
    var model: ExtensionPageModel?
    @Environment(\.pageWell) private var well
    @Environment(\.pageSelected) private var selected

    private var markColor: Color {
        if note.tone != .neutral { return note.tone.color }
        return note.style == .band ? (selected ?? Theme.inkFaint) : Theme.inkMuted
    }

    var body: some View {
        switch note.style {
        case .band:
            line
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s + 2)
                .background(note.tone == .neutral ? (well ?? note.tone.soft) : note.tone.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
        case .plain:
            line
        case .verdict:
            HStack(spacing: Theme.Space.m) {
                Image(systemName: note.symbol ?? note.tone.symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(note.tone == .neutral ? Theme.inkMuted : note.tone.color)
                    .frame(width: 30, height: 30)
                    .background(note.tone.soft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(ext: note.text).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var line: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Image(systemName: note.symbol ?? note.tone.symbol).foregroundStyle(markColor)
            Text(ext: note.text).font(Theme.Font.body).foregroundStyle(note.style == .plain && note.tone == .neutral ? Theme.inkMuted : Theme.ink).fixedSize(horizontal: false, vertical: true)
            if let link = note.link, let model {
                Button { Task { await model.run(link, on: nil) } } label: { Text(ext: link.label).font(Theme.Font.body).foregroundStyle(Theme.link) }
                    .buttonStyle(.sfBare)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A section as one card: its title and parts inside, the parts flat. Its padding is the same as a row's.
private struct SectionCardModifier: ViewModifier {
    var on: Bool

    func body(content: Content) -> some View {
        if on {
            content
                .environment(\.pageFlat, true)
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .cardSurface()
        } else {
            content
        }
    }
}

/// A choice or a button at the end of a section's title.
private struct PageSectionAccessory: View {
    var block: ExtensionPage.Block
    var model: ExtensionPageModel

    var body: some View {
        switch block {
        case .control(let control): PageButton(control: control, model: model)
        case .choice(let choice): PageChoiceInline(choice: choice, model: model)
        default: EmptyView()
        }
    }
}

private struct CardTitle: View {
    var title: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ext: title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
            if let caption { Text(ext: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true) }
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
    @Environment(\.pageFlat) private var flat
    @Environment(\.colorScheme) private var scheme

    /// The chart's own colours, where it names them.
    private var colors: [Color] {
        let own = chart.colors.compactMap { $0.color(scheme) }
        return own.isEmpty ? seriesColors : own
    }

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
                if !chart.title.isEmpty, !flat { Text(ext: chart.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink) }
                if !flat { Spacer(minLength: Theme.Space.s) }
                // The value now, by line, in the line's color: the legend and the reading at once.
                HStack(spacing: Theme.Space.s) {
                    ForEach(Array(chart.series.enumerated()), id: \.offset) { i, s in
                        HStack(spacing: 4) {
                            Circle().fill(colors[i % colors.count]).frame(width: 7, height: 7)
                            Text(ext: chart.series.count > 1 ? "\(s.label) \(s.display ?? "")" : (s.display ?? ""))
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
            .chartForegroundStyleScale(domain: chart.series.map(\.label), range: Array((0..<max(1, chart.series.count)).map { colors[$0 % colors.count] }))
            .chartLegend(.hidden)
            .chartYScale(domain: 0...(chart.max ?? max(0.001, (points.map(\.v).max() ?? 1) * 1.15)))
            .chartXScale(domain: Date().addingTimeInterval(-model.window.seconds)...Date())
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel { if let v = value.as(Double.self) { Text(ext: Self.axis(v, unit: chart.unit)) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: model.window.tick.unit, count: model.window.tick.count)) { _ in
                    AxisGridLine().foregroundStyle(Theme.line.opacity(0.5))
                    AxisValueLabel(format: model.window == .day ? .dateTime.hour() : .dateTime.hour().minute(), collisionResolution: .greedy)
                }
            }
            .frame(height: chart.height.map { CGFloat($0) } ?? 140)
            .overlay {
                if points.count < 2 {
                    Text("Collecting…", comment: "A chart that has too few readings yet").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
                }
            }
            if let caption = chart.caption {
                Text(ext: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(flat ? 0 : Theme.Space.m)
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
    var model: ExtensionPageModel
    @Environment(\.pageFlat) private var flat
    @Environment(\.pageWell) private var well
    @Environment(\.pageSelected) private var selected

    private func color(_ item: ExtensionPage.Bar) -> Color { item.tone == .neutral ? selected ?? Theme.accent : item.tone.color }

    /// Its picture or symbol beside it, its name over the bar and the value at the end.
    private func pictured(_ item: ExtensionPage.Bar) -> some View {
        HStack(spacing: Theme.Space.m) {
            Group {
                if let picture = item.picture {
                    PagePictureView(picture: picture, model: model, side: 64, fill: false)
                } else if let symbol = item.symbol {
                    Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Theme.inkMuted)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(ext: item.label).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                PageMeter(fraction: item.fraction, color: color(item), track: well ?? Theme.surfaceSunken, height: 6)
            }
            Text(ext: item.value).font(Theme.Font.body).foregroundStyle(Theme.ink).monospacedDigit().frame(minWidth: 36, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            if !bars.title.isEmpty { CardTitle(title: bars.title, caption: bars.caption) }
            else if let caption = bars.caption { Text(ext: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true) }
            if bars.items.isEmpty {
                Text("Nothing to show right now.", comment: "An extension page's list of bars is empty")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkFaint)
            }
            ForEach(Array(bars.items.enumerated()), id: \.offset) { _, item in
                if item.picture != nil || item.symbol != nil { pictured(item) } else { VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(ext: item.label).font(Theme.Font.body).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: Theme.Space.s)
                        Text(ext: item.value).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted).monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(well ?? Theme.surfaceSunken)
                            Capsule().fill(color(item))
                                .frame(width: max(4, geo.size.width * item.fraction))
                        }
                    }
                    .frame(height: 6)
                }
                .accessibilityElement(children: .combine) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(flat ? 0 : Theme.Space.m)
        .cardSurface()
    }
}

private struct FactsCard: View {
    var facts: ExtensionPage.Facts
    @Environment(\.pixelLength) private var pixel
    @Environment(\.pageFlat) private var flat

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let title = facts.title { CardTitle(title: title) }
            VStack(spacing: 0) {
                ForEach(Array(facts.items.enumerated()), id: \.offset) { i, fact in
                    if i > 0 { Rectangle().fill(Theme.line).frame(height: pixel * 2) }
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                        Text(ext: fact.label).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                        Spacer(minLength: Theme.Space.s)
                        Text(ext: fact.value).font(Theme.Font.body).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 7)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(flat ? 0 : Theme.Space.m)
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
    @Environment(\.pageFlat) private var flat

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            if let symbol = control.symbol { Image(systemName: symbol).foregroundStyle(Theme.inkMuted).frame(width: 20) }
            VStack(alignment: .leading, spacing: 2) {
                Text(ext: control.label).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                if let detail = control.detail {
                    Text(ext: detail).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.m)
            Toggle(isOn: Binding(get: { pending ?? isOn }, set: { on in
                pending = on
                Task {
                    await model.run(control, on: on)
                    pending = nil
                }
            })) { Text(ext: control.label) }
                .toggleStyle(.switch).labelsHidden()
                .disabled(pending != nil)
        }
        .padding(.horizontal, flat ? 0 : Theme.Space.l)
        .padding(.vertical, Theme.Space.s + 2)
    }

    private var isOn: Bool { if case .toggle(let on) = control.kind { on } else { false } }
}

// MARK: What Sidefolk does for it

/// The palette's shortcut, changeable here, and Accessibility when the extension pastes or keeps the person active:
/// Sidefolk's own part of the page, not the extension's (D63).
struct HostControls: View {
    var model: ExtensionPageModel
    /// Only what it needs from macOS: its palettes' row is drawn elsewhere on this page.
    var quiet = false
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if !model.palettes.isEmpty, !quiet {
                RowsCard {
                    ForEach(model.palettes) { p in PaletteSettingsRow(info: p) }
                }
            }
            if model.info.needsAccessibility, !trusted {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Image(systemName: "hand.raised.fill").foregroundStyle(Theme.warning)
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
                .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous))
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
struct HeadsUps: View {
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
                            Text(ext: alert.kind.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                            if !alert.kind.description.isEmpty {
                                Text(ext: alert.kind.description).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: Theme.Space.m)
                        Toggle(isOn: Binding(get: { alert.watcherId != nil }, set: { on in Task { await model.setAlert(alert, on: on) } })) {
                            Text(ext: alert.kind.title)
                        }
                        .toggleStyle(.switch).labelsHidden()
                    }
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.s + 2)
                }
            }
            if let problem = model.alertProblem {
                Text(ext: problem).font(Theme.Font.caption).foregroundStyle(Theme.danger)
            }
        }
    }
}
