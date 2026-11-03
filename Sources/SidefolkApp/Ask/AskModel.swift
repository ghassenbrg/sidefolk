import AppKit
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
    /// Every file in the drag, when there was more than one. `kind` holds the first.
    var files: [URL] = []
    /// Another app sent these through the Service, with no click behind them (D151).
    var fromAnotherApp = false

    /// Files macOS handed over, from a drag or from Finder's Send to Sidefolk (D151).
    static func files(_ urls: [URL]) -> Attachment? {
        guard let first = urls.first else { return nil }
        return Attachment(kind: .file(first), label: urls.count == 1 ? DropChoices.shownName(first.path) : String(localized: "\(urls.count) files", comment: "What several dropped files are called"),
                          text: nil, files: urls)
    }
}

/// A reminder the local parser could make from words that didn't start with "remind me".
struct ReminderGuess: Equatable {
    var title: String
    var when: Date
    var recurrence: Recurrence?
    var label: String
}

/// A request that needed AI while none was chosen: what works without it, and a way to send it again.
struct NoAIRequest: Equatable {
    /// The words with the dropped item's text, for the actions that keep them as a task or a note.
    var text: String
    var guess: ReminderGuess?
    /// The request as asked and what was dropped with it, sent again once an AI is chosen.
    var request: String
    var attachment: Attachment?
    /// Plans this Mac is already signed in to (Claude Code, Codex), found after the card appears.
    var ready: [ProviderKind] = []
}

/// One result in the Ask panel. Requests end in objects, not a transcript (DECISIONS D5).
struct AskEntry: Identifiable, Equatable {
    enum Content: Equatable {
        case result(ResultCard, activityId: String?, undo: Bool)
        /// `thread`: the AI conversation it belongs to, which Reply continues and Conversations opens (D45).
        case answer(String, canThinkHarder: Bool, tainted: Bool, thread: String? = nil)
        case list(title: String, cards: [ResultCard])
        case approval(ApprovalRequest)
        case error(UserFacingError, retryable: Bool)
        /// No AI is set up; offers local alternatives (a reminder it understood, a task, a note) and
        /// the AI this Mac already has, when there is one.
        case needsBrain(NoAIRequest)
        /// Sidefolk's own agent asks something; answered here with a button or by typing.
        case question(AttentionItem)
        case info(String)
        /// The line said aloud for this request, always shown too (D34); muted says why it wasn't.
        case spoken(String, muted: VoicePolicy.Silence?)
        /// Done without a question because the person chose Auto or Full access (D37): never silent.
        case doneWithoutAsking(String, fullAccess: Bool)
        /// Nobody answered in time: what was skipped, why, and that it waits in Now (D37).
        case skipped(String, why: String)
    }

    let id = UUID()
    var caption: String?
    var content: Content
    var createdAt = Date()
    /// A notice that needs nothing from anyone ("Undone", a word about talking) goes away on its own then.
    var fadesAt: Date?
    /// When it first reached the person, on screen in Ask or another way: its lifetime starts there (D90, D136).
    var seenAt: Date?
    /// Back from before quitting (D136): what's asked now doesn't join it.
    var restored = false
    /// Begins a request of its own without words to show.
    var startsRequest = false

