import Foundation

/// One line of a conversation as Home › Conversations shows it (D45).
public struct ConversationLine: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// What the person asked; `attachment` names what came with it.
        case request(spoken: Bool, attachment: String?)
        /// The AI's answer. `tainted`: its turn read outside content, so saving it isn't the person's own words (SECURITY T2).
        case reply(tainted: Bool)
        /// A tool step in Activity's words; `done` is false when it was refused, skipped or failed.
        case step(done: Bool)
        /// How a run ended without an answer ("Stopped. Nothing was changed.").
        case note
    }

    public var id: String
    public var kind: Kind
    public var text: String
    /// Why a step wasn't done, in Activity's words.
    public var detail: String?
    public var at: Date

    public init(id: String, kind: Kind, text: String, detail: String? = nil, at: Date) {
        self.id = id
        self.kind = kind
        self.text = text
        self.detail = detail
        self.at = at
    }
}

/// Puts a conversation back together from what the runtime stored: the requests and replies (`Exchange`), and the
/// steps each run took (`ActivityEntry`, by run), each step just before the reply of its run.
public enum ConversationTranscript {
    /// The runs whose steps belong in the conversation.
    public static func runIds(_ exchanges: [Exchange]) -> [String] {
        exchanges.compactMap { $0.meta?["runId"]?.stringValue }
    }

    public static func lines(_ exchanges: [Exchange], steps: [ActivityEntry]) -> [ConversationLine] {
        var byRun = Dictionary(grouping: steps) { $0.runId ?? "" }
        var lines: [ConversationLine] = []
        func stepsOf(_ runId: String?) {
            guard let runId, let taken = byRun.removeValue(forKey: runId) else { return }
            lines += taken.map(step)
        }
        for e in exchanges {
            switch e.role {
            case .user:
                let attachment = ExchangeMeta.attachment(e.meta)?.source
                lines.append(ConversationLine(id: e.id, kind: .request(spoken: e.meta?["spoken"]?.boolValue ?? false, attachment: attachment),
                                              text: e.content, at: e.createdAt))
            case .assistant:
                stepsOf(e.meta?["runId"]?.stringValue)
                // A turn that only made cards has no words of its own; its steps say what happened.
                guard !e.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                lines.append(ConversationLine(id: e.id, kind: .reply(tainted: e.meta?["tainted"]?.boolValue ?? false), text: e.content,
                                              at: e.createdAt))
            case .event:
                stepsOf(e.meta?["runId"]?.stringValue)
                lines.append(ConversationLine(id: e.id, kind: .note, text: e.content, at: e.createdAt))
            case .tool:
                continue
            }
        }
        // A run still going has steps and no reply yet: they follow its request.
        lines += byRun.values.joined().sorted { ($0.at, $0.id ?? 0) < ($1.at, $1.id ?? 0) }.map(step)
        return lines
    }

    private static func step(_ a: ActivityEntry) -> ConversationLine {
        let done = a.error == nil && ![.denied, .blocked, .failed, .skipped].contains(a.decision)
        return ConversationLine(id: "step-\(a.id ?? 0)", kind: .step(done: done), text: a.summary, detail: done ? nil : a.error, at: a.at)
    }
}
