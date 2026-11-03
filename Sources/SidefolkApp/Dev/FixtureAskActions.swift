#if DEBUG
import Foundation
import SidefolkCore

/// The Ask panel's actions for snapshots: the real hint line (the local parser, no AI), nothing else.
@MainActor
final class FixtureAskActions: AskActions {
    func hint(for text: String) -> String? {
        IntentParser().parse(text, now: Date(), knownCollections: [])?.hint ?? String(localized: "Ask \("Claude")")
    }

    func understanding(for text: String) -> Understanding? {
        IntentParser().parse(text, now: Date(), knownCollections: [])?.understanding() ?? .ai("Claude")
    }

    var aiName: String? { "Claude" }

    func submit(_ text: String, attachment: Attachment?, thinkHarder: Bool, askAI: Bool, spoken: Bool, followUp: String?, into model: AskModel) {}
    func find(_ query: String) async -> SearchResults { SearchResults() }
    func open(_ found: Found) {}
    func saveAsNote(_ text: String, in model: AskModel) {}
    func openSession(_ session: AgentSession) {}
    func dismissAttention(_ item: AttentionItem) {}
    func stop() {}
    func startFresh(in model: AskModel, announce: Bool) {}
    func openConversation(_ thread: String?) {}
    func undo(activityId: String, in model: AskModel) {}
    func answer(approval: ApprovalRequest, decision: ApprovalDecision) {}
    func open(card: ResultCard) {}
    func open(file: PlacedFile) {}
    func show(files: [PlacedFile]) {}
    func saveAnswer(_ text: String, tainted: Bool, in model: AskModel) {}
    func saveAsTask(_ text: String, in model: AskModel) {}
    func remind(_ guess: ReminderGuess, in model: AskModel) {}
    func askWhen(toRemind text: String, in model: AskModel) {}
    func answer(_ request: NoAIRequest, with kind: ProviderKind, replacing entry: AskEntry.ID, in model: AskModel) {}
    func reminderTimes() -> [(label: String, date: Date)] { [] }
    var whenParser: WhenParser { WhenParser() }
    func remindPending(at date: Date, in model: AskModel) {}
    func answer(question: AttentionItem, actionId: String) {}
    func perform(_ action: DropChoice, with attachment: Attachment, in model: AskModel) {}
    /// What a fictional extension offers for a drop (D100's drop actions).
    var drops: [ExtensionDropAction] = []
    func dropChoices(for attachment: Attachment) -> [DropChoice] {
        DropChoices.choices(for: attachment.dropKind, offers: extensionDrops(for: attachment).count)
    }
    func extensionDrops(for attachment: Attachment) -> [ExtensionDropAction] {
        if attachment.dropKind == .file { return DropChoices.offers(forFiles: attachment.dropFiles, among: drops) }
        return DropChoices.offers(for: attachment.dropKind, value: attachment.dropValue, among: drops)
    }
    func perform(_ action: ExtensionDropAction, choosing item: ExtensionManifest.DropMeta.MenuItem?, with attachment: Attachment, in model: AskModel) {}
    func open(_ entry: ExtensionEntry) {}
    func open(_ attachment: Attachment, with app: URL, in model: AskModel) {}
    func openPlay() {}
    func retry(_ text: String, in model: AskModel) {}
    func openSettings(tab: SettingsTab?) {}
    func openHome() {}
    func openNow() {}
}
#endif
