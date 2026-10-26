import SidefolkCore
import SwiftUI

/// Home › Activity: the audit log of everything Sidefolk did, who asked and what Guard decided.
struct ActivityView: View {
    @Bindable var model: ActivityModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            PageTitle(title: "Activity", subtitle: "Everything Sidefolk did, who asked, and what was allowed.")
            stats
            filters
            if let message = model.undoMessage {
                Text(verbatim: message).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            }
            table
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
                ActivityRow(header: true) { _ in EmptyView() }
                Rectangle().fill(Theme.line).frame(height: 1)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows, id: \.rowKey) { e in
                            ActivityRow { column in cell(column, e) }
                                .accessibilityElement(children: .combine)
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

    @ViewBuilder private func cell(_ column: ActivityColumn, _ e: ActivityEntry) -> some View {
        switch column {
        case .time:
            Text(TimeText.short(e.at)).font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
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
        case .skipped: Chip("Skipped", tone: .warning, systemImage: "clock.badge.xmark")
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
    @ViewBuilder var cell: (ActivityColumn) -> Cell

    var body: some View {
        HStack(spacing: Theme.Space.s + 2) {
            ForEach(ActivityColumn.allCases, id: \.self) { column in
                Group {
                    if header {
                        Eyebrow(Text(column.title))
                    } else {
                        cell(column)
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
