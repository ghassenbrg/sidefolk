import Foundation

/// The tools that let the user, Sidefolk's agent and other agents set watchers up and manage them.
/// Every one of them runs through `ToolExecutor`, so Guard and the Activity log see each call.
public enum WatchTools {
    /// - Parameters:
    ///   - parser: reads a report's end ("until 6pm") with the user's idea of morning and evening.
    ///   - here: where the person is, when they share it (D48).
    public static func make(engine: WatcherEngine, parser: @escaping @Sendable () -> WhenParser = { WhenParser() },
                            here: @escaping @Sendable () -> KnownPlace? = { nil }) -> [any Tool] {
        [
            WatchCreateTool(engine: engine), WatchCommandTool(engine: engine, parser: parser), WatchReportTool(engine: engine, parser: parser, here: here),
            WatchListTool(engine: engine), WatchStopTool(engine: engine), WatchPauseTool(engine: engine), WatchResumeTool(engine: engine),
        ]
    }
}

// MARK: Wording shared by the tools

/// How watchers are described: for people in the app's language, and `…ForModel` in English for the
/// tool results a model reads (DECISIONS D28).
enum WatchWords {
    /// "5 min", "30 s", "2 h", "3 days".
    static func every(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<90: seconds >= 60 ? String(localized: "1 min") : String(localized: "\(Int(seconds.rounded())) s")
        case ..<5400: String(localized: "\(Int((seconds / 60).rounded())) min")
        case ..<129_600: String(localized: "\(Int((seconds / 3600).rounded())) h")
        default: String(localized: "\(Int((seconds / 86400).rounded())) days")
        }
    }

    static func everyForModel(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<90: seconds >= 60 ? "1 min" : "\(Int(seconds.rounded())) s"
        case ..<5400: "\(Int((seconds / 60).rounded())) min"
        case ..<129_600: "\(Int((seconds / 3600).rounded())) h"
        default: "\(Int((seconds / 86400).rounded())) days"
        }
    }

    /// What the watcher will tell you, in a few words: "when it changes".
    static func promise(_ w: Watcher) -> String {
        switch w.kind {
        case WatchKind.urlChange:
            let c = PageCondition(w.condition)
            if let text = c.contains { return String(localized: "when it says “\(text.clipped(60))”") }
            if let text = c.notContains { return String(localized: "when “\(text.clipped(60))” is gone") }
            return String(localized: "when it changes")
        case WatchKind.siteStatus:
            switch w.condition.string("becomes") {
            case "up": return String(localized: "when it's back up")
            case "down": return String(localized: "when it goes down")
            default: return String(localized: "when it goes down or comes back")
            }
        case WatchKind.fileAppears:
            return w.condition["gone"]?.boolValue == true ? String(localized: "when it's gone") : String(localized: "when it appears")
        case WatchKind.fileChanges: return String(localized: "when it changes")
        case WatchKind.folderNewFile: return String(localized: "when a new file lands")
        case WatchKind.processExits: return String(localized: "when it quits")
        case WatchKind.command:
            let c = CommandCondition(w.condition)
            if let code = c.exitCode {
                return code == 0 ? String(localized: "when it succeeds") : String(localized: "when it exits with code \(code)")
            }
            if let text = c.outputContains { return String(localized: "when its output has “\(text.clipped(60))”") }
            return String(localized: "when its output changes")
        default: return String(localized: "when something happens")
        }
    }

    static func promiseForModel(_ w: Watcher) -> String {
        switch w.kind {
        case WatchKind.urlChange:
            let c = PageCondition(w.condition)
            if let text = c.contains { return "when it says “\(text.clipped(60))”" }
            if let text = c.notContains { return "when “\(text.clipped(60))” is gone" }
            return "when it changes"
        case WatchKind.siteStatus:
            switch w.condition.string("becomes") {
            case "up": return "when it's back up"
            case "down": return "when it goes down"
            default: return "when it goes down or comes back"
            }
        case WatchKind.fileAppears: return w.condition["gone"]?.boolValue == true ? "when it's gone" : "when it appears"
        case WatchKind.fileChanges: return "when it changes"
        case WatchKind.folderNewFile: return "when a new file lands"
        case WatchKind.processExits: return "when it quits"
        case WatchKind.command:
            let c = CommandCondition(w.condition)
            if let code = c.exitCode { return code == 0 ? "when it succeeds" : "when it exits with code \(code)" }
            if let text = c.outputContains { return "when its output has “\(text.clipped(60))”" }
            return "when its output changes"
        default: return "when something happens"
        }
    }

    /// The name a new watcher gets when none is given; people see it, so it is in their language.
    static func defaultTitle(kind: String, config: JSONValue) -> String {
        switch kind {
        case WatchKind.urlChange, WatchKind.siteStatus:
            // Typed as "example.com/pricing", so give it the https:// it will be watched with before naming it.
            return (try? WebTarget.normalise(config.string("url"), allowLocal: true)).map(WebTarget.displayName)
                ?? (config.string("url") ?? String(localized: "a web page")).clipped(70)
        case WatchKind.folderNewFile:
            return String(localized: "\(WatchedPath.name(config.string("path") ?? "")) folder")
        case WatchKind.fileAppears, WatchKind.fileChanges:
            return WatchedPath.name(config.string("path") ?? "")
        case WatchKind.processExits:
            return ProcessExitsProbe.label(config)
        case WatchKind.command:
            return (config.string("command") ?? String(localized: "command")).clipped(40)
        case WatchKind.metric:
            return config.string("metric").flatMap(Metric.init(rawValue:))?.title ?? kind
        case WatchKind.weather:
            let place = config.string("place") ?? ""
            return (WeatherQuantity(rawValue: config.string("quantity") ?? "") ?? .temperature).title(place)
        default:
            return kind
        }
    }

    /// "next check in 5 min".
    static func state(_ w: Watcher, now: Date) -> String {
        switch w.state {
        case .active:
            guard let next = w.nextCheckAt else { return String(localized: "active") }
            let wait = next.timeIntervalSince(now)
            return wait <= 5 ? String(localized: "checking now") : String(localized: "next check in \(every(wait))")
        case .paused: return String(localized: "paused")
        case .triggered: return String(localized: "done (it fired)")
        case .expired: return String(localized: "expired")
        case .error: return String(localized: "stuck: \(w.lastError ?? String(localized: "unknown problem"))")
        }
    }

    static func stateForModel(_ w: Watcher, now: Date) -> String {
        switch w.state {
        case .active:
            guard let next = w.nextCheckAt else { return "active" }
            let wait = next.timeIntervalSince(now)
            return wait <= 5 ? "checking now" : "next check in \(everyForModel(wait))"
        case .paused: return "paused"
        case .triggered: return "done (it fired)"
        case .expired: return "expired"
        case .error: return "stuck: \(w.lastError ?? "unknown problem")"
        }
    }
}

