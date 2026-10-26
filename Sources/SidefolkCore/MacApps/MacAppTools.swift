import Foundation

/// The tools that reach the Mac's own apps (DECISIONS D38): Apple Notes (list, read, copy into the
/// notebook, and remove after a copy when the person asked to move) and Apple Reminders (read).
/// Like every tool they run through `ToolExecutor`: reading another app's private data is medium
/// risk, its content is untrusted (it taints the turn), and nothing is offered to other agents.
public enum MacAppTools {
    public static func make(runner: any AppleEventsRunner, notebook: NotebookStore, events: EventBus, ledger: AppleNotesLedger,
                            clock: any Clock = SystemClock()) -> [any Tool] {
        let notes = AppleNotes(runner: runner, clock: clock)
        return [
            AppleNotesListTool(notes: notes, ledger: ledger),
            AppleNotesReadTool(notes: notes),
            AppleNotesCopyTool(notes: notes, ledger: ledger, notebook: notebook, events: events),
            AppleNotesRemoveTool(notes: notes, ledger: ledger, notebook: notebook),
            AppleRemindersListTool(reminders: AppleReminders(runner: runner)),
        ]
    }
}

enum MacAppAccess {
    /// What a tool returns when macOS refused: the model reads where the switch is, and the person
    /// gets a card whose button opens that page of System Settings.
    static func permissionResult(_ app: MacApp) -> ToolResult {
        let name = app.displayName
        return ToolResult(
            text: "macOS didn't let Sidefolk use \(app.englishName), so nothing was read or changed. The user can allow it in "
                + "System Settings › Privacy & Security › Automation by switching on \(app.englishName) under Sidefolk; a button "
                + "for that page is shown to them. Tell them, and don't try again until they say they have.",
            card: ResultCard(kind: .info, title: String(localized: "Sidefolk needs your OK to use \(name)"),
                             subtitle: String(localized: "System Settings › Privacy & Security › Automation"),
                             detail: String(localized: "Switch on \(name) under Sidefolk, then ask again."),
                             url: PrivacyPane.automation.rawValue),
            isError: true)
    }

    /// Runs `work`; macOS refusing becomes `permissionResult`, any other Apple Events problem a message.
    static func run(_ app: MacApp, _ work: () async throws -> ToolResult) async throws -> ToolResult {
        do {
            return try await work()
        } catch let error as AppleEventsError {
            if case .notPermitted = error { return permissionResult(app) }
            throw error.userFacing
        }
    }

    /// Text from another app, ready for a tool result: hygiene, one line, capped.
    static func line(_ text: String, _ limit: Int) -> String { ToolFormat.oneLine(ExternalText.clean(text), limit) }

    /// The ids a tool was given: strings, trimmed, unique, in order.
    static func ids(_ input: JSONValue, key: String = "ids", max: Int) throws -> [String] {
        var seen = Set<String>()
        let ids = (input.textList(key) ?? []).filter { seen.insert($0).inserted }
        guard !ids.isEmpty else { throw ToolError.invalidInput(String(localized: "“\(key)” needs at least one note id.")) }
        guard ids.count <= max else { throw UserFacingError("That's too many notes for one step (the limit is \(max)).") }
        return ids
    }
}
