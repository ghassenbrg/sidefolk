import Foundation

/// The tools that let the user, Sidefolk's agent and other agents set watchers up and manage them.
/// Every one of them runs through `ToolExecutor`, so Guard and the Activity log see each call.
public enum WatchTools {
    public static func make(engine: WatcherEngine) -> [any Tool] {
        [
            WatchCreateTool(engine: engine), WatchCommandTool(engine: engine), WatchListTool(engine: engine),
            WatchStopTool(engine: engine), WatchPauseTool(engine: engine), WatchResumeTool(engine: engine),
        ]
    }
}

// MARK: Wording shared by the tools

enum WatchWords {
    static func every(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<90: seconds >= 60 ? "1 min" : "\(Int(seconds.rounded())) s"
        case ..<5400: "\(Int((seconds / 60).rounded())) min"
        case ..<129_600: "\(Int((seconds / 3600).rounded())) h"
        default: "\(Int((seconds / 86400).rounded())) days"
        }
    }

    /// What the watcher will tell you, in a few words.
    static func promise(_ w: Watcher) -> String {
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

    static func defaultTitle(kind: String, config: JSONValue) -> String {
        switch kind {
        case WatchKind.urlChange, WatchKind.siteStatus:
            return config.string("url").flatMap(URL.init(string:)).map(WebTarget.displayName) ?? (config.string("url") ?? "a web page").clipped(70)
        case WatchKind.folderNewFile:
            return "\(WatchedPath.name(config.string("path") ?? "")) folder"
        case WatchKind.fileAppears, WatchKind.fileChanges:
            return WatchedPath.name(config.string("path") ?? "")
        case WatchKind.processExits:
            return ProcessExitsProbe.label(config)
        case WatchKind.command:
            return (config.string("command") ?? "command").clipped(40)
        default:
            return kind
        }
    }

    static func state(_ w: Watcher, now: Date) -> String {
        switch w.state {
        case .active:
            guard let next = w.nextCheckAt else { return "active" }
            let wait = next.timeIntervalSince(now)
            return wait <= 5 ? "checking now" : "next check in \(every(wait))"
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
            throw ToolError.invalidInput("“level” must be gentle, attention or critical.")
        }
        // Only the user's own request may be critical.
        return (level == .critical && caller != .user) ? .attention : level
    }

    static func mode(_ input: JSONValue) throws -> Watcher.Mode {
        guard let text = input.string("mode") else { return .once }
        guard let mode = Watcher.Mode(rawValue: text.lowercased()) else { throw ToolError.invalidInput("“mode” must be once or repeat.") }
        return mode
    }

    static func interval(_ input: JSONValue) throws -> TimeInterval {
        guard let minutes = input["interval_minutes"]?.doubleValue else { return 0 }
        guard minutes > 0, minutes <= 7 * 24 * 60 else { throw ToolError.invalidInput("“interval_minutes” must be between a fraction of a minute and 7 days.") }
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
                let names = matches.prefix(4).map { "“\($0.title)” (\($0.id.prefix(6)))" }.joined(separator: ", ")
                throw ToolError.invalidInput("That matches more than one watcher: \(names). Use the id.")
            }
            return matches.first
        }
        if ref.count >= 4, let w = try pick(mine.filter { $0.id.hasPrefix(ref) }) { return w }
        if let w = try pick(mine.filter { $0.title.caseInsensitiveCompare(ref) == .orderedSame }) { return w }
        if ref.count >= 3, let w = try pick(mine.filter { $0.title.range(of: ref, options: .caseInsensitive) != nil }) { return w }
        throw ToolError.notFound("a watcher called “\(ref.clipped(60))”")
    }
}

// MARK: watch.create

struct WatchCreateTool: Tool {
    let engine: WatcherEngine