enum WatchInput {
    static func level(_ input: JSONValue, caller: Caller) throws -> AttentionLevel {
        guard let text = input.string("level") else { return .attention }
        guard let level = AttentionLevel(rawValue: text.lowercased()), level != .ambient else {
            throw ToolError.invalidInput(String(localized: "“level” must be gentle, attention or critical."))
        }
        // Only the user's own request may be critical.
        return (level == .critical && caller != .user) ? .attention : level
    }

    static func mode(_ input: JSONValue) throws -> Watcher.Mode {
        guard let text = input.string("mode") else { return .once }
        // A report is asked for with watch.report or report=true, which bring its floor and its end with it.
        guard let mode = Watcher.Mode(rawValue: text.lowercased()), mode != .report else {
            throw ToolError.invalidInput(String(localized: "“mode” must be once or repeat."))
        }
        return mode
    }

    static func interval(_ input: JSONValue) throws -> TimeInterval {
        guard let minutes = input["interval_minutes"]?.doubleValue else { return 0 }
        guard minutes > 0, minutes <= 7 * 24 * 60 else { throw ToolError.invalidInput(String(localized: "“interval_minutes” must be between a fraction of a minute and 7 days.")) }
        return minutes * 60
    }

    static func watchError(_ error: any Error) -> any Error {
        if let e = error as? WatchError {
            switch e {
            case .notFound(let m): return ToolError.notFound(m)
            case .notAllowed(let m), .limit(let m): return ToolError.unavailable(m)
            case .invalid(let m): return ToolError.invalidInput(m)
            case .unknownKind: return ToolError.unavailable(e.description)
            }
        }
        return error
    }

