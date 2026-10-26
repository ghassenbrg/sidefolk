import Foundation
import Observation
import SidefolkCore

/// Something dropped on the companion or pasted, sent along with the next request.
struct Attachment: Equatable {
    enum Kind: Equatable { case file(URL), url(URL), text }
    var kind: Kind
    var label: String
    /// Text handed to the brain (always treated as untrusted).
    var text: String?
}

/// A reminder the local parser could make from words that didn't start with "remind me".
struct ReminderGuess: Equatable {
    var title: String
    var when: Date
    var recurrence: Recurrence?
    var label: String
}

/// Quick things to do with something dropped on the companion.
enum DropAction { case save, remind, watch, ask }

/// One result in the Ask panel. Requests end in objects, not a transcript (DECISIONS D5).
struct AskEntry: Identifiable, Equatable {
    enum Content: Equatable {
        case result(ResultCard, activityId: String?, undo: Bool)
        case answer(String, canThinkHarder: Bool, tainted: Bool)
        case list(title: String, cards: [ResultCard])
        case approval(ApprovalRequest)
        case error(UserFacingError, retryable: Bool)
        /// No AI is set up; offers local alternatives (a reminder it understood, a task, a note).
        case needsBrain(String, guess: ReminderGuess?)
        /// Sidefolk's own agent asks something; answered here with a button or by typing.
        case question(AttentionItem)
        case info(String)
        /// Done without a question because the person chose Auto or Full access (D37): never silent.
        case doneWithoutAsking(String, fullAccess: Bool)
        /// Nobody answered in time: what was skipped, why, and that it waits in Now (D37).
        case skipped(String, why: String)
    }

    let id = UUID()
    var caption: String?
    var content: Content
    var createdAt = Date()

    static func == (a: AskEntry, b: AskEntry) -> Bool { a.id == b.id && a.content == b.content && a.caption == b.caption }

    var isPinned: Bool {
        switch content {
        case .approval, .question: true
        default: false
        }
    }
}

/// What the panel asks the rest of the app to do.
@MainActor
protocol AskActions: AnyObject {
    func hint(for text: String) -> String?
    func submit(_ text: String, attachment: Attachment?, thinkHarder: Bool, into model: AskModel)
    func stop()
    func undo(activityId: String, in model: AskModel)
    func answer(approval: ApprovalRequest, decision: ApprovalDecision)
    func open(card: ResultCard)
    /// `tainted`: the words came from a turn that read outside content.
    func saveAnswer(_ text: String, tainted: Bool, in model: AskModel)
    func saveAsTask(_ text: String, in model: AskModel)
    func remind(_ guess: ReminderGuess, in model: AskModel)
    /// Asks "When?" for `text` (no AI needed: the answer can be typed or tapped).
    func askWhen(toRemind text: String, in model: AskModel)
    /// Times to tap when Sidefolk asks "When?", from the user's own times of day.
    func reminderTimes() -> [(label: String, date: Date)]
    /// Sets the reminder that was waiting for its time.
    func remindPending(at date: Date, in model: AskModel)
    func answer(question: AttentionItem, actionId: String)
    func perform(_ action: DropAction, with attachment: Attachment, in model: AskModel)
    func retry(_ text: String, in model: AskModel)
    func openSettings(tab: SettingsTab?)
    func openHome()
    /// Home › Now, where skipped steps wait (D37).
    func openNow()
}

@MainActor @Observable
final class AskModel {
    var text = ""
    var attachment: Attachment?
    var entries: [AskEntry] = []
    var busy = false
    var phase: String?
    /// Increments to ask the view to focus the input.
    var focusRequest = 0
    /// A reminder waiting for its time ("When should I remind you?").
    var pendingReminderTitle: String?
    var pendingReminderImportant = false
    /// A watch waiting for its address ("Which address? e.g. localhost:3000").
    var pendingWatch: (kind: String, becomes: String?)?
    /// How much Sidefolk asks (D37), shown in the header.
    var mode: GuardMode = .askOncePerKind
    weak var actions: AskActions?
    /// Called when a quick intent finished and the panel can close.
    var onAutoClose: (() -> Void)?

    /// Requests shown under the input; older ones drop off. This is not a chat.
    static let visibleRequests = 2

    var hint: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return actions?.hint(for: trimmed)
    }

    /// One request and what came of it, in order; the first entry carries the request's words.
    struct Request: Identifiable, Equatable {
        var entries: [AskEntry]
        var id: UUID { entries[0].id }
        var caption: String? { entries[0].caption }
    }

    /// Questions and approvals: they wait for an answer, so they stay in view above the results.
    var pinnedEntries: [AskEntry] { entries.filter(\.isPinned) }

    /// Every result so far, grouped by request, oldest first.
    var requests: [Request] {
        var requests: [Request] = []
        for entry in entries where !entry.isPinned {
            if entry.caption != nil || requests.isEmpty { requests.append(Request(entries: [entry])) } else { requests[requests.count - 1].entries.append(entry) }
        }
        return requests
    }

    /// The latest requests, newest first, right under the input where the eye already is.
    var visibleRequests: [Request] { Array(requests.suffix(Self.visibleRequests).reversed()) }

    var hasResults: Bool { entries.contains { !$0.isPinned } }

    func remove(_ request: Request) {
        let gone = Set(request.entries.map(\.id))
        entries.removeAll { gone.contains($0.id) }
    }

    /// Everything but the questions and approvals still waiting for an answer.
    func clearResults() {
        entries.removeAll { !$0.isPinned }
    }

    /// Sends a failed request again in place of its old cards, so retries don't pile up.
    func retry(_ request: Request) {
        guard let caption = request.caption else { return }
        remove(request)
        actions?.retry(caption, in: self)
    }

    /// The agent is waiting for an answer the user can type into the input.
    var pendingQuestion: AttentionItem? {
        for e in entries.reversed() { if case .question(let item) = e.content { return item } }
        return nil
    }

    func removeQuestion(id: String) {
        entries.removeAll { if case .question(let q) = $0.content { return q.id == id } else { return false } }
    }

    func submit(thinkHarder: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // While the agent waits for an answer, what the user types is that answer.
        if let question = pendingQuestion, !trimmed.isEmpty {
            text = ""
            actions?.answer(question: question, actionId: AgentFacingTools.typedAnswerPrefix + trimmed)
            return
        }
        guard !trimmed.isEmpty || attachment != nil, !busy else { return }
        // Shown as the request's caption and sent with the item; the model answers in any language.
        let request = trimmed.isEmpty ? String(localized: "What should I do with this?") : trimmed
        text = ""
        let sent = attachment
        attachment = nil
        actions?.submit(request, attachment: sent, thinkHarder: thinkHarder, into: self)
    }

    func add(_ content: AskEntry.Content, caption: String? = nil) {
        entries.append(AskEntry(caption: caption, content: content))
        if entries.count > 30 { entries.removeFirst(entries.count - 30) }
    }

    func replace(_ id: UUID, with content: AskEntry.Content) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].content = content
    }

    func removeApproval(id: String) {
        entries.removeAll { if case .approval(let r) = $0.content { return r.id == id } else { return false } }
    }

    /// Clears old results when the panel opens after a while, so it starts clean.
    func freshenIfStale(after seconds: TimeInterval = 600) {
        guard !busy, let last = entries.last, Date().timeIntervalSince(last.createdAt) > seconds else { return }
        entries.removeAll()
    }
}
