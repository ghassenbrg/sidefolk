import AppKit
import KeyboardShortcuts
import SidefolkCore
import SwiftUI

// A page composed like an app's screen (its model is ExtensionPage+Compose): sections as cards, side by side or joined, and the parts that live in them. Sidefolk's
// drawing; the words and colours are the extension's, and every click runs one of its own tools as the person, through Guard.

extension EnvironmentValues {
    /// Inside a section's card: the parts lose their own card and margins.
    @Entry var pageFlat = false
    /// What's written on a filled button in the page's accent.
    @Entry var pageAccentWords: Color = .white
    /// Soft wells on a dressed page's cards.
    @Entry var pageWell: Color?
}

extension PageDress.Pair {
    func color(_ scheme: ColorScheme) -> Color? { Color(extensionHex: scheme == .dark ? dark : light) }

    /// Near-black on what is too light to hold white at 4.5:1 (the same line as a page's accent).
    func words(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? darkHoldsWhite : lightHoldsWhite) ? .white : .black
    }
}

/// Sections side by side, sharing the width by weight and the height of the tallest; below `minimumWide`, one under another.
struct WeightedRow: Layout {
    var weights: [Double]
    var spacing: CGFloat
    var minimumWide: CGFloat = 760

    private func widths(_ total: CGFloat) -> [CGFloat]? {
        guard total >= minimumWide, weights.count > 1 else { return nil }
        // None so small it can't be read, whatever the page says.
        let least = weights.reduce(0, +) * 0.2
        let shares = weights.map { max($0, least) }
        let room = total - spacing * CGFloat(weights.count - 1), sum = shares.reduce(0, +)
        return shares.map { room * CGFloat($0 / sum) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 900
        if let widths = widths(width) {
            let tallest = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
            return CGSize(width: width, height: tallest)
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if let widths = widths(bounds.width) {
            // Laid out start to end; SwiftUI mirrors it right to left.
            var x = bounds.minX
            for (view, width) in zip(subviews, widths) {
                view.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
                x += width + spacing
            }
        } else {
            var y = bounds.minY
            for view in subviews {
                let height = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
                view.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
                y += height + spacing
            }
        }
    }
}

/// A run of sections in one `row`, apart or joined in one card.
struct PageRowView: View {
    var sections: [ExtensionPage.Section]
    var model: ExtensionPageModel
    @State private var width: CGFloat = 0
    private var minimumWide: CGFloat { 760 }
    private var joined: Bool { sections.first?.joined == true }

    var body: some View {
        if joined {
            WeightedRow(weights: sections.map(\.weight), spacing: 0, minimumWide: minimumWide) {
                ForEach(Array(sections.enumerated()), id: \.offset) { i, section in
                    SectionView(section: section, model: model)
                        .padding(Theme.Space.l)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .overlay(alignment: width >= minimumWide ? .leading : .top) {
                            if i > 0 {
                                if width >= minimumWide { Rectangle().fill(Theme.line).frame(width: 1) } else { Rectangle().fill(Theme.line).frame(height: 1) }
                            }
                        }
                }
            }
            .environment(\.pageFlat, true)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .cardSurface()
        } else {
            WeightedRow(weights: sections.map(\.weight), spacing: Theme.Space.l, minimumWide: minimumWide) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    SectionView(section: section, model: model)
                }
            }
        }
    }
}

// MARK: A number on a card