    /// Finds the watcher the caller means by id, a unique id prefix, or its title. Callers can only reach watchers they may manage.
    static func resolve(_ reference: String, caller: Caller, engine: WatcherEngine) async throws -> Watcher {
        let ref = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let mine = await engine.list().filter { WatchSource.canManage(caller: caller, watcherSource: $0.source) }
        if let exact = mine.first(where: { $0.id == ref }) { return exact }
        func pick(_ matches: [Watcher]) throws -> Watcher? {
            if matches.count > 1 {
                // An error isn't marked untrusted, so only the user's own titles are quoted in it (T3).
                let names = matches.prefix(4).map { w in
                    WatchSource.isUserSourced(w.source) ? "“\(w.title)” (\(w.id.prefix(6)))"
                        : String(localized: "one from another app or agent (\(String(w.id.prefix(6))))")
                }.joined(separator: ", ")
                throw ToolError.invalidInput(String(localized: "That matches more than one watcher: \(names). Use the id."))
            }
            return matches.first
        }
        if ref.count >= 4, let w = try pick(mine.filter { $0.id.hasPrefix(ref) }) { return w }
        if let w = try pick(mine.filter { $0.title.caseInsensitiveCompare(ref) == .orderedSame }) { return w }
        if ref.count >= 3, let w = try pick(mine.filter { $0.title.range(of: ref, options: .caseInsensitive) != nil }) { return w }
        throw ToolError.notFound(String(localized: "a watcher called “\(ref.clipped(60))”"))
    }
}

// MARK: watch.create

struct WatchCreateTool: Tool {
    let engine: WatcherEngine

    var spec: ToolSpec {
        ToolSpec(
            name: "watch.create", title: String(localized: "Watch something"),
            description: """
            Keep an eye on something and tell the user when it happens, even while they are busy. kind: \
            url_change (a web page changed, or now says/stops saying some words), site_status (a website went down or came back up), \
            file_appears (a file showed up, or disappeared with gone=true), file_changes (a file was modified), \
            folder_new_file (a new file landed in a folder, e.g. a finished download), process_exits (a program quit; target is its name or process number). \
            target is the web address, the full path, or the program. Checks are cheap and run on a gentle schedule.
            """,
            inputSchema: Schema.object([
                "kind": Schema.string("What to watch.", enum: WatchKind.creatable),
                "target": Schema.string("Web address, full path of a file or folder, or program name / process number."),
                "title": Schema.string("Short name for the watcher (optional)."),
                "contains": Schema.string("url_change: tell me when the page says this."),
                "not_contains": Schema.string("url_change: tell me when the page stops saying this."),
                "becomes": Schema.string("site_status: which change matters.", enum: ["up", "down", "any"]),
                "gone": Schema.boolean("file_appears: tell me when the file disappears instead."),
                "pattern": Schema.string("folder_new_file: only files matching this pattern, like *.pdf."),
                "interval_minutes": Schema.number("Minutes between checks. Web pages: at least 5, sites: at least 1. Usually leave it out."),
                "mode": Schema.string("once (default) stops after telling the user; repeat keeps going.", enum: ["once", "repeat"]),
                "level": Schema.string("How loudly to tell the user (default attention).", enum: ["gentle", "attention", "critical"]),
            ], required: ["kind", "target"]),
            risk: .low, capabilities: [.watch, .network, .filesRead], category: .watch, mutates: true, external: true)
    }

