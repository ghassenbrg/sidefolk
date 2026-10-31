import Foundation
import Observation
import SidefolkCore

/// Notebook › You (D84): what Sidefolk keeps in mind about the person, as a profile of facts with where each came
/// from, Edit and Forget. The facts are the About-you collection's items (D6); suggestions from other agents wait at
/// the top, out of answers, until the person keeps them. Forgetting is the Notebook's Trash, with its Undo.
@MainActor @Observable
final class YouModel {
    /// The person's facts, newest first: theirs, and what Sidefolk noticed in a conversation.
    private(set) var facts: [NotebookItem] = []
    /// What another agent, an extension or a routine suggested: not used until kept.
    private(set) var suggestions: [NotebookItem] = []
    private(set) var loaded = false
    /// The fact being rewritten in place, by id.
    var editing: String?
    /// The new fact's field is open.
    var adding = false
    var problem: UserFacingError?

    let services: AppServices
    /// Forgetting moves a fact to the Notebook's Trash, with the Notebook's own Undo.
    var trash: ((NotebookItem) async -> Void)?
    private var runtime: SidefolkRuntime { services.runtime }

    init(services: AppServices) {
        self.services = services
    }

    var companionName: String { runtime.settings.current.companionName }
    var count: Int { facts.count }

    func reload() async {
        let all = await ProfileFacts.all(notebook: runtime.notebook, includeUntrusted: true).reversed()
        facts = all.filter { !ProfileFacts.isSuggestion($0) }
        suggestions = all.filter(ProfileFacts.isSuggestion)
        loaded = true
    }

    /// Where a fact came from, in plain words: "You said it", "Mochi noticed in a conversation", "Codex suggests".
    func origin(_ item: NotebookItem) -> String {
        let source = item.source
        if source == "user:agent" { return String(localized: "\(companionName) noticed in a conversation", comment: "Where a fact about the person came from") }
        if source == "agent" { return String(localized: "Noted while reading outside content", comment: "Where a fact about the person came from") }
        if source == "app:notes" { return String(localized: "Copied from Apple Notes", comment: "Where a fact about the person came from") }
        if let who = Describe.source(source), ProfileFacts.isSuggestion(item) {
            return String(localized: "\(who) suggests", comment: "Where a fact about the person came from: another agent or an extension, “Codex suggests”")
        }
        if source.hasPrefix("routine") { return String(localized: "A routine suggests", comment: "Where a fact about the person came from") }
        return String(localized: "You said it", comment: "Where a fact about the person came from: the person's own words")
    }

    /// The origin's symbol: the person, the companion, or another app.
    func originSymbol(_ item: NotebookItem) -> String {
        switch item.source {
        case "user": "person"
        case "user:agent": "sparkles"
        default: "puzzlepiece.extension"
        }
    }

    func keep(_ item: NotebookItem) async {
        do {
            try await ProfileFacts.keep(item, notebook: runtime.notebook, events: runtime.events)
        } catch {
            problem = UserFacingError("That fact couldn't be kept. Nothing was changed.")
        }
        await reload()
    }

    func forget(_ item: NotebookItem) async {
        if editing == item.id { editing = nil }
        await trash?(item)
        await reload()
    }

    /// Saves a new fact or an edit, in the person's own words. Returns whether it was saved.
    @discardableResult
    func save(_ text: String, editing item: NotebookItem? = nil) async -> Bool {
        problem = nil
        do {
            guard try await ProfileFacts.write(text, editing: item, notebook: runtime.notebook, events: runtime.events) != nil else { return false }
        } catch {
            problem = UserFacingError("That fact couldn't be saved. Nothing was changed.")
            return false
        }
        editing = nil
        adding = false
        await reload()
        return true
    }
}