struct PageMetricView: View {
    var metric: ExtensionPage.Metric
    var model: ExtensionPageModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.pageSelected) private var selected
    @Environment(\.pageWell) private var well

    /// A warning keeps its meaning over any colour of the page's.
    private var color: Color {
        if metric.tone == .warn || metric.tone == .bad { return metric.tone.color }
        return metric.tint?.color(scheme) ?? (metric.tone == .neutral ? selected ?? Theme.accent : metric.tone.color)
    }

    /// The bar and the line are the page's own colour, whatever the symbol wears, unless something is wrong.
    private var fill: Color {
        metric.tone == .warn || metric.tone == .bad ? metric.tone.color : selected ?? color
    }

    var body: some View {
        Group {
            switch metric.size {
            case .large: large
            case .small: small
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Theme.Space.m)
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(ext: [metric.label, metric.value, metric.caption].compactMap { $0 }.joined(separator: ", ")))
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                if let symbol = metric.symbol {
                    Image(systemName: symbol).font(.system(size: 24, weight: .regular)).foregroundStyle(color).frame(width: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(ext: metric.label).font(Theme.Font.body).foregroundStyle(Theme.inkMuted).lineLimit(1)
                    Text(ext: metric.value).font(.system(size: 25, weight: .semibold)).foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.65).monospacedDigit()
                    if metric.fraction == nil, metric.spark == nil, let caption = metric.caption {
                        Text(ext: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2).padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            if let spark = metric.spark {
                PageSparkline(points: model.points(chart: spark.chart, series: spark.series), color: fill).frame(height: 24)
            } else if let fraction = metric.fraction {
                PageMeter(fraction: fraction, color: fill, track: well ?? Theme.surfaceSunken)
            }
            if metric.fraction != nil || metric.spark != nil, let caption = metric.caption {
                Text(ext: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var small: some View {
        HStack(spacing: Theme.Space.m) {
            if let symbol = metric.symbol {
                Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(color).frame(width: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ext: metric.label).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1)
                Text(ext: metric.value).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.7).monospacedDigit()
                if let caption = metric.caption { Text(ext: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
        }
    }
}

/// A capsule filled to a fraction.
struct PageMeter: View {
    var fraction: Double
    var color: Color
    var track: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color).frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

/// The past of a value as a small line, its own scale. Time runs left to right in every language.
struct PageSparkline: View {
    var points: [ExtensionPageHistory.Point]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let values = points.suffix(120).map(\.v)
            let top = max(values.max() ?? 1, 0.0001) * 1.15
            let step = geo.size.width / CGFloat(max(1, values.count - 1))
            let at = { (i: Int) in CGPoint(x: CGFloat(i) * step, y: geo.size.height * (1 - CGFloat(values[i] / top))) }
            if values.count > 1 {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height))
                    for i in values.indices { p.addLine(to: at(i)) }
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(color.opacity(0.12))
                Path { p in
                    p.move(to: at(0))
                    for i in values.indices.dropFirst() { p.addLine(to: at(i)) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            } else {
                Rectangle().fill(color.opacity(0.25)).frame(height: 1).frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

// MARK: Inside a card

struct PageHeadingView: View {
    var heading: ExtensionPage.Heading

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if heading.rule { Rectangle().fill(Theme.line).frame(height: 1) }
            Text(ext: heading.title).font(Theme.Font.heading).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
        }
    }
}

/// Questions as rows across the width: each sends its sentence to Ask, as if typed.
struct PageAskRows: View {
    var asks: [ExtensionPage.Ask]
    var model: ExtensionPageModel
    @Environment(\.pageWell) private var well

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            ForEach(Array(asks.enumerated()), id: \.offset) { _, ask in
                Button { model.ask(ask.ask) } label: {
                    HStack(spacing: Theme.Space.m) {
                        if let symbol = ask.symbol {
                            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Theme.inkMuted).frame(width: 36, height: 34)
                                .background(well ?? Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        Text(ext: ask.label).font(Theme.Font.body).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                        Spacer(minLength: Theme.Space.s)
                        Image(systemName: "chevron.forward").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    }
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, ask.symbol == nil ? Theme.Space.s + 2 : Theme.Space.xs + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control + 2, style: .continuous).strokeBorder(Theme.line))
                }
                .buttonStyle(.sfBare)
                .help(Text(ext: ask.ask))
            }
        }
    }
}

/// The extension's heads-ups where the page puts them: the ones it names first, the rest behind its own words.
struct PagePlacedHeadsUps: View {
    var part: ExtensionPage.HeadsUpsPart
    var model: ExtensionPageModel
    @State private var all = false

    private var shown: [ExtensionPageModel.Alert] {
        // A page can put some first, but not hide one that's on, or leave no way to the rest.
        if all || part.show.isEmpty || part.more == nil { return model.alerts }
        return model.alerts.filter { part.show.contains($0.kind.watcher) || $0.watcherId != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if all || part.show.isEmpty {
                Text("Switch one on and your companion tells you when it happens. Each checks every five minutes.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, alert in
                    if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    HStack(spacing: Theme.Space.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ext: alert.kind.title).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink)
                            if !alert.kind.description.isEmpty {
                                Text(ext: alert.kind.description).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: Theme.Space.m)
                        Toggle(isOn: Binding(get: { alert.watcherId != nil }, set: { on in Task { await model.setAlert(alert, on: on) } })) { Text(ext: alert.kind.title) }
                            .toggleStyle(.switch).labelsHidden()
                    }
                    .padding(.vertical, Theme.Space.s)
                }
            }
            if let problem = model.alertProblem { Text(ext: problem).font(Theme.Font.caption).foregroundStyle(Theme.danger) }
            if shown.count < model.alerts.count || all, let more = all ? part.less ?? part.more : part.more {
                Button { withAnimation(Theme.Motion.ease(0.18)) { all.toggle() } } label: {
                    HStack(spacing: 4) {
                        Text(ext: more)
                        Image(systemName: all ? "chevron.up" : "chevron.forward").font(.system(size: 10, weight: .semibold))
                    }
                    .font(Theme.Font.body).foregroundStyle(Theme.link).contentShape(Rectangle())
                }
                .buttonStyle(.sfBare)
                .accessibilityValue(all ? Text("Unfolded", comment: "Spoken state of a section of an extension page that folds: open now")
                                        : Text("Folded", comment: "Spoken state of a section of an extension page that folds: closed now"))
            }
        }
    }
}