    func summary(for input: JSONValue) -> String {
        let target = (input.string("target") ?? String(localized: "something")).clipped(120)
        switch input.string("kind") {
        case WatchKind.urlChange:
            if let text = input.string("contains") { return String(localized: "Watch \(target) until it says “\(text.clipped(40))”") }
            return String(localized: "Watch \(target) for changes")
        case WatchKind.siteStatus: return String(localized: "Watch whether \(target) is up")
        case WatchKind.fileAppears:
            return input["gone"]?.boolValue == true ? String(localized: "Watch for \(target) to disappear") : String(localized: "Watch for \(target) to appear")
        case WatchKind.fileChanges: return String(localized: "Watch \(target) for changes")
        case WatchKind.folderNewFile: return String(localized: "Watch \(target) for new files")
        case WatchKind.processExits: return String(localized: "Tell you when \(target) quits")
        default: return String(localized: "Watch \(target)")
        }
    }

    func scope(for input: JSONValue) -> ToolScope {
        guard let target = input.string("target") else { return .none }
        switch input.string("kind") {
        case WatchKind.urlChange, WatchKind.siteStatus:
            let text = target.contains("://") ? target : WebTarget.defaultScheme(for: target) + target
            return ToolScope(url: URL(string: text)?.absoluteString ?? text)
        case WatchKind.fileAppears, WatchKind.fileChanges, WatchKind.folderNewFile:
            return ToolScope(readPaths: [(target as NSString).expandingTildeInPath])
        default:
            return .none
        }
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let kind = input.string("kind"), WatchKind.creatable.contains(kind) else {
            throw ToolError.invalidInput(String(localized: "“kind” must be one of \(WatchKind.creatable.joined(separator: ", "))."))
        }
        guard let target = input.string("target") else { throw ToolError.invalidInput(String(localized: "Tell me what to watch (“target”).")) }

        var config: JSONValue = .object([:])
        var condition: JSONValue = .object([:])
        switch kind {
        case WatchKind.urlChange:
            config = ["url": .string(target)]
            if let text = input.string("contains") { condition = condition.setting("contains", .string(text)) }
            if let text = input.string("not_contains") { condition = condition.setting("not_contains", .string(text)) }
        case WatchKind.siteStatus:
            config = ["url": .string(target)]
            if let becomes = input.string("becomes") { condition = ["becomes": .string(becomes)] }
        case WatchKind.fileAppears:
            config = ["path": .string(target)]
            if input["gone"]?.boolValue == true { condition = ["gone": true] }
        case WatchKind.fileChanges:
            config = ["path": .string(target)]
        case WatchKind.folderNewFile:
            config = ["path": .string(target)]
            if let pattern = input.string("pattern") { config = config.setting("pattern", .string(pattern)) }
        default: // process_exits
            let lower = target.lowercased()
            let digits = lower.hasPrefix("pid") ? lower.drop(while: { !$0.isNumber }) : Substring(lower)
            if let pid = Int(digits.trimmingCharacters(in: .whitespaces)), pid > 0 { config = ["pid": .number(Double(pid))] }
            else { config = ["name": .string(target.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))) ] }
        }
        // Reaching this Mac or the local network is something only the user can ask for (docs/SECURITY.md T11).
        // Their own typed request or button may ("tell me when localhost:3000 is up"); an agent, an external
        // client, an extension or a turn that has read outside content may not. There is no such option in the schema.
        if context.caller == .user, !context.tainted, kind == WatchKind.urlChange || kind == WatchKind.siteStatus {
            config = config.setting("allow_local", true)
        }

        let title = input.string("title") ?? WatchWords.defaultTitle(kind: kind, config: config)
        let requested = try WatchInput.interval(input)
        let watcher = Watcher(kind: kind, title: title, config: config, condition: condition, intervalS: requested,
                              mode: try WatchInput.mode(input), level: try WatchInput.level(input, caller: context.caller),
                              source: WatchSource.string(for: context), now: context.now)
        let added: Watcher
        do { added = try await engine.add(watcher) } catch { throw WatchInput.watchError(error) }
        let look = await engine.firstLook(of: added.id, polite: context.caller != .user)
        return WatchResults.started(await engine.watcher(id: added.id) ?? added, requested: requested, engine: engine, look: look)
    }
}