    /// How long it stays in Ask (D90, D136): what still needs the person stays, the rest goes soon after it reached them.
    var weight: ResultLifetime.Weight {
        switch content {
        case .approval, .question: .needsYou
        case .error(_, let retryable): retryable ? .needsYou : .normal
        case .result(let card, _, _): ResultLifetime.weight(of: card)
        case .info, .spoken: .quick
        case .answer, .list, .needsBrain, .doneWithoutAsking, .skipped: .normal
        }
    }

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
/// What the working card shows. Sidefolk's own words, about the person's file.
struct WorkingFile: Equatable {
    var path: String
    var name: String
    var extensionId: String
    var mark: String?
    var showsPicture = true
}

protocol AskActions: AnyObject {
    func hint(for text: String) -> String?
    /// What Return would do with these words, from the same parse that runs them (D84): nil while Sidefolk waits for
    /// a time or an address, which the hint line asks for.
    func understanding(for text: String) -> Understanding?
    /// The AI ⌘Return asks ("Claude"), nil when none is set up.
    var aiName: String? { get }
    /// `spoken`: the words came from the talk key, so the reply may be said aloud (D34). `followUp`: the conversation
    /// the person chose to reply in, which continues however long ago it was (D45).
    /// - Parameter askAI: the AI answers even words Sidefolk understands without it (⌘Return, D58).
    func submit(_ text: String, attachment: Attachment?, thinkHarder: Bool, askAI: Bool, spoken: Bool, followUp: String?, into model: AskModel)
    /// Everything that matches the words typed so far (D58).
    func find(_ query: String) async -> SearchResults
    /// Opens something a search found where it lives.
    func open(_ found: Found)
    /// Keeps the words as a note in Inbox (⌥Return).
    func saveAsNote(_ text: String, in model: AskModel)
    func openSession(_ session: AgentSession)
    /// Something Sidefolk noticed, set aside without an answer (Glance's ×).
    func dismissAttention(_ item: AttentionItem)
    func stop()
    /// The next request starts a new conversation with the AI; `announce` says so in the panel (D45).
    func startFresh(in model: AskModel, announce: Bool)
    /// Home › Conversations, at `thread` when given.
    func openConversation(_ thread: String?)
    func undo(activityId: String, in model: AskModel)
    func answer(approval: ApprovalRequest, decision: ApprovalDecision)
    func open(card: ResultCard)
    /// A file Sidefolk saved: opened in its default app, or shown in Finder (D142). Only on the person's click.
    func open(file: PlacedFile)
    func show(files: [PlacedFile])
    /// `tainted`: the words came from a turn that read outside content.
    func saveAnswer(_ text: String, tainted: Bool, in model: AskModel)
    func saveAsTask(_ text: String, in model: AskModel)
    func remind(_ guess: ReminderGuess, in model: AskModel)
    /// Asks "When?" for `text` (no AI needed: the answer can be typed or tapped).
    func askWhen(toRemind text: String, in model: AskModel)
    /// Chooses `kind` as the AI (a plan this Mac is signed in to) and sends the request again with it.
    func answer(_ request: NoAIRequest, with kind: ProviderKind, replacing entry: AskEntry.ID, in model: AskModel)
    /// Times to tap when Sidefolk asks "When?", from the user's own times of day.
    func reminderTimes() -> [(label: String, date: Date)]
    /// What reads a typed time, with the person's times of day.
    var whenParser: WhenParser { get }
    /// Sets the reminder that was waiting for its time.
    func remindPending(at date: Date, in model: AskModel)
    func answer(question: AttentionItem, actionId: String)
    /// Something dropped on the companion: one of its drop card's choices (D84).
    func perform(_ action: DropChoice, with attachment: Attachment, in model: AskModel)
    /// The drop card's four choices for what was dropped, the first what Return does.
    func dropChoices(for attachment: Attachment) -> [DropChoice]
    /// What extensions offer for it (D100).
    func extensionDrops(for attachment: Attachment) -> [ExtensionDropAction]
    /// A picture from an extension's pack, checked as any of its pictures is (D150).
    func packPicture(_ path: String, extensionId: String) async -> NSImage?
    func perform(_ action: ExtensionDropAction, choosing item: ExtensionManifest.DropMeta.MenuItem?, with attachment: Attachment, in model: AskModel)
    /// The drop card's Open with…: the dropped file in the app the person picked.
    func open(_ attachment: Attachment, with app: URL, in model: AskModel)
    func retry(_ text: String, in model: AskModel)
    func openSettings(tab: SettingsTab?)
    func openHome()
    /// Home › Now, where skipped steps wait (D37).
    func openNow()
    func open(_ entry: ExtensionEntry)
}

/// The answer a reply follows up: its card, its conversation, and the words it answered.
struct ReplyTarget: Equatable {
    var entry: AskEntry.ID
    var thread: String?
    var request: String?
}

/// Talking instead of typing (D34): what the panel shows while the talk key is held and just after.
enum VoiceInput: Equatable {
    /// The microphone and the recognizer are getting ready.
    case starting
    /// The microphone is on; the input shows the words as they are recognized. `basic` on macOS 15.
    case listening(basic: Bool)
    /// The language's speech model is downloading (0...1).
    case preparing(Double)
    /// Released: the last words are settling.
    case finishing
}

@MainActor @Observable
final class AskModel {
    var text = "" {
        didSet {
            guard text != oldValue else { return }
            found.query = text
            // Words typed under Today are a request: the conversation shows what they will do.
            if !text.isEmpty { tab = .ask }
        }
    }
    /// The conversation or a compact Today under the field (D84).
    var tab: AskTab = .ask {
        didSet { markSeen() }
    }
    /// Extensions' tabs beside Ask's own (D100), as they were when it opened.
    var entryTabs: [ExtensionEntry] = []
    /// What the words typed so far match across Sidefolk, under the hint line (D58).
    let found = FindModel()
    /// Today at a glance, shown while nothing is typed (D58): Ask's resting state, on top of the stack (D84).
    var glance = Glance()
    /// How many wait on the person in all (the count on the companion's shoulder).
    var waiting = 0
    var attachment: Attachment?
    var entries: [AskEntry] = [] {
        didSet { savePins() }
    }
    var busy = false
    /// A file an extension is working on right now, from a choice on the drop card (D150).
    var working: WorkingFile?
    var phase: String?
    /// Set while the person talks; the input is theirs again once it is nil.
    var voice: VoiceInput?
    /// Increments to ask the view to focus the input.
    var focusRequest = 0
    /// The answer the person chose to reply to; the input says so until they send (D45).
    var replyingTo: ReplyTarget?
    /// The AI conversation the newest answer belongs to, while one is open; "New conversation" ends it (D45).
    var thread: String?
    /// The person started fresh: the next request to the AI begins a new conversation.
    var startsFresh = false
    /// A reminder waiting for its time ("When should I remind you?").
    var pendingReminderTitle: String?
    var pendingReminderImportant = false
    /// A watch waiting for its address ("Which address? e.g. localhost:3000").
    var pendingWatch: (kind: String, becomes: String?)?
    /// How much Sidefolk asks (D37), shown in the header.
    var mode: GuardMode = .askOncePerKind
    weak var actions: AskActions? {
        didSet { found.find = { [weak self] query in await self?.actions?.find(query) ?? SearchResults() } }
    }
    /// Extensions by id, so their approval and result cards show their icon and name.
    var extensionLooks: [String: ExtensionLook] = [:]
    /// Called when a quick intent finished and the panel can close.
    var onAutoClose: (() -> Void)?
    /// The header's close button.
    var onClose: (() -> Void)?
    /// Who the person talks to, for "Mochi wants to".
    var companionName = "Sidefolk"
    /// Opened by a slip or a question alone: only they show, above the companion, until the person opens Ask (D84).
    var compact = false
    /// Where the Sidecard's tail points, toward the companion's head; set when the panel is placed.
    var tail: SidecardTail?

