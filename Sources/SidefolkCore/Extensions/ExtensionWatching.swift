import Foundation

/// Lets the watcher engine run watchers that extensions declare (`sidefolk/watch.check`).
/// One probe kind, `extension`, whose config names the extension, its watcher and the settings.
public struct ExtensionWatcherProbe: WatcherProbe {
    public let host: ExtensionHost
    public init(host: ExtensionHost) { self.host = host }

    public var kind: String { "extension" }
    public var defaultInterval: TimeInterval { 15 * 60 }
    public var minimumInterval: TimeInterval { 5 * 60 }
    public var repeatCooldown: TimeInterval { 60 * 60 }

    public func prepare(_ watcher: Watcher) throws -> Watcher {
        guard watcher.config.string("extension") != nil, watcher.config.string("watcher") != nil else {
            throw WatchError.invalid(String(localized: "An extension watcher needs the extension and the watcher's name."))
        }
        var w = watcher
        // Extensions never reach the user louder than "attention" (SECURITY T17).
        if w.level == .critical { w.level = .attention }
        return w
    }

    public func check(_ watcher: Watcher, now: Date) async throws -> ProbeResult {
        let id = watcher.config.string("extension") ?? ""
        let name = watcher.config.string("watcher") ?? ""
        do {
            let result = try await host.checkWatcher(extensionId: id, watcher: name, config: watcher.config["settings"] ?? .object([:]),
                                                     state: watcher.lastState ?? .object([:]))
            return ProbeResult(state: result.state, triggered: result.triggered, summary: result.summary, level: .attention)
        } catch let error as UserFacingError {
            throw ProbeError.failed(error.message)
        } catch {
            throw ProbeError.failed(String(describing: error).clipped(200))
        }
    }
}

/// `watch.extension`: start one of an extension's watchers. Medium risk: it runs extension code on a schedule.
public struct ExtensionWatchTool: Tool {
    let host: ExtensionHost
    let engine: WatcherEngine

    public init(host: ExtensionHost, engine: WatcherEngine) {
        self.host = host
        self.engine = engine
    }

    public var spec: ToolSpec {
        ToolSpec(
            name: "watch.extension", title: String(localized: "Watch with an extension"),
            description: "Start a watcher provided by an installed extension (see the extension watchers listed in context). "
                + "`settings` must match that watcher's fields.",
            inputSchema: Schema.object([
                "extension": Schema.string("The extension id, e.g. dev.sidefolk.system-vitals."),
                "watcher": Schema.string("The watcher's name in that extension, e.g. disk_low."),
                "settings": .object(["type": "object", "description": "The watcher's settings."]),
                "title": Schema.string("Optional short title."),
                "interval_minutes": Schema.integer("How often to check (at least 5).", minimum: 5),
                "mode": Schema.string("once (default) or repeat.", enum: ["once", "repeat"]),
            ], required: ["extension", "watcher"]),
            risk: .medium, capabilities: [.watch, .extensions], category: .watch, mutates: true)
    }

    public func summary(for input: JSONValue) -> String {
        String(localized: "Watch “\(input.string("watcher") ?? "?")” from \(input.string("extension") ?? String(localized: "an extension"))")
    }

    public func scope(for input: JSONValue) -> ToolScope { ToolScope(extensionId: input.string("extension")) }

    public func run(_ input: JSONValue, context: ToolContext) async throws -> ToolResult {
        guard let id = input.string("extension"), let name = input.string("watcher") else {
            throw ToolError.invalidInput(String(localized: "extension and watcher are required"))
        }
        guard let kind = await host.watcherKinds().first(where: { $0.extensionId == id && $0.watcher == name }) else {
            throw ToolError.notFound(String(localized: "a watcher “\(name)” in an enabled extension “\(id)”"))
        }
        let settings = try WatcherConfig.validate(input["settings"] ?? .object([:]), fields: kind.config)
        let minutes = Double(max(5, input["interval_minutes"]?.intValue ?? 15))
        let mode: Watcher.Mode = input.string("mode") == "repeat" ? .repeat : .once
        // The manifest's title is the extension author's text; a watcher's title is quoted to the
        // model later as the creator's own words, so without one from the caller it is the plain name.
        let watcher = Watcher(kind: "extension", title: input.string("title") ?? "\(id) / \(name)",
                              config: ["extension": .string(id), "watcher": .string(name), "settings": settings],
                              intervalS: minutes * 60, mode: mode, level: .attention, source: WatchSource.string(for: context), now: context.now)
        let added = try await engine.add(watcher)
        let engine = self.engine
        return ToolResult(
            text: "Watching “\(added.title)” (\(id)) every \(Int(minutes)) min. Watcher id \(added.id).",
            card: ResultCard(kind: .watcher, title: String(localized: "Watching: \(added.title)"),
                             subtitle: String(localized: "Every \(Int(minutes)) min · \(kind.title)"), refId: added.id),
            undo: UndoAction(label: String(localized: "Stop watching \(added.title)")) { _ = await engine.remove(added.id) })
    }
}

/// Context lines about what extension watchers exist, for the agent. Only identifiers appear: titles
/// and descriptions are the extension author's words and would reach every system prompt (SECURITY T2).
public enum ExtensionContext {
    /// "PDF Tools (A PDF's details and text, …)" for each built-in that is installed but off. Their words ship in the
    /// signed app (D39), so they may reach the model; anyone else's extension never appears here.
    public static func switchedOff(_ installed: [ExtensionInfo]) -> [String] {
        installed.filter { $0.origin?.firstParty == true && !$0.enabled }.sorted { $0.name < $1.name }.map { e in
            "\(ExtensionText.line(e.name, characters: 40))" + (e.description.map { " (\(ExtensionText.line($0, characters: 110)))" } ?? "")
        }
    }

    /// "Currency (Money in 30 currencies at today's rates)" for each of Sidefolk's own extensions in the gallery that
    /// isn't installed (D55), as the gallery shows them on `channel` (D65). Only official entries: their words are
    /// Sidefolk's, from the signed catalog.
    public static func inGallery(_ catalog: AddonCatalog?, installed: [ExtensionInfo], channel: UpdateChannel) -> [String] {
        let have = Set(installed.map(\.id))
        return (catalog?.offered(on: channel) ?? []).filter { $0.kind == .extension && $0.official && !have.contains($0.id) }
            .sorted { $0.name < $1.name }.prefix(16).map { e in
                ExtensionText.line(e.name, characters: 40) + (e.tagline.isEmpty ? "" : " (\(ExtensionText.line(e.tagline, characters: 80)))")
            }
    }

    public static func watcherLines(_ kinds: [ExtensionWatcherKind]) -> String? {
        guard !kinds.isEmpty else { return nil }
        return kinds.prefix(12).map { k in
            let fields = k.config.keys.sorted().map { ExtensionText.line($0, characters: 40) }.joined(separator: ", ")
            return "- Extension watcher \(k.extensionId) / \(ExtensionText.line(k.watcher, characters: 64))" + (fields.isEmpty ? "" : " (settings: \(fields))")
        }.joined(separator: "\n")
    }
}