enum WatchResults {
    static func started(_ w: Watcher, requested: TimeInterval, engine: WatcherEngine, look: FirstLook = FirstLook()) -> ToolResult {
        let every = WatchWords.everyForModel(w.intervalS)
        var text = "Watching \(w.title) every \(every); I'll tell the user \(WatchWords.promiseForModel(w)). Its id is \(w.id)."
        var title = String(localized: "Watching \(w.title) every \(WatchWords.every(w.intervalS))")
        var subtitle = String(localized: "I'll tell you \(WatchWords.promise(w))")
        // The first look has already gone wrong: say so instead of promising something that is not happening yet.
        if let trouble = WatchTrouble(w, look) {
            title = trouble.title
            subtitle = trouble.subtitle
            text = "Started watching \(w.title) (every \(every)), but \(trouble.forTheModel) The user has been told. Its id is \(w.id)."
        }
        if requested > 0, w.intervalS > requested { text += " That's the shortest gap allowed for this kind of watcher." }
        if let expires = w.expiresAt {
            text += " It stops on its own after \(WatchWords.everyForModel(expires.timeIntervalSince(w.createdAt)))."
        }
        let card = ResultCard(kind: .watcher, title: title, subtitle: subtitle,
                              detail: w.mode == .repeat ? String(localized: "Keeps going until you stop it") : String(localized: "Stops after telling you once"),
                              refId: w.id, url: w.config.string("url"))
        let id = w.id
        let undo = UndoAction(label: String(localized: "Stopped watching \(w.title)")) { _ = await engine.remove(id) }
        return ToolResult(text: text, card: card, undo: undo)
    }
}

// MARK: watch.command

struct WatchCommandTool: Tool {
    let engine: WatcherEngine
    var parser: @Sendable () -> WhenParser = { WhenParser() }

    var spec: ToolSpec {
        ToolSpec(
            name: "watch.command", title: String(localized: "Watch with a command"),
            description: """
            Run a shell command on a schedule and tell the user when the result matches (it exits with a given code, \
            its output has some words, or its output changes). With report=true it instead shows the output's last line \
            every time, live beside the companion (every_seconds, 10 at the fastest; a faster request is raised and the result \
            says so; it stops after 1 hour when faster than once a minute, otherwise after 1 day, unless until or until_stopped). \
            The user approves the exact command first unless they turned on Full access. Prefer watch.create when a web page, \
            file, folder or program can be watched directly, and watch.report for CPU, memory, battery, disk, network or the weather.
            """,
            inputSchema: Schema.object([
                "command": Schema.string("The shell command, exactly as it should run."),
                "title": Schema.string("Short name for the watcher (optional)."),
                "exit_code": Schema.integer("Tell me when the command exits with this code (0 = success).", minimum: 0, maximum: 255),
                "output_contains": Schema.string("Tell me when the output contains this text."),
                "changed": Schema.boolean("Tell me when the output changes (default when nothing else is given)."),
                "cwd": Schema.string("Full path of a folder to run in (optional)."),
                "interval_minutes": Schema.number("Minutes between runs, at least 1 (default 5)."),
                "mode": Schema.string("once (default) stops after telling the user; repeat keeps going.", enum: ["once", "repeat"]),
                "level": Schema.string("How loudly to tell the user (default attention).", enum: ["gentle", "attention", "critical"]),
                "report": Schema.boolean("Show the output every time instead of waiting for a match."),
                "every_seconds": Schema.number("report: seconds between runs, as the user asked (10 at the fastest)."),
                "until": Schema.string("report: when to stop, in the user's words (\"6pm\", \"in 2 hours\")."),
                "until_stopped": Schema.boolean("report: true when the user said to keep going until they stop it."),
                "notify": Schema.boolean("report: true only when the user asked for a notification each time."),
            ], required: ["command"]),
            risk: .high, capabilities: [.watch, .shell], category: .watch, mutates: true, external: false)
    }