    /// Requests kept, pins aside: the newest under the input. It's a shortcut, and History has them all (D136).
    static let keptRequests = 8
    /// How long a notice that needs nothing stays.
    static let noticeSeconds: TimeInterval = 20
    /// The pointer is over the panel: nothing fades while someone may be reading it.
    var hovering = false
    /// A request being swiped away with two fingers, and how far it has moved.
    var swipe: (id: UUID, offset: CGFloat)?
    /// The request under the pointer, the one a two-finger swipe moves.
    var hoveredRequest: UUID?
    /// Results the person pinned: they stay until removed (D90).
    var pinnedRequests: Set<UUID> = [] {
        didSet { savePins() }
    }
    /// Pinned results changed: they outlast quitting (D136).
    var onPinsChanged: (([SavedAskRequest]) -> Void)?
    private var savedPins: [SavedAskRequest] = []
    /// Results went on their own since Ask was cleared: a quiet line says they are in History.
    var tidied = false
    /// Ask is on screen, and has the keyboard: nothing is tidied away while someone may be reading.
    var visible = false
    var focused = false
    /// The tallest the results may grow before they scroll: the panel stays on screen.
    var resultsMaxHeight: CGFloat = 520
    private var fading: Task<Void, Never>?

    var hint: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return actions?.hint(for: trimmed)
    }

