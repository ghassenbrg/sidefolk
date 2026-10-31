import Foundation
import Observation
import SidefolkCore

/// Home › History (D84): Activity and Conversations as one timeline of plain sentences, with what Sidefolk told the
/// person and other agents' sessions as receipts. Read from what the app already keeps (`HistoryTimeline`); Undo is
/// Activity's, where an undo still exists; a conversation opens in place with Conversations' own model.
@MainActor @Observable
final class HistoryModel {
    /// How far back the timeline reaches.
    enum Span: String, CaseIterable, Identifiable {
        case today, week, all
        var id: Self { self }
    }

    var filter: HistoryFilter = .all
    var span: Span = .today
    var query = ""
    /// The row whose exact record is open, by event id: one at a time.
    var openId: String?
    /// What the last Undo did, or why it couldn't.
    private(set) var undoMessage: String?
    private(set) var events: [HistoryEvent] = []
    /// Activity rows whose action can still be undone (the last 15 minutes), by row id.
    private(set) var undoable: Set<Int64> = []
    /// The kept conversation each run belongs to, by run id: "asked in" on an action's record.
    private(set) var runConversations: [String: ConversationSummary] = [:]
    /// The timeline has been read once (an empty one means there is none, not that it's loading).
    private(set) var loaded = false
    /// The conversation open in place, with its transcript and reply field.
    let conversation: ConversationsModel

    let services: AppServices
    private var runtime: SidefolkRuntime { services.runtime }

    init(services: AppServices) {
        self.services = services
        conversation = ConversationsModel(services: services)
    }

    var companionName: String { runtime.settings.current.companionName }

    /// What shows under the filter, the span and the search.
    var visible: [HistoryEvent] {
        let start = spanStart
        return events.filter { event in
            start.map { event.at >= $0 } ?? true && HistoryTimeline.shows(event, filter: filter, query: query)
        }
    }

    /// How many things happened in the span, for the toolbar's line.
    var spanCount: Int {
        let start = spanStart
        return events.filter { event in start.map { event.at >= $0 } ?? true }.count
    }

    private var spanStart: Date? {
        let cal = Calendar.current
        switch span {
        case .today: return cal.startOfDay(for: Date())
        case .week: return cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date()))
        case .all: return nil
        }
    }

    func reload() async {
        let rt = runtime
        let activity = (try? await rt.activity.recent(limit: 1000)) ?? []
        let conversations = (try? await rt.exchanges.conversations(matching: "")) ?? []
        let alerts = (try? await AttentionStore(rt.db).recent(limit: 300)) ?? []
        let sessions = (try? await rt.sessions.recent(limit: 100)) ?? []
        events = HistoryTimeline.merge(activity: activity, conversations: conversations, alerts: alerts, sessions: sessions)
        runConversations = (try? await rt.exchanges.conversations(ofRuns: activity.compactMap(\.runId))) ?? [:]
        undoable = await rt.executor.undo.undoableRows().union(await rt.gateway.undo.undoableRows())
        loaded = true
        if let open = conversation.selectedId, !conversations.contains(where: { $0.id == open }) { conversation.selectedId = nil }
    }

    func toggle(_ event: HistoryEvent) {
        if case .conversation(let c) = event.kind {
            if conversation.selectedId == c.id { conversation.selectedId = nil } else { open(conversation: c.id) }
            return
        }
        openId = openId == event.id ? nil : event.id
    }

    /// Opens a conversation in place, its row in view.
    func open(conversation id: String) {
        if filter != .all && filter != .conversations { filter = .all }
        if let event = events.first(where: { if case .conversation(let c) = $0.kind { c.id == id } else { false } }),
           let start = spanStart, event.at < start {
            span = .all
        }
        conversation.selectedId = id
    }

    /// Opens the record of an Activity row (the Ask panel's "see in Activity").
    func open(activityRow id: Int64?) {
        guard let id else { return }
        filter = .all
        if let event = events.first(where: { if case .action(let e) = $0.kind { e.id == id } else { false } }) {
            if let start = spanStart, event.at < start { span = .all }
            openId = event.id
        }
    }

    func canUndo(_ entry: ActivityEntry) -> Bool { entry.id.map(undoable.contains) ?? false }

    /// Undoes what a row did, as Activity's Undo always has: Sidefolk's own actions and other agents' are undone by
    /// different executors.
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

    func clearUndoMessage() { undoMessage = nil }
}
