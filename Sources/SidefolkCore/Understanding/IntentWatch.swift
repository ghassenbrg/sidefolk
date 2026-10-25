import Foundation

/// "Tell me when ..." and "watch ...": web pages, sites, files, folders and processes.
extension IntentParser {
    // MARK: Patterns

    private static let tellMe = IntentPattern(
        #"(?:tell|let|notify|ping|alert|message|remind)\s+me(?:\s+know)?,?\s+(?:when|once|if|as\s+soon\s+as|the\s+moment|the\s+second)\s+(?<rest>.+)"#
    )
    private static let watchDirect = IntentPattern(
        #"(?:watch|monitor|keep\s+an\s+eye\s+on|keep\s+watching|track\s+changes\s+(?:on|to))\s+(?:the\s+|this\s+|that\s+)?(?:(?:page|site|website|url|link)\s+)?(?<target>\S+)(?:\s+for\s+(?<what>.+))?"#
    )
    private static let watchFolder = IntentPattern(#"(?:watch|monitor|keep\s+an\s+eye\s+on)\s+(?:my\s+|the\s+)?(?<place>downloads|desktop|documents)(?:\s+folder)?"#)

    private static let downloadDone = IntentPattern(
        #"(?:the\s+|my\s+|this\s+|that\s+|a\s+|the\s+current\s+)?downloads?\s+(?:finish(?:es)?|is\s+(?:finished|done|complete|completed)|complete[sd]?|ends?|done)"#
    )
    private static let fileAppears = IntentPattern(
        #"(?<file>.+?)\s+(?:appears|shows\s+up|arrives|lands|is\s+created|gets\s+created|is\s+downloaded|gets\s+downloaded|is\s+there|exists|is\s+saved|is\s+added|gets\s+added)(?:\s+(?:in|on|to|at|under|inside)\s+(?<place>.+))?"#
    )
    private static let siteStatus = IntentPattern(
        #"(?<target>\S+)\s+(?:(?:is|are|goes|comes|gets|came|went)\s+)?(?:back\s+)?(?<state>up|online|down|offline|unreachable|available|reachable|live|working|responding|alive)(?:\s+again)?"#
    )
    private static let urlChanges = IntentPattern(
        #"(?<target>\S+)\s+(?:changes|changed|is\s+changed|updates|is\s+updated|gets\s+updated|has\s+changed|has\s+been\s+(?:updated|changed)|is\s+modified|gets\s+modified)"#
    )
    private static let anythingChanges = IntentPattern(
        #"(?:anything|something|there(?:'s|\s+is)\s+(?:a|any)\s+change)\s+(?:changes\s+|changed\s+)?(?:on|at|in|to)\s+(?<target>\S+)"#
    )
    private static let urlContains = IntentPattern(#"(?<target>\S+)\s+(?:contains|mentions|says|has|includes|shows|lists)\s+(?<text>.+)"#)
    private static let processExits = IntentPattern(
        #"(?:the\s+)?(?<name>[\w.\-]+)(?:\s+(?:process|command|job|program))?\s+(?:finishes|finished|exits|exited|ends|ended|completes|completed|stops|stopped|quits|terminates|is\s+(?:done|finished|complete|completed))"#
    )
    private static let newFile = IntentPattern(#"(?:a\s+|any\s+|the\s+)?(?:new\s+)?(?:file|files|something|anything|document|documents)"#)
    private static let changeWords = IntentPattern(#"(?:any\s+)?(?:changes?|updates?|news|new\s+content)"#)

    /// "the server is back up", "my site goes down", "the dev api is up again": a site is meant but no address is given.
    private static let anySiteStatus = IntentPattern(
        #"(?:(?:the|my|our|this|that)\s+)?(?:[\w-]+\s+){0,2}?(?:server|site|website|web\s*site|api|app|service|backend|frontend|host|localhost|database|db)\s+(?:(?:is|are|goes|comes|gets|came|went)\s+)?(?:(?:back\s+)?(?<state>up|online|down|offline|unreachable|available|reachable|live|working|responding|alive)|back)(?:\s+again)?"#
    )
    /// "my site changes", "the pricing page updates": a page is meant but no address is given.
    private static let anyPageChanges = IntentPattern(
        #"(?:(?:the|my|our|this|that)\s+)?(?:[\w-]+\s+){0,2}?(?:site|website|web\s*site|page|web\s*page|docs|documentation|blog)\s+(?:changes|changed|updates|is\s+updated|gets\s+updated|has\s+changed|has\s+been\s+(?:updated|changed)|is\s+modified|gets\s+modified)"#
    )

    /// Words that are not the name of a program.
    private static let notAProcess: Set<String> = [
        "it", "this", "that", "everything", "build", "test", "tests", "job", "task", "command", "process", "upload", "export", "install",
        "backup", "sync", "deploy", "download", "downloads", "he", "she", "they", "we", "i", "you", "work", "meeting", "class", "the",
    ]
    /// Top-level domains accepted for addresses typed without "https://". Not included: md, sh, py, rs, zip,
    /// mov, pl, which are far more often file extensions.
    private static let domains: Set<String> = [
        "com", "org", "net", "io", "dev", "app", "co", "ai", "me", "xyz", "info", "biz", "edu", "gov", "us", "uk", "de", "fr", "es", "it",
        "nl", "se", "no", "fi", "dk", "ch", "at", "be", "ca", "au", "nz", "jp", "cn", "in", "br", "ru", "tn", "eu", "tv", "gg", "so",
        "page", "site", "online", "tech", "cloud", "store", "blog", "wiki", "shop", "news",
    ]

    // MARK: Entry

    func watch(_ t: String, _ ctx: Context) -> ParsedIntent? {
        if let c = Self.watchFolder.match(t), let place = c["place"], let path = placePath(place) {
            return parsed(WatchIntent(kind: "folder_new_file", target: path))
        }
        if let c = Self.watchDirect.match(t), let target = c["target"], let url = urlTarget(target) {
            var contains: String?
            if let what = c["what"], Self.changeWords.match(what) == nil { contains = what.unquoted }
            return parsed(WatchIntent(kind: "url_change", target: url, contains: contains))
        }
        if let c = Self.tellMe.match(t), let rest = c["rest"] {
            if let intent = classify(rest) { return parsed(intent) }
            if let ask = needsTarget(rest) { return ask }
        }
        return nil
    }

    /// A site or page is meant, but where is not said: ask for the address instead of sending the question to the AI.
    private func needsTarget(_ rest: String) -> ParsedIntent? {
        let hint = "Watch · which address? · no AI"
        if let c = Self.anySiteStatus.match(rest) {
            let down = ["down", "offline", "unreachable"].contains(c["state"]?.lowercased() ?? "")
            return ParsedIntent(intent: .needsTarget(kind: WatchKind.siteStatus, becomes: down ? "down" : "up"), hint: hint)
        }
        if Self.anyPageChanges.match(rest) != nil {
            return ParsedIntent(intent: .needsTarget(kind: WatchKind.urlChange, becomes: nil), hint: hint)
        }
        return nil
    }

    /// Finishes a `.needsTarget` once the person has typed the address: "localhost:3000", "3000", "example.com/status".
    /// Nil when what they typed is not an address (the app can ask again).
    public func watch(address: String, kind: String, becomes: String?) -> ParsedIntent? {
        let typed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        // A bare port number means a server on this Mac.
        let word = typed.allSatisfy(\.isNumber) && (2...5).contains(typed.count) && (Int(typed) ?? 0) <= 65535 ? "localhost:" + typed : typed
        guard let url = urlTarget(word) else { return nil }
        switch kind {
        case WatchKind.siteStatus:
            return parsed(WatchIntent(kind: kind, target: url, contains: becomes == "down" ? "down" : nil))
        case WatchKind.urlChange:
            return parsed(WatchIntent(kind: kind, target: url))
        default:
            return nil
        }
    }

    private func classify(_ rest: String) -> WatchIntent? {
        if Self.downloadDone.match(rest) != nil, let path = placePath("downloads") {
            return WatchIntent(kind: "folder_new_file", target: path)
        }
        if let c = Self.fileAppears.match(rest), let file = c["file"] { return fileWatch(file: file, place: c["place"]) }
        if let c = Self.siteStatus.match(rest), let target = c["target"], let url = urlTarget(target) {
            let down = ["down", "offline", "unreachable"].contains(c["state"]?.lowercased() ?? "")
            return WatchIntent(kind: "site_status", target: url, contains: down ? "down" : nil)
        }
        if let c = Self.urlChanges.match(rest), let target = c["target"], let url = urlTarget(target) {
            return WatchIntent(kind: "url_change", target: url)
        }
        if let c = Self.anythingChanges.match(rest), let target = c["target"], let url = urlTarget(target) {
            return WatchIntent(kind: "url_change", target: url)
        }
        if let c = Self.urlContains.match(rest), let target = c["target"], let url = urlTarget(target), let text = c["text"] {
            return WatchIntent(kind: "url_change", target: url, contains: text.unquoted)
        }
        if let c = Self.processExits.match(rest), let name = c["name"]?.lowercased(), !Self.notAProcess.contains(name), urlTarget(name) == nil {
            return WatchIntent(kind: "process_exits", target: c["name"] ?? name)
        }
        return nil
    }

    private func fileWatch(file raw: String, place: String?) -> WatchIntent? {
        var file = raw.unquoted
        for lead in ["the file ", "a file ", "file ", "the "] where file.lowercased().hasPrefix(lead) { file = String(file.dropFirst(lead.count)) }
        file = file.unquoted
        if Self.newFile.match(file) != nil {
            guard let place, let folder = placePath(place) else { return nil }
            return WatchIntent(kind: "folder_new_file", target: folder)
        }
        let hasExtension = file.range(of: #"\.[A-Za-z0-9]{1,8}$"#, options: .regularExpression) != nil
        guard hasExtension || file.contains("/") else { return nil }
        if file.hasPrefix("~") || file.hasPrefix("/") { return WatchIntent(kind: "file_appears", target: expand(file)) }
        // "Downloads/report.pdf"
        if let slash = file.firstIndex(of: "/"), let folder = placePath(String(file[..<slash])) {
            return WatchIntent(kind: "file_appears", target: folder + String(file[slash...]))
        }
        // A bare name needs a folder to look in; guessing would watch the wrong place silently.
        guard !file.contains("/"), let place, let folder = placePath(place) else { return nil }
        return WatchIntent(kind: "file_appears", target: folder + "/" + file)
    }

    // MARK: Targets

    /// A web address from one word: "https://example.com/x", "example.com/pricing", "localhost:3000", "printer.local:631".
    func urlTarget(_ word: String) -> String? {
        let w = Self.trimmedAddress(word)
        guard !w.isEmpty, !w.contains(" ") else { return nil }
        let lower = w.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: w)?.host == nil ? nil : w
        }
        let hostEnd = lower.firstIndex(where: { "/?#".contains($0) }) ?? lower.endIndex
        let authority = String(lower[..<hostEnd])
        let host = authority.split(separator: ":", maxSplits: 1).first.map(String.init) ?? authority
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }) else { return nil }
        // This Mac, a private address or a name on the home network: plain http, as a dev server or a gadget would speak.
        let isLocal = host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") || Self.isIPv4(host)
        if !isLocal {
            guard labels.count >= 2, let tld = labels.last, Self.domains.contains(String(tld)) else { return nil }
        }
        return (isLocal ? "http://" : "https://") + w
    }

    /// Strips quotes, brackets and sentence punctuation around an address, but keeps a ")" that closes a "(" inside it
    /// (".../Swift_(programming_language)").
    private static func trimmedAddress(_ word: String) -> String {
        var w = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>`,;!?"))
        while w.hasPrefix("(") || w.hasPrefix("[") { w.removeFirst() }
        func count(_ c: Character) -> Int { w.filter { $0 == c }.count }
        while w.hasSuffix(")"), count(")") > count("(") { w.removeLast() }
        while w.hasSuffix("]"), count("]") > count("[") { w.removeLast() }
        return w.trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>`,;!?")).trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func isIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { Int($0).map { (0...255).contains($0) } == true }
    }

    /// "Downloads", "my desktop", "~/Projects/out", "/tmp/x" as an absolute folder path.
    func placePath(_ raw: String) -> String? {
        var name = raw.unquoted
        for lead in ["my ", "the ", "your "] where name.lowercased().hasPrefix(lead) { name = String(name.dropFirst(lead.count)) }
        for tail in [" folder", " directory", " dir"] where name.lowercased().hasSuffix(tail) { name = String(name.dropLast(tail.count)) }
        switch name.lowercased() {
        case "downloads", "download": return home + "/Downloads"
        case "desktop": return home + "/Desktop"
        case "documents": return home + "/Documents"
        case "pictures": return home + "/Pictures"
        case "movies": return home + "/Movies"
        case "music": return home + "/Music"
        case "home": return home
        default:
            return name.hasPrefix("~") || name.hasPrefix("/") ? expand(name) : nil
        }
    }

    private func expand(_ path: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + String(path.dropFirst(1)) }
        return path
    }

    // MARK: Hints

    private func parsed(_ w: WatchIntent) -> ParsedIntent {
        let subject: String
        switch w.kind {
        case "site_status": subject = w.contains == "down" ? "\(display(w.target)) goes down" : "\(display(w.target)) is up"
        case "folder_new_file": subject = "\(abbreviated(w.target)) for new files"
        case "file_appears": subject = abbreviated(w.target)
        case "process_exits": subject = "\(w.target) exits"
        default: subject = w.contains.map { "\(display(w.target)) for “\($0)”" } ?? display(w.target)
        }
        return ParsedIntent(intent: .watch(w), hint: "Watch \(subject) · no AI")
    }

    private func display(_ url: String) -> String {
        var s = url
        for scheme in ["https://", "http://"] where s.lowercased().hasPrefix(scheme) { s = String(s.dropFirst(scheme.count)) }
        return s.hasSuffix("/") ? String(s.dropLast()) : s
    }

    private func abbreviated(_ path: String) -> String {
        path == home ? "~" : (path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path)
    }
}