    func summary(for input: JSONValue) -> String { String(localized: "Run “\((input.string("command") ?? "").clipped(160))” on a schedule") }

    func scope(for input: JSONValue) -> ToolScope {
        var scope = ToolScope(command: input.string("command"))
        if let cwd = input.string("cwd") { scope.readPaths = [(cwd as NSString).expandingTildeInPath] }
        return scope
    }

    /// Refused before the approval card: a command written while untrusted content steered the turn is
    /// never run, so asking the user to approve it would be pointless.
    func refusal(for input: JSONValue, context: ToolContext) -> String? {
        guard !WatchSource.mayRunCommands(WatchSource.string(for: context)) else { return nil }
        if context.tainted, ["user", "agent"].contains(context.caller.kind) {
            return String(localized: """
                I can't set up a command watcher in this conversation: it has read content from outside, \
                so the command might not be the user's own. Ask again in a new conversation.
                """)
        }
        return String(localized: "Only you, or Sidefolk with your approval, can set up a command watcher.")
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        // Defence in depth: Guard never offers this tool to these callers, and the engine refuses them too.
        if let why = refusal(for: input, context: context) { throw ToolError.unavailable(why) }
        guard let command = input.string("command") else { throw ToolError.invalidInput(String(localized: "Tell me which command to run.")) }
        var config: JSONValue = ["command": .string(command)]
        if let cwd = input.string("cwd") { config = config.setting("cwd", .string(cwd)) }
        if input["report"]?.boolValue == true { return try await report(command, config: config, input, context: context) }
        var condition: JSONValue = .object([:])
        if let code = input["exit_code"]?.intValue { condition = ["exit_code": .number(Double(code))] }
        else if let text = input.string("output_contains") { condition = ["output_contains": .string(text)] }
        else { condition = ["changed": true] }

        let requested = try WatchInput.interval(input)
        let watcher = Watcher(kind: WatchKind.command, title: input.string("title") ?? WatchWords.defaultTitle(kind: WatchKind.command, config: config),
                              config: config, condition: condition, intervalS: requested,
                              mode: try WatchInput.mode(input), level: try WatchInput.level(input, caller: context.caller),
                              source: WatchSource.string(for: context), now: context.now)
        let added: Watcher
        do { added = try await engine.add(watcher) } catch { throw WatchInput.watchError(error) }
        let look = await engine.firstLook(of: added.id, polite: false)
        return WatchResults.started(await engine.watcher(id: added.id) ?? added, requested: requested, engine: engine, look: look)
    }
}

extension WatchCommandTool {
    /// report=true: the output every time, live, with a report's floor and end.
    func report(_ command: String, config: JSONValue, _ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        var config = config
        if input["notify"]?.boolValue == true { config = config.setting("notify", true) }
        let end = try Report.end(input, now: context.now, parser: parser())
        if end == nil, input["until_stopped"]?.boolValue == true { config = config.setting("until_stopped", true) }
        let requested = try Report.interval(input)
        let watcher = Watcher(kind: WatchKind.command, title: input.string("title") ?? WatchWords.defaultTitle(kind: WatchKind.command, config: config),
                              config: config, intervalS: requested, mode: .report, expiresAt: end,
                              source: WatchSource.string(for: context), now: context.now)
        return try await Report.start(watcher, requested: requested, engine: engine, context: context)
    }
}

