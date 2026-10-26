import Foundation
import SidefolkCore

/// Plain-language labels for core records, in the companion's voice (docs/VOICE.md).
enum Describe {
    // MARK: Time

    /// "Every weekday", "Every 2 weeks on Mon and Thu", "Every day until 12 Dec": the same words as
    /// cards and notices (`TimeFormat.recurrence`), starting a line.
    static func recurrence(_ r: Recurrence) -> String {
        var text = TimeFormat.recurrence(r, calendar: .autoupdatingCurrent)
        if let until = r.until {
            text = String(localized: "\(text) until \(until.formatted(.dateTime.day().month(.abbreviated)))",
                          comment: "“every day until 12 Dec”")
        }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "every 30 s", "every 5 min", "every 2 h", "every day".
    static func interval(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return String(localized: "every \(s) s") }
        if s < 3600 { return String(localized: "every \(s / 60) min") }
        if s < 86400 { return s % 3600 == 0 ? String(localized: "every \(s / 3600) h") : String(localized: "every \(s / 60) min") }
        return s == 86400 ? String(localized: "every day") : String(localized: "every \(s / 86400) days")
    }

    // MARK: Watchers

    struct WatcherKind {
        var symbol: String
        var label: String
    }

    /// The probe kind as a person would name it, with an icon.
    static func watcherKind(_ kind: String) -> WatcherKind {
        let k = kind.lowercased()
        if k.hasPrefix("ext") || k.contains("/") {
            return WatcherKind(symbol: "puzzlepiece.extension", label: String(localized: "Extension"))
        }
        if k.contains("site") || k.hasSuffix("up") || k.contains("http") {
            return WatcherKind(symbol: "antenna.radiowaves.left.and.right", label: String(localized: "Site"))
        }
        if k.contains("web") || k.contains("page") || k.contains("url") {
            return WatcherKind(symbol: "globe", label: String(localized: "Web page"))
        }
        if k.contains("folder") || k.contains("dir") { return WatcherKind(symbol: "folder", label: String(localized: "Folder")) }
        if k.contains("file") { return WatcherKind(symbol: "doc", label: String(localized: "File")) }
        if k.contains("process") || k.contains("pid") { return WatcherKind(symbol: "cpu", label: String(localized: "Process")) }
        if k.contains("command") || k.contains("shell") { return WatcherKind(symbol: "terminal", label: String(localized: "Command")) }
        if k.contains(".") { return WatcherKind(symbol: "puzzlepiece.extension", label: String(localized: "Extension")) }
        return WatcherKind(symbol: "binoculars", label: String(localized: "Watch"))
    }

    /// What the watcher looks at (a URL, a path, a process), when the config says.
    static func watcherTarget(_ w: Watcher) -> String? {
        for key in ["url", "path", "folder", "file", "process", "name", "command"] {
            if let value = w.config.string(key) {
                if key == "url" { return value.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "") }
                return value.hasPrefix("/") ? FolderAccess.displayPath(value) : value
            }
        }
        return nil
    }

    // MARK: People and agents

    /// "claude-code" → "Claude Code", "codex" → "Codex", anything else title-cased.
    static func agentName(_ raw: String) -> String {
        let k = raw.lowercased()
        if k.hasPrefix("claude") { return "Claude Code" }
        if k.hasPrefix("codex") { return "Codex" }
        if k.hasPrefix("cursor") { return "Cursor" }
        return raw.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// For a notebook item or reminder saved by another agent or an extension: who, e.g. "Claude Code".
    /// Nil when the user or Sidefolk itself made it.
    static func source(_ source: String) -> String? {
        let parts = source.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            // Bare sources are Sidefolk's own ("user", "agent", "cli"…) unless they name a known agent.
            let k = source.lowercased()
            return k.hasPrefix("claude") || k.hasPrefix("codex") || k.hasPrefix("cursor") ? agentName(source) : nil
        }
        switch parts[0] {
        case "external": return agentName(parts[1])
        case "extension": return extensionName(parts[1])
        default: return nil
        }
    }

    /// Who asked, from an activity entry's caller ("agent", "user:you", "external:claude-code").
    static func caller(_ raw: String, companion: String) -> String {
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first ?? raw {
        case "user": return String(localized: "You")
        case "agent": return companion
        case "routine": return String(localized: "Routine")
        case "external": return parts.count > 1 ? agentName(parts[1]) : String(localized: "Agent")
        case "extension": return parts.count > 1 ? extensionName(parts[1]) : String(localized: "Extension")
        default: return raw
        }
    }

    /// "app.sidefolk.system-vitals" → "System Vitals" (the id's last part, made readable).
    static func extensionName(_ id: String) -> String {
        let last = id.split(separator: ".").last.map(String.init) ?? id
        return last.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// "files.move" → "Files move": a readable fallback when a tool's own title isn't known.
    static func toolName(_ name: String) -> String {
        let spaced = name.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    static func callerKind(_ raw: String) -> String {
        String(raw.split(separator: ":", maxSplits: 1).first ?? Substring(raw))
    }

    /// The session's headline: "Claude Code in sidefolk".
    static func session(_ s: AgentSession) -> String {
        let who = agentName(s.agent)
        if let project = s.projectName {
            return String(localized: "\(who) in \(project)", comment: "A thing, then where it is: “Ideas in Sidefolk”, “Claude Code in sidefolk”")
        }
        return s.title ?? who
    }
}