    var spec: ToolSpec {
        ToolSpec(
            name: "watch.create", title: "Watch something",
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
        let target = (input.string("target") ?? "something").clipped(120)
        switch input.string("kind") {
        case WatchKind.urlChange:
            if let text = input.string("contains") { return "Watch \(target) until it says “\(text.clipped(40))”" }
            return "Watch \(target) for changes"
        case WatchKind.siteStatus: return "Watch whether \(target) is up"
        case WatchKind.fileAppears: return input["gone"]?.boolValue == true ? "Watch for \(target) to disappear" : "Watch for \(target) to appear"
        case WatchKind.fileChanges: return "Watch \(target) for changes"
        case WatchKind.folderNewFile: return "Watch \(target) for new files"
        case WatchKind.processExits: return "Tell you when \(target) quits"
        default: return "Watch \(target)"
        }
    }

    func scope(for input: JSONValue) -> ToolScope {
        guard let target = input.string("target") else { return .none }
        switch input.string("kind") {
        case WatchKind.urlChange, WatchKind.siteStatus:
            let text = target.contains("://") ? target : "https://" + target
            return ToolScope(url: URL(string: text)?.absoluteString ?? text)
        case WatchKind.fileAppears, WatchKind.fileChanges, WatchKind.folderNewFile:
            return ToolScope(readPaths: [(target as NSString).expandingTildeInPath])
        default:
            return .none
        }
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let kind = input.string("kind"), WatchKind.creatable.contains(kind) else {
            throw ToolError.invalidInput("“kind” must be one of \(WatchKind.creatable.joined(separator: ", ")).")
        }
        guard let target = input.string("target") else { throw ToolError.invalidInput("Tell me what to watch (“target”).") }

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
        // Reaching this Mac or the local network is something only the user can ask for (docs/SECURITY.md T11);
        // the option is not in the schema, and it is ignored unless the user themself made the call.
        if context.caller == .user, input["allow_local"]?.boolValue == true, kind == WatchKind.urlChange || kind == WatchKind.siteStatus {
            config = config.setting("allow_local", true)
        }

        let title = input.string("title") ?? WatchWords.defaultTitle(kind: kind, config: config)
        let requested = try WatchInput.interval(input)
        let watcher = Watcher(kind: kind, title: title, config: config, condition: condition, intervalS: requested,
                              mode: try WatchInput.mode(input), level: try WatchInput.level(input, caller: context.caller),
                              source: WatchSource.string(for: context.caller), now: context.now)
        let added: Watcher
        do { added = try await engine.add(watcher) } catch { throw WatchInput.watchError(error) }
        return WatchResults.started(added, requested: requested, engine: engine)
    }
}

enum WatchResults {
    static func started(_ w: Watcher, requested: TimeInterval, engine: WatcherEngine) -> ToolResult {
        let every = WatchWords.every(w.intervalS)
        var text = "Watching \(w.title) every \(every); I'll tell the user \(WatchWords.promise(w)). Its id is \(w.id)."
        if requested > 0, w.intervalS > requested { text += " That's the shortest gap allowed for this kind of watcher." }
        if let expires = w.expiresAt {
            text += " It stops on its own after \(WatchWords.every(expires.timeIntervalSince(w.createdAt)))."
        }
        let card = ResultCard(kind: .watcher, title: "Watching \(w.title) every \(every)", subtitle: "I'll tell you \(WatchWords.promise(w))",
                              detail: w.mode == .repeat ? "Keeps going until you stop it" : "Stops after telling you once",
                              refId: w.id, url: w.config.string("url"))
        let id = w.id
        let undo = UndoAction(label: "Stopped watching \(w.title)") { _ = await engine.remove(id) }
        return ToolResult(text: text, card: card, undo: undo)
    }
}

// MARK: watch.command

struct WatchCommandTool: Tool {
    let engine: WatcherEngine

