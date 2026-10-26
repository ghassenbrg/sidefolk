import Foundation

/// What a tool of Sidefolk's own extensions (D39) is about to do, as one sentence for its approval card and
/// Activity: "Clone https://github.com/octocat/Hello-World into ~/git/Hello-World" rather than the title and
/// a JSON object. Their text ships in the app, so it may speak for the call; it is built only from the call's
/// exact arguments (T1). Nil when an argument it needs is missing or isn't text: the card then shows the
/// title and the arguments as they are, as it does for everyone else's tools.
enum BuiltInToolSummary {
    static func sentence(extensionId: String, tool: String, input: JSONValue) -> String? {
        func text(_ key: String) -> String? {
            guard let raw = input.string(key) else { return nil }
            let line = ToolFormat.oneLine(ExtensionText.clean(raw), 200)
            return line.isEmpty ? nil : line
        }
        func folder(_ key: String) -> String? { text(key).map { FolderAccess.displayPath(($0 as NSString).expandingTildeInPath) } }
        func places(_ key: String) -> String? {
            let all = (input[key]?.arrayValue ?? []).compactMap(\.stringValue).map { ToolFormat.oneLine(ExtensionText.clean($0), 60) }
            return all.isEmpty || all.contains(where: \.isEmpty) ? nil : Wording.list(all)
        }

        switch (extensionId, tool) {
        case ("dev.sidefolk.git", "clone"):
            guard let url = text("url"), let destination = folder("destination") else { return nil }
            return String(localized: "Clone \(url) into \(destination)", comment: "Approval and Activity: the Git extension clones a repository")
        case ("dev.sidefolk.git", "status"):
            return folder("repository").map { String(localized: "Check the status of the repository in \($0)") }
        case ("dev.sidefolk.git", "pull"):
            return folder("repository").map { String(localized: "Pull the latest changes into \($0)") }
        case ("dev.sidefolk.git", "log"):
            return folder("repository").map { String(localized: "Read the recent commits in \($0)") }
        case ("dev.sidefolk.weather", "forecast"):
            // The place is what leaves the Mac, so the sentence says where it goes.
            return text("place").map { String(localized: "Get the forecast for \($0) from Open-Meteo") }
        case ("dev.sidefolk.world-clock", "current_time"):
            guard input["places"] != nil else { return String(localized: "Look up the time here") }
            return places("places").map { String(localized: "Look up the time in \($0)") }
        case ("dev.sidefolk.world-clock", "convert_time"):
            guard let time = text("time"), let to = places("to") else { return nil }
            guard let from = text("from") else { return String(localized: "Convert \(time) here to the time in \(to)") }
            return String(localized: "Convert \(time) in \(from) to the time in \(to)")
        case ("dev.sidefolk.system-vitals", "battery"):
            return String(localized: "Read the battery's charge")
        case ("dev.sidefolk.system-vitals", "disk"):
            return String(localized: "Read the free disk space")
        case ("dev.sidefolk.system-vitals", "memory"):
            return String(localized: "Read the memory use")
        default:
            return nil
        }
    }
}
