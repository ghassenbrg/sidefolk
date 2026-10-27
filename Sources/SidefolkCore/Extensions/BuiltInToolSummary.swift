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
        func number(_ key: String) -> String? {
            guard case .number(let n)? = input[key] else { return nil }
            return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        }
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
        case ("dev.sidefolk.system-vitals", "about"):
            return String(localized: "Read this Mac's details")
        case ("dev.sidefolk.weather", "sun_and_moon"):
            return text("place").map { String(localized: "Get sunrise and sunset for \($0) from Open-Meteo") }
        case ("dev.sidefolk.calculator", "calculate"):
            return text("expression").map { String(localized: "Work out \($0)") }
        case ("dev.sidefolk.calculator", "convert_units"):
            guard let value = number("value"), let from = text("from"), let to = text("to") else { return nil }
            return String(localized: "Convert \(value) \(from) to \(to)")
        case ("dev.sidefolk.calculator", "date_math"):
            return String(localized: "Work out a date")
        case ("dev.sidefolk.currency", "convert_currency"):
            guard let amount = number("amount"), let from = text("from"), let to = places("to") else { return nil }
            return String(localized: "Convert \(amount) \(from) to \(to) with the European Central Bank's rates")
        case ("dev.sidefolk.playtime", "chance"):
            return String(localized: "Leave it to chance")
        case ("dev.sidefolk.playtime", "trivia"):
            return String(localized: "Play a round of trivia")
        case ("dev.sidefolk.playtime", "rock_paper_scissors"):
            return String(localized: "Play rock, paper, scissors")
        case ("dev.sidefolk.images", "image_info"), ("dev.sidefolk.pdf", "pdf_info"):
            return folder("path").map { String(localized: "Read the details of \($0)") }
        case ("dev.sidefolk.images", "convert_images"):
            guard let folder = folder("folder") else { return nil }
            return input["remove_location"]?.boolValue == true
                ? String(localized: "Make copies of the pictures in \(folder) without their location")
                : String(localized: "Make converted copies of the pictures in \(folder)")
        case ("dev.sidefolk.pdf", "pdf_text"):
            return folder("path").map { String(localized: "Read the text of \($0)") }
        case ("dev.sidefolk.pdf", "combine_pdfs"):
            return folder("folder").map { String(localized: "Combine PDFs in \($0) into a new one") }
        case ("dev.sidefolk.pdf", "extract_pages"):
            guard let folder = folder("folder"), let file = text("file"), let pages = text("pages") else { return nil }
            return String(localized: "Save pages \(pages) of \(file) as a new PDF in \(folder)")
        case ("dev.sidefolk.qr-codes", "make_qr"):
            return folder("folder").map { String(localized: "Make a QR code picture in \($0)") }
        case ("dev.sidefolk.qr-codes", "read_qr"):
            return folder("path").map { String(localized: "Read the QR code in \($0)") }
        case ("dev.sidefolk.archives", "zip"):
            return folder("folder").map { String(localized: "Make a zip file in \($0)") }
        case ("dev.sidefolk.archives", "unzip"):
            guard let folder = folder("folder"), let file = text("file") else { return nil }
            return String(localized: "Unpack \(file) in \(folder)")
        case ("dev.sidefolk.dev-toolbox", "checksum"):
            return folder("path").map { String(localized: "Work out the checksum of \($0)") }
        case ("dev.sidefolk.feeds", "read_feed"):
            return text("url").map { String(localized: "Read the latest posts from \($0)") }
        default:
            return nil
        }
    }
}
