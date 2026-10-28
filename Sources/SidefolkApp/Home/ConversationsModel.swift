import Foundation
import Observation
import SidefolkCore

/// Home › Conversations (D45): what was asked of the AI and what it answered, to read again, follow up in, or forget.
/// The history is the runtime's (`Exchange` rows, kept `historyDays`); the steps come from Activity.
@MainActor @Observable
final class ConversationsModel {
    let services: AppServices
    private var runtime: SidefolkRuntime { services.runtime }

    private(set) var conversations: [ConversationSummary] = []
    private(set) var lines: [ConversationLine] = []
    /// The list has been read once (an empty one means there are none, not that it's loading).
    private(set) var loaded = false
    var query = "" {
        didSet { if query != oldValue { scheduleReload() } }
    }
    var selectedId: String? {
        didSet {
            guard selectedId != oldValue else { return }
            draft = ""
            error = nil
            lines = []
            Task { await loadTranscript() }
        }
    }
    var draft = ""
    /// The words just sent, shown until the stored request takes their place.
    private(set) var sending: String?
    /// What the AI is doing for the reply ("Thinking…").
    private(set) var phase: String?
    private(set) var runId: String?
    var error: UserFacingError?
    private var searching: Task<Void, Never>?

    init(services: AppServices) {
        self.services = services
    }

    var selected: ConversationSummary? { conversations.first { $0.id == selectedId } }
    var hasAI: Bool { runtime.settings.current.provider.kind != .none }
    var keptDays: Int { runtime.settings.current.historyDays }
    var busy: Bool { runId != nil || sending != nil }

    func reload() async {
        conversations = (try? await runtime.exchanges.conversations(matching: query)) ?? []
        loaded = true
        // Deleted, aged out, or not among the matches: the newest takes its place.
        if selectedId.map({ id in !conversations.contains { $0.id == id } }) ?? true, runId == nil {
            selectedId = conversations.first?.id
        }
        await loadTranscript()
    }

    func loadTranscript() async {
        guard let id = selectedId else {
            lines = []
            return
        }
        let exchanges = (try? await runtime.exchanges.conversation(id)) ?? []
        // A reply still coming has steps under a run no stored exchange names yet.
        let runs = ConversationTranscript.runIds(exchanges) + [runId].compactMap { $0 }
        let steps = (try? await runtime.activity.steps(ofRuns: runs)) ?? []
        guard id == selectedId else { return }
        lines = ConversationTranscript.lines(exchanges, steps: steps)
        if let sending, lines.last(where: \.isRequest)?.text == sending { self.sending = nil }
    }

    /// Continues the conversation with the words in the reply field, however long ago it was.
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let thread = selectedId, !text.isEmpty, !busy else { return }
        guard hasAI else {
            error = UserFacingError("That needs AI, which isn't set up yet.",
                                    recovery: "Choose Claude Code, Codex, an API key or Ollama in Settings › AI.")
            return
        }
        draft = ""
        error = nil
        sending = text
        phase = AppCoordinator.thinkingLine(harder: false)
        Task {
            guard let handle = await services.continueConversation(thread, text: text) else {
                sending = nil
                phase = nil
                return
            }
            runId = handle.runId
            for await event in handle.events {
                switch event {
                case .phase(.thinking): phase = AppCoordinator.thinkingLine(harder: false)
                case .phase(.working(let category)): phase = AppCoordinator.phaseLine(category)
                case .phase(.waitingForApproval): phase = String(localized: "Waiting for your OK…")
                case .toolFinished: await loadTranscript()
                default: break
                }
            }
            runId = nil
            sending = nil
            phase = nil
            await reload()
        }
    }

    func stop() async {
        guard let runId else { return }
        await services.stopConversation(run: runId)
    }

    func delete(_ conversation: ConversationSummary) async {
        if let problem = await services.deleteConversation(conversation.id) { error = problem }
        await reload()
    }

    func deleteAll() async {
        if let problem = await services.deleteAllConversations() { error = problem }
        selectedId = nil
        await reload()
    }

    private func scheduleReload() {
        searching?.cancel()
        searching = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }
}

extension ConversationLine {
    var isRequest: Bool {
        if case .request = kind { return true }
        return false
    }
}