    var spec: ToolSpec {
        ToolSpec(
            name: "watch.command", title: "Watch with a command",
            description: """
            Run a shell command on a schedule and tell the user when the result matches (it exits with a given code, \
            its output has some words, or its output changes). The user approves the exact command first. \
            Prefer watch.create when a web page, file, folder or program can be watched directly.
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
            ], required: ["command"]),
            risk: .high, capabilities: [.watch, .shell], category: .watch, mutates: true, external: false)
    }

    func summary(for input: JSONValue) -> String { "Run “\((input.string("command") ?? "").clipped(160))” on a schedule" }

    func scope(for input: JSONValue) -> ToolScope {
        var scope = ToolScope(command: input.string("command"))
        if let cwd = input.string("cwd") { scope.readPaths = [(cwd as NSString).expandingTildeInPath] }
        return scope
    }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        // Defence in depth: Guard never offers this tool to these callers, and the engine refuses them too.
        guard WatchSource.mayRunCommands(WatchSource.string(for: context.caller)) else {
            throw ToolError.unavailable("Only you, or Sidefolk with your approval, can set up a command watcher.")
        }
        guard let command = input.string("command") else { throw ToolError.invalidInput("Tell me which command to run.") }
        var config: JSONValue = ["command": .string(command)]
        if let cwd = input.string("cwd") { config = config.setting("cwd", .string(cwd)) }
        var condition: JSONValue = .object([:])
        if let code = input["exit_code"]?.intValue { condition = ["exit_code": .number(Double(code))] }
        else if let text = input.string("output_contains") { condition = ["output_contains": .string(text)] }
        else { condition = ["changed": true] }

        let requested = try WatchInput.interval(input)
        let watcher = Watcher(kind: WatchKind.command, title: input.string("title") ?? WatchWords.defaultTitle(kind: WatchKind.command, config: config),
                              config: config, condition: condition, intervalS: requested,
                              mode: try WatchInput.mode(input), level: try WatchInput.level(input, caller: context.caller),
                              source: WatchSource.string(for: context.caller), now: context.now)
        let added: Watcher
        do { added = try await engine.add(watcher) } catch { throw WatchInput.watchError(error) }
        return WatchResults.started(added, requested: requested, engine: engine)
    }
}

// MARK: watch.list / stop / pause / resume

struct WatchListTool: Tool {
    let engine: WatcherEngine

    var spec: ToolSpec {
        ToolSpec(name: "watch.list", title: "List watchers", description: "List what Sidefolk is watching, with each watcher's id and state.",
                 inputSchema: Schema.object([:]), risk: .low, capabilities: [.watch], category: .watch, mutates: false, external: true)
    }

    func summary(for input: JSONValue) -> String { "List what I'm watching" }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let all = await engine.list().filter { WatchSource.canManage(caller: context.caller, watcherSource: $0.source) }
        guard !all.isEmpty else {
            return ToolResult(text: "Nothing is being watched.", card: ResultCard(kind: .list, title: "Nothing is being watched"))
        }
        let lines = all.prefix(50).map { w in
            "• \(w.title) (\(w.kind), id \(w.id)): \(WatchWords.state(w, now: context.now)), every \(WatchWords.every(w.intervalS))"
                + (w.fireCount > 0 ? ", fired \(w.fireCount)×" : "")
        }
        let card = ResultCard(kind: .list, title: all.count == 1 ? "1 watcher" : "\(all.count) watchers", detail: lines.joined(separator: "\n"))
        // Titles made by other agents are their words, not ours.
        let outside = all.contains { WatchSource.isExternal($0.source) || $0.source.hasPrefix("extension:") }
        return ToolResult(text: lines.joined(separator: "\n"), card: card, untrusted: outside)
    }
}

struct WatchStopTool: Tool {
    let engine: WatcherEngine

    var spec: ToolSpec {
        ToolSpec(name: "watch.stop", title: "Stop watching", description: "Stop and remove a watcher. id is its id or its title.",
                 inputSchema: Schema.object(["id": Schema.string("The watcher's id (or its title).")], required: ["id"]),
                 risk: .low, capabilities: [.watch], category: .watch, mutates: true, external: true)
    }

    func summary(for input: JSONValue) -> String { "Stop watching “\((input.string("id") ?? "").clipped(60))”" }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let w = try await WatchInput.resolve(input.string("id") ?? "", caller: context.caller, engine: engine)
        guard let removed = await engine.remove(w.id) else { throw ToolError.notFound("that watcher") }
        let engine = self.engine
        let undo = UndoAction(label: "Watching \(removed.title) again") { _ = try await engine.add(removed) }
        return ToolResult(text: "Stopped watching \(removed.title).", card: ResultCard(kind: .watcher, title: "Stopped watching \(removed.title)", refId: removed.id), undo: undo)
    }
}

struct WatchPauseTool: Tool {
    let engine: WatcherEngine

    var spec: ToolSpec {
        ToolSpec(name: "watch.pause", title: "Pause a watcher", description: "Pause a watcher without removing it. id is its id or its title.",
                 inputSchema: Schema.object(["id": Schema.string("The watcher's id (or its title).")], required: ["id"]),
                 risk: .low, capabilities: [.watch], category: .watch, mutates: true, external: false)
    }

    func summary(for input: JSONValue) -> String { "Pause “\((input.string("id") ?? "").clipped(60))”" }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let w = try await WatchInput.resolve(input.string("id") ?? "", caller: context.caller, engine: engine)
        let paused: Watcher
        do { paused = try await engine.pause(w.id) } catch { throw WatchInput.watchError(error) }
        let engine = self.engine
        let undo = UndoAction(label: "Resumed \(paused.title)") { _ = try await engine.resume(paused.id) }
        return ToolResult(text: "Paused \(paused.title).", card: ResultCard(kind: .watcher, title: "Paused \(paused.title)", refId: paused.id), undo: undo)
    }
}

struct WatchResumeTool: Tool {
    let engine: WatcherEngine

    var spec: ToolSpec {
        ToolSpec(name: "watch.resume", title: "Resume a watcher", description: "Start a paused, finished or expired watcher again. id is its id or its title.",
                 inputSchema: Schema.object(["id": Schema.string("The watcher's id (or its title).")], required: ["id"]),
                 risk: .low, capabilities: [.watch], category: .watch, mutates: true, external: false)
    }

    func summary(for input: JSONValue) -> String { "Resume “\((input.string("id") ?? "").clipped(60))”" }

    func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        let w = try await WatchInput.resolve(input.string("id") ?? "", caller: context.caller, engine: engine)
        let resumed: Watcher
        do { resumed = try await engine.resume(w.id) } catch { throw WatchInput.watchError(error) }
        let engine = self.engine
        let undo = UndoAction(label: "Paused \(resumed.title)") { _ = try await engine.pause(resumed.id) }
        return ToolResult(text: "Watching \(resumed.title) again.", card: ResultCard(kind: .watcher, title: "Watching \(resumed.title) again", refId: resumed.id), undo: undo)
    }
}
