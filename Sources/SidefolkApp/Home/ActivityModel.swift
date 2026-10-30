import Foundation
import Observation
import SidefolkCore

/// The audit trail: every tool call, who asked, what Guard decided and how it ended.
@MainActor @Observable
final class ActivityModel {
    enum Show: Hashable { case all, needsAttention }

    /// Caller kinds as the filter names them; nil means everyone.
    static let callerKinds: [(kind: String, title: LocalizedStringResource)] = [
        ("user", "You"), ("agent", "Sidefolk"), ("routine", "Routines"), ("external", "Other agents"), ("extension", "Extensions"),
    ]

    var show: Show = .all
    var callerKind: String?
    /// The row whose details are open, by id: one at a time, so the table stays a table.
    var openId: Int64?
    private(set) var entries: [ActivityEntry] = []
    /// Rows whose action can still be undone (the last 15 minutes), by row id.
    private(set) var undoable: Set<Int64> = []
    /// What the last Undo here did, or why it couldn't.
    private(set) var undoMessage: String?
    private(set) var weekRuns = 0
    private(set) var weekInputTokens = 0
    private(set) var weekOutputTokens = 0
    private(set) var weekActions = 0

    let services: AppServices
    private var runtime: SidefolkRuntime { services.runtime }

    init(services: AppServices) {
        self.services = services
    }

    var companionName: String { runtime.settings.current.companionName }

    var visible: [ActivityEntry] {
        entries.filter { e in
            (show == .all || Self.needsAttention(e)) && (callerKind == nil || Describe.callerKind(e.caller) == callerKind)
        }
    }

    var attentionCount: Int { entries.filter(Self.needsAttention).count }

    static func needsAttention(_ e: ActivityEntry) -> Bool {
        [.denied, .blocked, .failed, .skipped].contains(e.decision)
    }

    func toggle(_ e: ActivityEntry) {
        openId = openId == e.id ? nil : e.id
    }

    /// Undoes what a row did. Sidefolk's own actions and other agents' are undone by different executors.
    func undo(_ entry: ActivityEntry) async {
        guard let row = entry.id else { return }
        do {
            var label = try await runtime.executor.undo.undo(row: row)
            if label == nil { label = try await runtime.gateway.undo.undo(row: row) }
            undoMessage = label.map { String(localized: "Undone: \($0).") } ?? String(localized: "That can't be undone anymore.")
        } catch {
            undoMessage = String(localized: "I couldn't undo that.")
        }
        await reload()
    }

    func reload() async {
        entries = (try? await runtime.activity.recent(limit: 1000)) ?? []
        undoable = await runtime.executor.undo.undoableRows().union(await runtime.gateway.undo.undoableRows())
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date().addingTimeInterval(-7 * 86400)
        if let totals = try? await runtime.runs.totals(since: weekStart) {
            weekRuns = totals.runs
            weekInputTokens = totals.input
            weekOutputTokens = totals.output
        }
        weekActions = entries.filter { $0.at >= weekStart }.count
    }
}