/// How the card that confirms a new watcher words a first look that already went wrong. The watcher stays on
/// (a site that is down is often exactly what someone wants to wait out); the person just hears it straight.
struct WatchTrouble {
    let title: String
    let subtitle: String
    /// The same thing as one sentence for the model, which should pass it on.
    let forTheModel: String

    init?(_ w: Watcher, _ look: FirstLook) {
        guard let why = look.problem ?? look.note else { return nil }
        let name = w.title
        switch w.kind {
        case WatchKind.siteStatus:
            title = String(localized: "I can't reach \(name) right now")
            subtitle = w.condition.string("becomes") == "down"
                ? String(localized: "\(Self.sentence(why)) It's already down, so I'll tell you if it comes back and goes down again.")
                : String(localized: "\(Self.sentence(why)) I'll keep checking and tell you when it's back up.")
            forTheModel = "it isn't answering right now (\(Self.plain(why))). I'll keep checking."
        case WatchKind.urlChange:
            title = String(localized: "I can't reach \(name) right now")
            subtitle = String(localized: "\(Self.sentence(why)) I'll keep trying.")
            forTheModel = "I can't reach it right now (\(Self.plain(why))). I'll keep trying."
        case WatchKind.processExits:
            title = Self.plain(why)
            subtitle = String(localized: "I'll tell you if it starts and then quits.")
            forTheModel = "\(Self.plain(why)). I'll tell the user if it starts and then quits."
        default:
            title = String(localized: "I can't check \(name) right now")
            subtitle = String(localized: "\(Self.sentence(why)) I'll keep trying.")
            forTheModel = "the first check failed (\(Self.plain(why))). I'll keep trying."
        }
    }

    private static func plain(_ s: String) -> String { s.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }
    private static func sentence(_ s: String) -> String { plain(s) + "." }
}

// MARK: watch.list / stop / pause / resume

struct WatchListTool: Tool {
    let engine: WatcherEngine

    var spec: ToolSpec {
        ToolSpec(name: "watch.list", title: String(localized: "List watchers"), description: "List what Sidefolk is watching, with each watcher's id and state.",
                 inputSchema: Schema.object([:]), risk: .low, capabilities: [.watch], category: .watch, mutates: false, external: true)
    }

    func summary(for input: JSONValue) -> String { String(localized: "List what I'm watching") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let all = await engine.list().filter { WatchSource.canManage(caller: context.caller, watcherSource: $0.source) }
        guard !all.isEmpty else {
            return ToolResult(text: "Nothing is being watched.", card: ResultCard(kind: .list, title: String(localized: "Nothing is being watched")))
        }
        let lines = all.prefix(50).map { w in
            "• \(w.title) (\(w.kind), id \(w.id)): \(WatchWords.stateForModel(w, now: context.now)), every \(WatchWords.everyForModel(w.intervalS))"
                + (w.fireCount > 0 ? ", fired \(w.fireCount)×" : "")
        }
        let shown = all.prefix(50).map { w in
            let line = String(localized: "• \(w.title) (\(w.kind), id \(w.id)): \(WatchWords.state(w, now: context.now)), every \(WatchWords.every(w.intervalS))")
            return w.fireCount > 0 ? line + String(localized: ", fired \(w.fireCount)×") : line
        }
        let card = ResultCard(kind: .list, title: String(localized: "\(all.count) watchers"), detail: shown.joined(separator: "\n"))
        // Titles made by other agents, extensions, routines or a tainted turn are not the user's words.
        let outside = all.contains { !WatchSource.isUserSourced($0.source) }
        return ToolResult(text: lines.joined(separator: "\n"), card: card, untrusted: outside)
    }
}

struct WatchStopTool: Tool {
    let engine: WatcherEngine

