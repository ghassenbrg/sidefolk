import SidefolkCore

// What Settings › Extensions searches and filters (`ExtensionListQuery`, D39): what each row shows, then what its
// details hold, the friendliest first so a match the row doesn't show can be named under it.

extension ExtensionInfo: ExtensionListEntry {
    var isOn: Bool { enabled }

    /// What it may do comes from `hiddenSearchTexts` (core leaves out "No access to…"), not from `permissionLines`.
    var searchTexts: [String] {
        var texts = [name, tagline, description] + toolNames + watcherNames
        if bundled, let example = BuiltInExamples.request(for: id) { texts.append(example) }
        if kind == .mcpServer { texts.append(String(localized: "MCP server")) }
        if fromDraft { texts.append(String(localized: "Written for you")) }
        if !pendingTools.isEmpty { texts.append(String(localized: "Needs review")) }
        return texts + commands + hiddenSearchTexts + [command].compactMap { $0 }
    }

    /// The row in one phrase for VoiceOver: its name, what it does, and anything waiting on the person.
    var accessibilityPhrase: String {
        var parts = [name]
        if !description.isEmpty { parts.append(description) }
        if !pendingTools.isEmpty { parts.append(String(localized: "Needs review")) }
        if let lastError { parts.append(lastError) }
        return parts.joined(separator: ", ")
    }

    /// A search's `hit` as the row shows it: a tool or a watcher says which it is.
    func shownHit(_ hit: String) -> String {
        if toolNames.contains(hit) { return ExtensionWords.tools([hit]) }
        if watcherNames.contains(hit) { return ExtensionWords.watchers([hit]) }
        if commands.contains(hit) { return ExtensionWords.commands([hit]) }
        return hit
    }
}

extension UnavailableExtension: ExtensionListEntry {
    var isOn: Bool { false }
    var searchTexts: [String] { [name, message] }
}

extension SkillInfo {
    var searchTexts: [String] { [name, description, bundled ? String(localized: "Built in") : String(localized: "Yours")] }
}

extension ExtensionDraftInfo {
    var searchTexts: [String] { [title, name, String(localized: "Draft")] }
}