// MARK: One thing, whole

struct PagePreviewView: View {
    var preview: ExtensionPage.Preview
    var model: ExtensionPageModel
    @Environment(\.pageSelected) private var accent
    @Environment(\.colorScheme) private var scheme
    private var selection: PageSelection { PageSelection(accent: accent, dark: scheme == .dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let empty = preview.empty {
                Text(ext: empty).font(Theme.Font.body).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                head
                content
            }
            if preview.footer != nil || !preview.actions.isEmpty { foot }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var head: some View {
        if let kind = preview.kind {
            HStack(spacing: 6) {
                if let symbol = preview.kindSymbol { Image(systemName: symbol) }
                Text(ext: kind)
            }
            .font(Theme.Font.captionStrong).foregroundStyle(selection.ink)
            .padding(.horizontal, Theme.Space.s).padding(.vertical, 5)
            .background(selection.soft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        if let title = preview.title {
            Text(ext: title).font(Theme.Font.title2).foregroundStyle(Theme.ink).lineLimit(3).accessibilityAddTraits(.isHeader)
        }
        Rectangle().fill(Theme.line).frame(height: 1)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if let image = preview.image, let folder = model.folder {
                    ExtensionPictureView(name: image, folder: folder, pixels: 1000, limit: ExtensionDataFile.previewLimit, fill: false)
                        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 320)
                }
                if let color = preview.color.flatMap(Color.init(extensionHex:)) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color).frame(height: 120)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
                }
                if let text = preview.text {
                    Text(ext: text).font(preview.code ? .system(size: 13, design: .monospaced) : Theme.Font.body).foregroundStyle(Theme.ink)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(preview.facts.enumerated()), id: \.offset) { _, fact in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                        Text(ext: fact.label).font(Theme.Font.body).foregroundStyle(Theme.inkMuted)
                        Spacer(minLength: Theme.Space.s)
                        Text(ext: fact.value).font(Theme.Font.body).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing).textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var foot: some View {
        VStack(spacing: Theme.Space.m) {
            Rectangle().fill(Theme.line).frame(height: 1)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.s) {
                    footer
                    Spacer(minLength: Theme.Space.m)
                    actions
                }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    footer
                    actions
                }
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if let footer = preview.footer { Text(ext: footer).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(2) }
    }

    private var actions: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(Array(preview.actions.enumerated()), id: \.offset) { _, control in PageButton(control: control, model: model) }
        }
    }
}

// MARK: A plain hero

/// What the page is about right now, across it as one of its cards: a ring or a symbol, a line under the title's side, its states, and the actions at the end.
struct PageHeroStrip: View {
    var hero: ExtensionPage.Hero
    var model: ExtensionPageModel
    @Environment(\.pageFlat) private var flat
    @Environment(\.pageSelected) private var selected
    @Environment(\.pageWell) private var well
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var width: CGFloat = 1000

    var body: some View {
        Group {
            if flat { content } else { content.padding(Theme.Space.l).cardSurface() }
        }
        .accessibilityElement(children: .contain)
    }