    var spec: ToolSpec {
        ToolSpec(name: "watch.stop", title: String(localized: "Stop watching"), description: "Stop and remove a watcher. id is its id or its title.",
                 inputSchema: Schema.object(["id": Schema.string("The watcher's id (or its title).")], required: ["id"]),
                 risk: .low, capabilities: [.watch], category: .watch, mutates: true, external: true)
    }

    func summary(for input: JSONValue) -> String { String(localized: "Stop watching “\((input.string("id") ?? "").clipped(60))”") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let w = try await WatchInput.resolve(input.string("id") ?? "", caller: context.caller, engine: engine)
        guard let removed = await engine.remove(w.id) else { throw ToolError.notFound(String(localized: "that watcher")) }
        let engine = self.engine
        let report = removed.mode == .report
        let undo = UndoAction(label: report ? String(localized: "Showing \(removed.title) again") : String(localized: "Watching \(removed.title) again")) {
            _ = try await engine.add(removed)
        }
        let title = report ? String(localized: "Stopped showing \(removed.title)") : String(localized: "Stopped watching \(removed.title)")
        return ToolResult(text: report ? "Stopped showing \(removed.title)." : "Stopped watching \(removed.title).",
                          card: ResultCard(kind: .watcher, title: title, refId: removed.id),
                          undo: undo, untrusted: !WatchSource.isUserSourced(removed.source))
    }
}

struct WatchPauseTool: Tool {
    let engine: WatcherEngine

    var spec: ToolSpec {
        ToolSpec(name: "watch.pause", title: String(localized: "Pause a watcher"), description: "Pause a watcher without removing it. id is its id or its title.",
                 inputSchema: Schema.object(["id": Schema.string("The watcher's id (or its title).")], required: ["id"]),
                 risk: .low, capabilities: [.watch], category: .watch, mutates: true, external: false)
    }

    func summary(for input: JSONValue) -> String { String(localized: "Pause “\((input.string("id") ?? "").clipped(60))”") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let w = try await WatchInput.resolve(input.string("id") ?? "", caller: context.caller, engine: engine)
        let paused: Watcher
        do { paused = try await engine.pause(w.id) } catch { throw WatchInput.watchError(error) }
        let engine = self.engine
        let undo = UndoAction(label: String(localized: "Resumed \(paused.title)")) { _ = try await engine.resume(paused.id) }
        return ToolResult(text: "Paused \(paused.title).", card: ResultCard(kind: .watcher, title: String(localized: "Paused \(paused.title)"), refId: paused.id),
                          undo: undo, untrusted: !WatchSource.isUserSourced(paused.source))
    }
}

struct WatchResumeTool: Tool {
    let engine: WatcherEngine

    var spec: ToolSpec {
        ToolSpec(name: "watch.resume", title: String(localized: "Resume a watcher"),
                 description: "Start a paused, finished or expired watcher again. id is its id or its title.",
                 inputSchema: Schema.object(["id": Schema.string("The watcher's id (or its title).")], required: ["id"]),
                 risk: .low, capabilities: [.watch], category: .watch, mutates: true, external: false)
    }

    func summary(for input: JSONValue) -> String { String(localized: "Resume “\((input.string("id") ?? "").clipped(60))”") }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let w = try await WatchInput.resolve(input.string("id") ?? "", caller: context.caller, engine: engine)
        let resumed: Watcher
        do { resumed = try await engine.resume(w.id) } catch { throw WatchInput.watchError(error) }
        let engine = self.engine
        let undo = UndoAction(label: String(localized: "Paused \(resumed.title)")) { _ = try await engine.pause(resumed.id) }
        return ToolResult(text: "Watching \(resumed.title) again.",
                          card: ResultCard(kind: .watcher, title: String(localized: "Watching \(resumed.title) again"), refId: resumed.id),
                          undo: undo, untrusted: !WatchSource.isUserSourced(resumed.source))
    }
}