    /// The understanding row under the field: what Return will do with the words typed so far.
    var understanding: Understanding? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, pendingQuestion == nil, voice == nil, !busy else { return nil }
        return actions?.understanding(for: trimmed)
    }

    /// One request and what came of it, in order; the first entry carries the request's words.
    struct Request: Identifiable, Equatable {
        var entries: [AskEntry]
        var id: UUID { entries[0].id }
        var caption: String? { entries[0].caption }
    }

    /// Questions and approvals: they wait for an answer, so they stay in view above the results.
    var pinnedEntries: [AskEntry] { entries.filter(\.isPinned) }

    /// Opened by permission slips alone: only they show, above the companion (a question needs the field to answer).
    var showsSlipsOnly: Bool {
        compact && !pinnedEntries.isEmpty && pinnedEntries.allSatisfy { if case .approval = $0.content { true } else { false } }
    }

    /// Every result so far, grouped by request, oldest first.
    var requests: [Request] {
        var requests: [Request] = []
        for entry in entries where !entry.isPinned {
            if entry.caption != nil || entry.startsRequest || requests.isEmpty { requests.append(Request(entries: [entry])) } else { requests[requests.count - 1].entries.append(entry) }
        }
        return requests
    }

    /// The requests, newest first, right under the input where the eye already is.
    var visibleRequests: [Request] { requests.reversed() }

    var hasResults: Bool { entries.contains { !$0.isPinned } }

    func remove(_ request: Request) {
        let gone = Set(request.entries.map(\.id))
        entries.removeAll { gone.contains($0.id) }
        if swipe.map({ gone.contains($0.id) }) == true { swipe = nil }
        if replyingTo.map({ gone.contains($0.entry) }) == true { replyingTo = nil }
    }

    /// Swiped or clicked away: the card slides off the way it was going, then goes.
    func dismiss(_ id: UUID, toward direction: CGFloat) {
        guard let request = requests.first(where: { $0.id == id }) else { return }
        swipe = (id, direction < 0 ? -460 : 460)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            self?.remove(request)
        }
    }

    /// Everything but the questions and approvals still waiting for an answer. The conversation ends with them:
    /// a follow-up shouldn't lean on answers the person just cleared away (D45).
    func clearResults() {
        entries.removeAll { !$0.isPinned }
        pinnedRequests = []
        tidied = false
        replyingTo = nil
        actions?.startFresh(in: self, announce: false)
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

    /// Replying is typing a follow-up in that answer's conversation, however long ago it was; nothing said so, so
    /// every answer offers Reply and the input becomes the place for it. Again on the same answer: not replying.
    func reply(to entry: AskEntry.ID, thread: String?, request: String?) {
        guard replyingTo?.entry != entry else {
            replyingTo = nil
            return
        }
        replyingTo = ReplyTarget(entry: entry, thread: thread, request: request)
        focusRequest += 1
    }

    func submit(thinkHarder: Bool = false, askAI: Bool = false, spoken: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // While the agent waits for an answer, what the user types is that answer.
        if let question = pendingQuestion, !trimmed.isEmpty {
            text = ""
            actions?.answer(question: question, actionId: AgentFacingTools.typedAnswerPrefix + trimmed)
            return
        }
        guard !trimmed.isEmpty || attachment != nil, !busy else { return }
        // Choosing an extension's offer is what lets it read the file, so Return never makes that choice for you (D141).
        if trimmed.isEmpty, let attachment, attachment.dropKind == .file, actions?.extensionDrops(for: attachment).isEmpty == false { return }
        // Nothing typed with something dropped: Return is the drop card's first choice (D84).
        if trimmed.isEmpty, let attachment, let first = actions?.dropChoices(for: attachment).first {
            actions?.perform(first, with: attachment, in: self)
            return
        }
        let followUp = replyingTo?.thread
        replyingTo = nil
        // Shown as the request's caption and sent with the item; the model answers in any language.
        let request = trimmed.isEmpty ? String(localized: "What should I do with this?") : trimmed
        text = ""
        let sent = attachment
        attachment = nil
        actions?.submit(request, attachment: sent, thinkHarder: thinkHarder, askAI: askAI, spoken: spoken, followUp: followUp, into: self)
    }

    /// When the AI last answered in the open conversation, for Ask's header (D84).
    var threadAnsweredAt: Date? {
        guard let thread else { return nil }
        return entries.last { if case .answer(_, _, _, let t) = $0.content { t == thread } else { false } }?.createdAt
    }

    /// The words of the newest request, to tell whether a newer one came in since.
    var latestCaption: String? { entries.last { $0.caption != nil }?.caption }

    /// `fades`: a notice that needs nothing from anyone, gone after `noticeSeconds` unless someone is reading.
    /// `seen`: it already reached the person some other way, as an animation they watched.
    func add(_ content: AskEntry.Content, caption: String? = nil, fades: Bool = false, seen: Bool = false) {
        // Asking something new is when what's past its time goes, with the pointer anywhere.
        if caption != nil { tidy(force: true) }
        var entry = AskEntry(caption: caption, content: content, fadesAt: fades ? Date().addingTimeInterval(Self.noticeSeconds) : nil)
        entry.startsRequest = entries.last { !$0.isPinned }?.restored == true
        entries.append(entry)
        makeRoom()
        if fades { fadeLater() }
        // Something new shows where it can be seen: the conversation (D84).
        tab = .ask
        markSeen()
        // Said aloud reached them as much as read, and says the whole request.
        var reached = seen
        if case .spoken(_, muted: nil) = content { reached = true }
        if reached, let request = requests.last { markSeen(request) }
    }

    private func markSeen(_ request: Request, at now: Date = Date()) {
        let ids = Set(request.entries.map(\.id))
        var marked = entries
        for i in marked.indices where ids.contains(marked[i].id) && marked[i].seenAt == nil { marked[i].seenAt = now }
        entries = marked
    }

    /// Over the limit, the oldest results go: never one that's pinned or still waiting for an answer (D136).
    private func makeRoom() {
        let all = requests
        let gone = ResultLifetime.overflow(all.map { (id: $0.id, kept: pinnedRequests.contains($0.id)) }, limit: Self.keptRequests)
        for request in all where gone.contains(request.id) { remove(request) }
    }

    /// Removes earlier notices under this caption: a new word about talking replaces the last one.
    func removeNotices(caption: String) {
        for request in requests where request.caption == caption && request.entries.allSatisfy({ $0.fadesAt != nil }) { remove(request) }
    }

    /// A request made only of notices goes whole; a notice under another card ("Undone") goes alone. A
    /// notice that carries a request's words stays with the rest of it.
    func fade(at now: Date) {
        let due = { (e: AskEntry) in e.fadesAt.map { $0 <= now } ?? false }
        var gone = Set<UUID>()
        for request in requests {
            if request.entries.allSatisfy(due) { gone.formUnion(request.entries.map(\.id)) } else { gone.formUnion(request.entries.dropFirst().filter(due).map(\.id)) }
        }
        entries.removeAll { gone.contains($0.id) }
        for i in entries.indices where due(entries[i]) { entries[i].fadesAt = nil }
    }

    /// Requests made only of notices go once their time is up, never under the pointer.
    private func fadeLater() {
        guard fading == nil else { return }
        fading = Task { [weak self] in
            while let self, let next = self.entries.compactMap(\.fadesAt).min() {
                try? await Task.sleep(for: .seconds(max(0.5, next.timeIntervalSinceNow)))
                if self.hovering { try? await Task.sleep(for: .seconds(2)); continue }
                self.fade(at: Date())
            }
            self?.fading = nil
        }
    }

    func replace(_ id: UUID, with content: AskEntry.Content) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].content = content
    }

    func removeApproval(id: String) {
        entries.removeAll { if case .approval(let r) = $0.content { return r.id == id } else { return false } }
        // A slip that stood alone was answered: nothing else was asked for, so it goes.
        if compact, pinnedEntries.isEmpty {
            compact = false
            onAutoClose?()
        }
    }

    /// Clears old results when the panel opens after a while, so it starts clean.
    func freshenIfStale(after seconds: TimeInterval = 600) {
        guard !busy, let last = entries.last, Date().timeIntervalSince(last.createdAt) > seconds else { return }
        // The runtime's conversation went quiet as long ago: the next request starts a new one. The results themselves
        // go by their own lifetimes (`tidy`).
        thread = nil
        replyingTo = nil
    }

    /// Ask came on screen: what is past its time goes, and what shows now counts as seen (D90).
    func opened(at now: Date = Date()) {
        visible = true
        tidy(at: now, force: true)
        markSeen(at: now)
    }

    /// Results' time starts when they're really in front of the person: not behind another tab or a lone permission slip.
    func markSeen(at now: Date = Date()) {
        guard visible, tab == .ask, !showsSlipsOnly, entries.contains(where: { $0.seenAt == nil }) else { return }
        var marked = entries
        for i in marked.indices where marked[i].seenAt == nil { marked[i].seenAt = now }
        entries = marked
    }

    /// Takes away the requests whose every result is past its lifetime, never a pinned one, never while the person may
    /// be reading (the pointer on Ask, or the keyboard in it) unless Ask is only now opening.
    func tidy(at now: Date = Date(), force: Bool = false) {
        guard force || (!hovering && !focused && !busy) else { return }
        var gone = Set<UUID>()
        for request in requests where !pinnedRequests.contains(request.id) {
            let done = request.entries.allSatisfy {
                ResultLifetime.expired($0.weight, createdAt: $0.createdAt, seenAt: $0.seenAt, pinned: false, now: now)
            }
            if done { gone.formUnion(request.entries.map(\.id)) }
        }
        guard !gone.isEmpty else { return }
        entries.removeAll { gone.contains($0.id) }
        if replyingTo.map({ gone.contains($0.entry) }) == true { replyingTo = nil }
        tidied = true
    }

    func togglePin(_ request: Request) {
        if pinnedRequests.remove(request.id) == nil { pinnedRequests.insert(request.id) }
    }

    // MARK: Pins across quitting (D136)

    private func savePins() {
        guard !pinnedRequests.isEmpty || !savedPins.isEmpty else { return }
        let now = requests.filter { pinnedRequests.contains($0.id) }.compactMap(\.saved)
        guard now != savedPins else { return }
        savedPins = now
        onPinsChanged?(now)
    }

    /// What was pinned before quitting comes back, oldest first, below anything already here.
    func restorePins(_ saved: [SavedAskRequest]) {
        savedPins = saved
        var restored: [AskEntry] = []
        var pins: Set<UUID> = []
        for request in saved {
            let parts = request.parts.map(AskEntry.Content.init(saved:))
            guard let head = parts.first else { continue }
            var first = AskEntry(caption: request.caption, content: head, createdAt: request.createdAt, seenAt: request.seenAt)
            first.startsRequest = true
            first.restored = true
            pins.insert(first.id)
            restored.append(first)
            for part in parts.dropFirst() {
                var entry = AskEntry(caption: nil, content: part, createdAt: request.createdAt, seenAt: request.seenAt)
                entry.restored = true
                restored.append(entry)
            }
        }
        entries = restored + entries
        pinnedRequests.formUnion(pins)
    }
}

