#if DEBUG
import Foundation
import SidefolkCore

/// The Ask panel's actions for snapshots: the real hint line (the local parser, no AI), nothing else.
@MainActor
final class FixtureAskActions: AskActions {
    func hint(for text: String) -> String? {
        IntentParser().parse(text, now: Date(), knownCollections: [])?.hint ?? String(localized: "Ask \("Claude")")
    }

    func submit(_ text: String, attachment: Attachment?, thinkHarder: Bool, spoken: Bool, into model: AskModel) {}
    func stop() {}
    func undo(activityId: String, in model: AskModel) {}
    func answer(approval: ApprovalRequest, decision: ApprovalDecision) {}
    func open(card: ResultCard) {}
    func saveAnswer(_ text: String, tainted: Bool, in model: AskModel) {}
    func saveAsTask(_ text: String, in model: AskModel) {}
    func remind(_ guess: ReminderGuess, in model: AskModel) {}
    func askWhen(toRemind text: String, in model: AskModel) {}
    func reminderTimes() -> [(label: String, date: Date)] { [] }
    func remindPending(at date: Date, in model: AskModel) {}
    func answer(question: AttentionItem, actionId: String) {}
    func perform(_ action: DropAction, with attachment: Attachment, in model: AskModel) {}
    func retry(_ text: String, in model: AskModel) {}
    func openSettings(tab: SettingsTab?) {}
    func openHome() {}
}
#endif