    /// Across the card when there's room for the words to wrap beside it all, its actions under them when there isn't, and one under another in a narrow window.
    private var content: some View {
        Group {
            if width >= 640 {
                HStack(alignment: .center, spacing: Theme.Space.l) {
                    lead
                    words.frame(maxWidth: .infinity, alignment: .leading)
                    actions.fixedSize()
                }
            } else if width >= 420 {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack(alignment: .center, spacing: Theme.Space.l) {
                        lead
                        words.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    actions
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    lead
                    words
                    actions
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    @ViewBuilder private var lead: some View {
        if let ring = hero.ring {
            HStack(spacing: Theme.Space.l) {
                ringView(ring)
                Rectangle().fill(Theme.line).frame(width: 1, height: 104)
            }
        } else if let symbol = hero.symbol {
            Image(systemName: symbol).font(.system(size: 26, weight: .medium))
                .foregroundStyle(tone)
                .frame(width: 60, height: 60)
                .background(hero.tone == .neutral ? well ?? Theme.surfaceSunken : hero.tone.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var tone: Color { hero.tone == .neutral ? selected ?? Theme.accent : hero.tone.color }
    /// Time left is the page's own colour unless something is wrong.
    private var ringColor: Color { hero.tone == .warn || hero.tone == .bad ? hero.tone.color : selected ?? Theme.accent }

    private func ringView(_ ring: ExtensionPage.Ring) -> some View {
        ZStack {
            Circle().stroke(well ?? Theme.surfaceSunken, lineWidth: 9)
            Circle().trim(from: 0, to: max(0.004, ring.fraction))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(still ? nil : Theme.Motion.spring(0.5), value: ring.fraction)
            VStack(spacing: 2) {
                Text(ext: ring.value).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.6).monospacedDigit()
                if let caption = ring.caption { Text(ext: caption).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1) }
            }
            .padding(.horizontal, 16)
        }
        .frame(width: 122, height: 122)
        .accessibilityElement(children: .combine)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if hero.eyebrow != nil || hero.busy {
                HStack(spacing: 6) {
                    if hero.busy { ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12) }
                    if let eyebrow = hero.eyebrow {
                        Text(ext: eyebrow).font(Theme.Font.captionStrong).foregroundStyle(hero.tone == .neutral ? Theme.inkMuted : hero.tone.color)
                    }
                }
            }
            Text(ext: hero.title).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            if let detail = hero.detail {
                Text(ext: detail).font(Theme.Font.body).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            if let code = hero.code {
                Text(ext: code).font(.system(size: 42, weight: .semibold, design: .monospaced)).tracking(4).foregroundStyle(Theme.ink)
                    .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                    .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .textSelection(.enabled)
            }
            if !hero.chips.isEmpty {
                FlowRow(spacing: Theme.Space.s) {
                    ForEach(Array(hero.chips.enumerated()), id: \.offset) { _, chip in
                        HStack(spacing: 6) {
                            if let symbol = chip.symbol { Image(systemName: symbol) }
                            Text(ext: chip.label)
                        }
                        .font(Theme.Font.caption.weight(.medium))
                        .foregroundStyle(chip.tone == .neutral ? Theme.inkMuted : chip.tone.color)
                        .padding(.horizontal, Theme.Space.s + 2).padding(.vertical, 6)
                        .background(chip.tone == .neutral ? Theme.surfaceSunken : chip.tone.soft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
            if !hero.facts.isEmpty {
                FlowRow(spacing: Theme.Space.l) {
                    ForEach(Array(hero.facts.enumerated()), id: \.offset) { _, fact in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ext: fact.value).font(Theme.Font.bodyStrong).foregroundStyle(Theme.ink).monospacedDigit()
                            Text(ext: fact.label).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var actions: some View {
        FlowRow(spacing: Theme.Space.s) {
            ForEach(Array(hero.actions.enumerated()), id: \.offset) { _, control in
                PageButton(control: control, model: model, leads: !(model.page?.hasPrimary ?? true), full: true)
            }
        }
    }
}

/// The chart window in a card: 10 min, 1 hour or 24 hours, the pick tinted.
struct PageWindowPills: View {
    var model: ExtensionPageModel
    @Environment(\.pageSelected) private var accent
    @Environment(\.colorScheme) private var scheme
    private var selection: PageSelection { PageSelection(accent: accent, dark: scheme == .dark) }

    private var windows: [(ExtensionPageModel.Window, Text)] {
        [(.tenMinutes, Text("10 min", comment: "Chart window: the last ten minutes")), (.hour, Text("1 hour", comment: "Chart window: the last hour")),
         (.day, Text("24 hours", comment: "Chart window: the last day"))]
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(windows, id: \.0) { window, label in
                let on = model.window == window
                Button { model.window = window } label: {
                    label.font(Theme.Font.caption.weight(.medium)).foregroundStyle(on ? selection.ink : Theme.inkMuted)
                        .padding(.horizontal, Theme.Space.s + 2).frame(minHeight: 26)
                        .background(on ? selection.soft : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.sfBare)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Chart window", comment: "What the 10 min / 1 hour / 24 hours choice above a chart is, read by VoiceOver"))
    }
}

// MARK: A shortcut on a button

/// The shortcut a palette opens with, as the person set it.
struct PageShortcutCap: View {
    var palette: String
    var model: ExtensionPageModel

    var body: some View {
        if let info = model.palettes.first(where: { $0.palette == palette }), let shortcut = KeyboardShortcuts.getShortcut(for: PaletteController.shortcutName(info)) {
            Text(verbatim: shortcut.description)
                .font(Theme.Font.caption.weight(.medium)).foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}