extension AskModel.Request {
    /// nil when nothing in it can outlast the moment: a request to send again, a failure to retry, a passing notice.
    var saved: SavedAskRequest? {
        let parts = entries.filter { $0.fadesAt == nil }.compactMap(\.content.saved)
        guard !parts.isEmpty else { return nil }
        return SavedAskRequest(caption: caption, createdAt: entries[0].createdAt, seenAt: entries[0].seenAt, parts: parts)
    }
}

extension AskEntry.Content {
    var saved: SavedAskRequest.Part? {
        switch self {
        case .result(let card, _, _): .result(card)
        case .answer(let text, _, let tainted, let thread): .answer(text, tainted: tainted, thread: thread)
        case .list(let title, let cards): .list(title: title, cards: cards)
        case .info(let text): .info(text)
        case .doneWithoutAsking(let text, let fullAccess): .doneWithoutAsking(text, fullAccess: fullAccess)
        case .skipped(let text, let why): .skipped(text, why: why)
        case .approval, .question, .error, .needsBrain, .spoken: nil
        }
    }

    init(saved part: SavedAskRequest.Part) {
        self = switch part {
        case .result(let card): .result(card, activityId: nil, undo: false)
        case .answer(let text, let tainted, let thread): .answer(text, canThinkHarder: false, tainted: tainted, thread: thread)
        case .list(let title, let cards): .list(title: title, cards: cards)
        case .info(let text): .info(text)
        case .doneWithoutAsking(let text, let fullAccess): .doneWithoutAsking(text, fullAccess: fullAccess)
        case .skipped(let text, let why): .skipped(text, why: why)
        }
    }
}
