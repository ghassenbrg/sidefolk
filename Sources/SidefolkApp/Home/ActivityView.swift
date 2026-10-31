import SidefolkCore
import SwiftUI

/// Home › Activity: the audit log of everything Sidefolk did, who asked and what Guard decided.
struct ActivityView: View {
    @Bindable var model: ActivityModel
    /// The row the keyboard is on: ↑↓ move, Space opens or closes its details.
    @FocusState private var focused: String?

    /// The theme's Activity (D64): a table, or a log (dense, in mono, a word for each result).
    private var style: ThemeLayout.Activity { ThemeStore.shared.style.tokens.layout.activity }
    private var columns: [ActivityColumn] { style == .log ? [.time, .who, .what, .risk, .decision] : ActivityColumn.allCases }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if style == .log || style == .diary {
                HStack(alignment: .firstTextBaseline) {
                    Text("Activity").font(Theme.Font.heading).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                    if style == .diary {
                        Text("what was done, who asked, what you allowed").font(.system(size: 14, design: .serif)).italic()
                            .foregroundStyle(Theme.inkMuted)
                    }
                    Spacer()
                    filters
                }
            } else {
                PageTitle(title: "Activity", subtitle: "Everything Sidefolk did, who asked, and what was allowed.")
                stats
                filters
            }
            if let message = model.undoMessage {
                Text(verbatim: message).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            if style == .diary { diary } else { table }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.xl)
        .padding(.bottom, Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surfaceSunken)
    }

    private var stats: some View {
        HStack(spacing: Theme.Space.m) {
            Stat(title: "Agent runs this week", value: model.weekRuns.formatted(), folk: "byte")
            Stat(title: "Tokens this week", value: tokens, folk: "byte")
            Stat(title: "Actions this week", value: model.weekActions.formatted(), folk: "guard")
        }
    }

    private var tokens: String {
        let fmt: (Int) -> String = { $0.formatted(.number.notation(.compactName)) }
        return String(localized: "\(fmt(model.weekInputTokens)) in · \(fmt(model.weekOutputTokens)) out",
                      comment: "Tokens sent to and received from the AI this week: “12K in · 3K out”")
    }

    private var filters: some View {
        HStack(spacing: Theme.Space.m) {
            Picker("Show", selection: $model.show) {
                Text("All").tag(ActivityModel.Show.all)
                Text(model.attentionCount > 0 ? "Needs attention (\(model.attentionCount))" : "Needs attention")
                    .tag(ActivityModel.Show.needsAttention)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            Picker("From", selection: $model.callerKind) {
                Text("Everyone").tag(String?.none)
                Divider()
                ForEach(ActivityModel.callerKinds, id: \.kind) { k in Text(k.title).tag(Optional(k.kind)) }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    @ViewBuilder private var table: some View {
        let rows = model.visible
        if rows.isEmpty {
            VStack {
                Spacer()
                if model.entries.isEmpty {
                    EmptyState(title: "Nothing yet", message: "Everything Sidefolk does, and who asked for it, shows up here.",
                               systemImage: "list.bullet.rectangle", folk: "guard")
                } else {
                    EmptyState(title: "Nothing to show", message: "No activity matches these filters.", systemImage: "line.3.horizontal.decrease.circle",
                               folk: "scout")
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cardSurface()
        } else {
            VStack(spacing: 0) {
                ActivityRow(header: true, columns: columns, log: style == .log) { _ in EmptyView() }
                Rectangle().fill(Theme.line).frame(height: 1)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows, id: \.rowKey) { e in
                            let open = e.id != nil && model.openId == e.id
                            ActivityRow(columns: columns, log: style == .log) { column in
                                if style == .log { logCell(column, e) } else { cell(column, e, open: open) }
                            }
                                .background(focused == e.rowKey ? Theme.accentSoft : open ? Theme.surfaceSunken : .clear)
                                .contentShape(Rectangle())
                                .onTapGesture { model.toggle(e) }
                                .focusable()
                                .focusEffectDisabled()
                                .focused($focused, equals: e.rowKey)
                                .onKeyPress(.space) { model.toggle(e); return .handled }
                                .onKeyPress(.upArrow) { move(-1, from: e, in: rows); return .handled }
                                .onKeyPress(.downArrow) { move(1, from: e, in: rows); return .handled }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHint(Text("Shows or hides the details"))
                            if open {
                                ActivityDetails(entry: e, who: Describe.caller(e.caller, companion: model.companionName),
                                                askedIn: e.runId.flatMap { model.conversations[$0] },
                                                open: { model.services.openConversation($0) },
                                                seeRule: e.decision == .always ? { model.services.openSettings(tab: .privacy) } : nil)
                            }
                            Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, Theme.Space.l)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(Theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .cardSurface()
        }
    }

    /// The same facts as sentences, under the time of day they happened (D64); a click opens the same details.
    @ViewBuilder private var diary: some View {
        let rows = model.visible
        if rows.isEmpty {
            table
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.days(rows), id: \.title) { part in
                        Text(verbatim: part.title).font(.system(size: 17, design: .serif)).italic().foregroundStyle(Theme.ink)
                            .padding(.top, Theme.Space.l).padding(.bottom, Theme.Space.xs)
                        ForEach(part.entries, id: \.rowKey) { e in
                            let open = e.id != nil && model.openId == e.id
                            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                                Text(verbatim: TimeFormat.clock(e.at, calendar: .current)).font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.inkFaint).frame(width: 44, alignment: .leading)
                                (Text(verbatim: Describe.caller(e.caller, companion: model.companionName)).fontWeight(.semibold)
                                 + Text(verbatim: " · \(e.summary). ")
                                 + Text(verbatim: Describe.decision(e.decision)).italic().foregroundColor(Theme.inkMuted))
                                    .font(.system(size: 14, design: .serif)).foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: Theme.Space.s)
                                if let risk = Risk(rawValue: e.risk) { Stamp(risk: risk) }
                            }
                            .padding(.vertical, Theme.Space.s)
                            .contentShape(Rectangle())
                            .onTapGesture { model.toggle(e) }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            if open {
                                ActivityDetails(entry: e, who: Describe.caller(e.caller, companion: model.companionName),
                                                askedIn: e.runId.flatMap { model.conversations[$0] },
                                                open: { model.services.openConversation($0) },
                                                seeRule: e.decision == .always ? { model.services.openSettings(tab: .privacy) } : nil)
                            }
                            Rectangle().fill(Theme.line).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.xl)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .cardSurface()
        }
    }

    /// Rows under "This evening", "This afternoon", "Yesterday" or their date, newest first.
    static func days(_ rows: [ActivityEntry], now: Date = Date()) -> [(title: String, entries: [ActivityEntry])] {
        let cal = Calendar.current
        func title(_ date: Date) -> String {
            if cal.isDate(date, inSameDayAs: now) {
                switch cal.component(.hour, from: date) {
                case 5..<12: return String(localized: "This morning")
                case 12..<18: return String(localized: "This afternoon")
                case 18..<24: return String(localized: "This evening")
                default: return String(localized: "Last night")
                }
            }
            if cal.isDateInYesterday(date) { return String(localized: "Yesterday") }
            return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        var parts: [(title: String, entries: [ActivityEntry])] = []
        for row in rows {
            let t = title(row.at)
            if parts.last?.title == t { parts[parts.count - 1].entries.append(row) } else { parts.append((t, [row])) }
        }
        return parts
    }

    private func move(_ step: Int, from e: ActivityEntry, in rows: [ActivityEntry]) {
        guard let i = rows.firstIndex(where: { $0.rowKey == e.rowKey }) else { return }
        focused = rows[min(max(i + step, 0), rows.count - 1)].rowKey
    }

    @ViewBuilder private func cell(_ column: ActivityColumn, _ e: ActivityEntry, open: Bool) -> some View {
        switch column {
        case .time:
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .accessibilityHidden(true)
                Text(TimeText.short(e.at)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
        case .who:
            Text(verbatim: Describe.caller(e.caller, companion: model.companionName)).font(Theme.Font.body).foregroundStyle(Theme.ink)
        case .what:
            Text(e.summary).font(Theme.Font.body).foregroundStyle(Theme.ink).help(e.summary)
        case .risk:
            riskChip(e.risk)
        case .decision:
            decisionChip(e.decision)
        case .outcome:
            HStack(spacing: 6) {
                outcome(e)
                // The same Undo the Ask panel offers, whatever mode it ran in (D37).
                if let row = e.id, model.undoable.contains(row) {
                    Spacer(minLength: 0)
                    Button("Undo") { Task { await model.undo(e) } }.buttonStyle(.sf(.secondary)).fixedSize()
                        .accessibilityLabel(Text("Undo “\(e.summary)”"))
                }
            }
        }
    }

    /// A log's cell: exact words in mono, the risk as a tag, and the result as one coloured word.
    @ViewBuilder private func logCell(_ column: ActivityColumn, _ e: ActivityEntry) -> some View {
        switch column {
        case .time: Text(verbatim: TimeFormat.clock(e.at, calendar: .current)).foregroundStyle(Theme.inkMuted)
        case .who: Text(verbatim: Describe.caller(e.caller, companion: model.companionName))
            .foregroundStyle(e.caller.hasPrefix("external:") ? Theme.link : Theme.ink)
        case .what: Text(verbatim: "\(e.tool.replacingOccurrences(of: ".", with: "_")) \(e.summary)").foregroundStyle(Theme.ink).help(e.summary)
        case .risk: RiskTag(risk: e.risk)
        case .decision, .outcome: result(e)
        }
    }

    private func result(_ e: ActivityEntry) -> some View {
        let (word, color): (String, Color) = switch e.decision {
        case .denied: (String(localized: "denied", comment: "A log's result: you said no"), Theme.danger)
        case .blocked: (String(localized: "blocked", comment: "A log's result: rules don't allow it"), Theme.danger)
        case .failed: (String(localized: "failed", comment: "A log's result"), Theme.danger)
        case .skipped: (String(localized: "skipped", comment: "A log's result: nobody answered in time"), Theme.link)
        case .auto, .autoMode, .fullAccess, .autoModePaired, .fullAccessPaired, .webSetting: (String(localized: "auto", comment: "A log's result: done without asking"), Theme.inkMuted)
        case .allowed, .always: (e.outcome?.clipped(24) ?? String(localized: "allowed", comment: "A log's result"), Theme.success)
        }
        return Text(verbatim: word).foregroundStyle(color).help(e.outcome ?? e.error ?? word)
    }

    @ViewBuilder private func riskChip(_ risk: String) -> some View {
        switch Risk(rawValue: risk) {
        case .low: Chip("Low", tone: .neutral)
        case .medium: Chip("Medium", tone: .warning)
        case .high: Chip("High", tone: .danger)
        case nil: Chip(verbatim: risk.capitalized, tone: .neutral)
        }
    }

    @ViewBuilder private func decisionChip(_ d: ActivityEntry.Decision) -> some View {
        switch d {
        case .auto: Chip("Automatic", tone: .neutral)
        case .allowed: Chip("Allowed", tone: .accent, systemImage: "checkmark")
        case .always: Chip("Always", tone: .accent, systemImage: "checkmark.circle")
        case .denied: Chip("Denied", tone: .danger, systemImage: "hand.raised")
        case .blocked: Chip("Blocked", tone: .danger, systemImage: "nosign")
        case .failed: Chip("Failed", tone: .danger, systemImage: "exclamationmark.triangle")
        // Done without asking: the mode answered for the person (D37), so it never looks like they did.
        case .autoMode: Chip("Auto", tone: .accent, systemImage: "bolt")
        case .fullAccess: Chip("Full access", tone: .warning, systemImage: "bolt.fill")
        // After outside content, only because the call reached nothing but a device the person paired (D72): the
        // mode's icon and tone, and the details name the mode.
        case .autoModePaired: Chip("Paired device", tone: .accent, systemImage: "bolt")
        case .fullAccessPaired: Chip("Paired device", tone: .warning, systemImage: "bolt.fill")
        case .skipped: Chip("Skipped", tone: .warning, systemImage: "clock.badge.xmark")
        // Read or used without a card because the person chose not to be asked before reading the web (D47).
        case .webSetting: Chip("Web setting", tone: .accent, systemImage: "globe")
        }
    }

    @ViewBuilder private func outcome(_ e: ActivityEntry) -> some View {
        if let error = e.error {
            Text(error).font(Theme.Font.caption).foregroundStyle(Theme.danger).help(error)
        } else if let outcome = e.outcome {
            Text(outcome).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).help(outcome)
        } else {
            Text("—").font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).accessibilityLabel("No outcome")
        }
    }
}

/// A row's details, opened in place: everything the columns cut, how it was allowed, and its arguments.
private struct ActivityDetails: View {
    var entry: ActivityEntry
    var who: String
    /// The conversation whose run did it, while that conversation is kept.
    var askedIn: ConversationSummary?
    var open: (String) -> Void
    /// Opens the rule in Settings, for something an "Always allow" let through.
    var seeRule: (() -> Void)?

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Theme.Space.m, verticalSpacing: Theme.Space.s) {
            line("What") { Text(entry.summary).font(Theme.Font.bodyStrong) }
            line("Who") { Text(verbatim: who) }
            if let askedIn {
                line("Asked in") { ConversationLink(conversation: askedIn) { open(askedIn.id) } }
            }
            line("Decision") {
                HStack(spacing: Theme.Space.s) {
                    Text(verbatim: Describe.decision(entry.decision))
                    if let seeRule {
                        Button("See the rule in Settings…", action: seeRule).buttonStyle(.sf(.plain))
                    }
                }
            }
            if let error = entry.error {
                line("Outcome") { Text(error).foregroundStyle(Theme.danger) }
            } else if let outcome = entry.outcome {
                line("Outcome") { Text(outcome) }
            }
            ForEach(Describe.arguments(entry.args), id: \.name) { argument in
                GridRow {
                    Text(verbatim: argument.name).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.inkFaint)
                    Text(verbatim: argument.value).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }
            }
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                Text(verbatim: entry.tool).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkFaint)
            }
        }
        .font(Theme.Font.body)
        .foregroundStyle(Theme.ink)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Theme.Space.l + 13)
        .padding(.trailing, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .background(Theme.surfaceSunken)
        .accessibilityElement(children: .contain)
    }

    private func line(_ label: LocalizedStringKey, @ViewBuilder _ value: () -> some View) -> some View {
        GridRow {
            Eyebrow(Text(label)).gridColumnAlignment(.trailing)
            value().fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The table's columns: fixed widths for short values; what happened and how it ended share the rest.
private enum ActivityColumn: CaseIterable {
    case time, who, what, risk, decision, outcome

    var title: LocalizedStringKey {
        switch self {
        case .time: "Time"
        case .who: "Who"
        case .what: "What"
        case .risk: "Risk"
        case .decision: "Decision"
        case .outcome: "Outcome"
        }
    }

    var width: CGFloat? {
        switch self {
        case .time: 96
        case .who: 100
        case .risk: 72
        case .decision: 104
        case .what, .outcome: nil
        }
    }

    /// Flexible columns may shrink this far in a narrow window (they truncate; full text is in the tooltip).
    var minWidth: CGFloat {
        switch self {
        case .what: 72
        case .outcome: 40
        default: width ?? 0
        }
    }
}

/// One line of the table (or its header): the same column frames every time, so columns line up.
private struct ActivityRow<Cell: View>: View {
    var header = false
    var columns = ActivityColumn.allCases
    /// A log's row: mono, and the decision column says the result.
    var log = false
    @ViewBuilder var cell: (ActivityColumn) -> Cell

    var body: some View {
        HStack(spacing: Theme.Space.s + 2) {
            ForEach(columns, id: \.self) { column in
                Group {
                    if header {
                        Eyebrow(Text(log && column == .decision ? "Result" : column.title))
                    } else {
                        cell(column).font(log ? .system(size: 12, design: .monospaced) : nil)
                    }
                }
                .lineLimit(1)
                // Fixed columns shrink a longer word a little before cutting it.
                .minimumScaleFactor(column.width == nil ? 1 : 0.8)
                .frame(minWidth: column.minWidth, maxWidth: column.width ?? .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, header ? Theme.Space.s + 2 : Theme.Space.s + 1)
        .accessibilityAddTraits(header ? .isHeader : [])
    }
}

private extension ActivityEntry {
    /// Stored rows always have an id; the fallback keeps the list stable regardless.
    var rowKey: String { id.map(String.init) ?? "\(at.timeIntervalSince1970)-\(tool)" }
}

private struct Stat: View {
    var title: LocalizedStringKey
    var value: String
    var folk: String

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            FolkBadge(name: folk, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                // German doesn't shorten thousands (“218.400 gesendet · 28.080 empfangen”), so leave it room to shrink.
                Text(value).font(Theme.Font.heading).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.6)
                Text(title).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted).lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

/// A risk stamped in small capitals, as on a page (D64).
struct Stamp: View {
    var risk: Risk

    var body: some View {
        let color = risk == .high ? Theme.danger : risk == .medium ? Theme.link : Theme.success
        Text(verbatim: risk == .high ? String(localized: "risk.high", defaultValue: "high", comment: "High risk, in a narrow column")
             : risk == .medium ? String(localized: "medium", comment: "A risk stamp") : String(localized: "risk.low", defaultValue: "low", comment: "Low risk, in a narrow column"))
            .textCase(.uppercase).font(.system(size: 9.5, weight: .heavy)).kerning(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(color, lineWidth: 1.2))
            .rotationEffect(.degrees(-2))
    }
}
