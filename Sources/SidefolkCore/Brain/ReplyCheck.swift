import Foundation

/// The last word on what was done belongs to `ToolExecutor`, not the model (D115). Every brain's reply comes through here,
/// whichever backend ran it, and what the tools really did is added beneath the model's own words. It stays in the
/// conversation, so the model reads it next turn too.
enum ReplyCheck {
    /// `mutates` says whether a tool changes things, and nil for one that doesn't exist: a model calling a tool it wasn't
    /// given has done nothing to report.
    static func checked(_ reply: AgentReply, outcomes: [ToolOutcome], mutates: (String) -> Bool?) -> AgentReply {
        let acting = outcomes.filter { mutates($0.activity.tool) == true }
        let done = acting.filter(\.isOK)
        var added = standingFailures(acting).map(failureLine)
        // Any call that worked, read-only included, may be what the words are about ("Your reminder is set for 3").
        if added.isEmpty, !outcomes.contains(where: \.isOK), UnbackedClaim.firm(in: reply.text) {
            added.append(String(localized: "Sorry, that didn't actually happen: no action ran. Nothing was changed.",
                                comment: "Added under a reply that said something was done when no tool did it"))
        }
        if !done.isEmpty, UnbackedClaim.denied(in: reply.text) {
            added.append(LoopBackend.progress(done))
        }
        guard !added.isEmpty else { return reply }
        var checked = reply
        checked.text = ([reply.text.trimmingCharacters(in: .whitespacesAndNewlines)] + added).filter { !$0.isEmpty }.joined(separator: "\n\n")
        return checked
    }

    /// What failed and wasn't then done by trying the same thing again; three notes with one failed still say so. A step
    /// the person refused or left unanswered isn't one: they know, and a claim about it is caught as a claim.
    private static func standingFailures(_ acting: [ToolOutcome]) -> [ToolOutcome] {
        acting.enumerated().filter { i, outcome in
            switch outcome.status {
            case .failed: break
            case .ok(let result) where result.isError: break
            default: return false
            }
            return !acting[(i + 1)...].contains { $0.isOK && $0.activity.tool == outcome.activity.tool && $0.activity.summary == outcome.activity.summary }
        }.map(\.element).prefix(3).map { $0 }
    }

    /// A tool's own words on an error are written for the model, and an extension's aren't to be trusted: its card, or
    /// nothing more, reaches the person.
    private static func failureLine(_ outcome: ToolOutcome) -> String {
        let what = String(localized: "Not done: “\(outcome.activity.summary)”.", comment: "Added under a reply: a step that failed, in the tool's words about it")
        if case .ok(let result) = outcome.status { return Wording.sentences([what, result.card?.title ?? ""]) }
        return Wording.sentences([what, outcome.problem?.message ?? ""])
    }
}
