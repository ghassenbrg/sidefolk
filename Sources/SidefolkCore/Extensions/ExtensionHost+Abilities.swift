import Foundation
import Synchronization

/// What an extension declares and the host keeps or draws for it (D100): settings, entries, drop actions, the one-time
/// settings it used to have in the app, one History row, and its use of the person's AI.
extension ExtensionHost {
    // MARK: Shelf

    /// Called wherever what is on changes, so an extension that is off or gone has nothing left in any menu.
    func shelveAbilities() {
        var entries: [ExtensionEntry] = [], drops: [ExtensionDropAction] = [], settings: [ExtensionSettingRow] = [], names: [String: String] = [:]
        for id in runtimes.keys.sorted() {
            guard let rt = runtimes[id], rt.record.enabled, restingFor(id) == nil, let m = rt.manifest else { continue }
            let firstParty = rt.pin.origin?.firstParty == true, name = self.name(rt), short = shortName(rt), w = words(rt)
            names[id] = name
            func entry(_ e: ExtensionManifest.EntryMeta) -> ExtensionEntry {
                let action: ExtensionEntry.Action
                if let tool = e.tool {
                    action = .tool(name: ExtensionTool.registryName(short: short, tool: tool), input: .object(e.input ?? [:]))
                } else if let page = e.page {
                    action = .page(page)
                } else {
                    action = .menu
                }
                return ExtensionEntry(extensionId: id, extensionName: name, key: e.id, title: w?.entries[e.id] ?? e.title, symbol: e.symbol,
                                      places: e.places, action: action, items: e.items.map(entry), firstParty: firstParty)
            }
            entries += m.entries.map(entry)
            drops += m.drops.map { d in
                ExtensionDropAction(extensionId: id, extensionName: name, key: d.id, title: w?.drops[d.id]?.title ?? d.title,
                                    detail: w?.drops[d.id]?.description ?? d.detail, symbol: d.symbol, kinds: d.kinds, patterns: d.patterns,
                                    tool: ExtensionTool.registryName(short: short, tool: d.tool), input: d.input)
            }
            settings += settingRows(rt)
        }
        shelf.set(entries: entries, drops: drops, settings: settings, names: names)
        publishRequestContext()
    }

    // MARK: Commands that meet (D100)

    /// Sentences this manifest and another extension that is on both claim. Neither gets them: whoever says one is answered by the
    /// AI, because guessing would hand their words to the wrong program (D50). The install sheet says so.
    func commandClashes(_ manifest: ExtensionManifest, strings: ExtensionStrings?) -> [String] {
        let mine = ExtensionCommandRules.claims(manifest, strings: strings)
        guard !mine.isEmpty else { return [] }
        var out: [String] = []
        for id in runtimes.keys.sorted() where id != manifest.id {
            guard let rt = runtimes[id], rt.record.enabled, let other = rt.manifest else { continue }
            let shared = mine.intersection(ExtensionCommandRules.claims(other, strings: rt.strings))
            guard let first = shared.sorted().first else { continue }
            let name = self.name(rt), sentence = ExtensionText.line(first, characters: 60)
            out.append(String(localized: "“\(sentence)” is also a sentence of \(name): when someone says it, the AI answers instead of either.",
                              comment: "Install sheet: two extensions claim the same command sentence; the sentence, then the other extension's name"))
        }
        return out
    }

    // MARK: Settings

    func settingRows(_ rt: Runtime) -> [ExtensionSettingRow] {
        guard let m = rt.manifest else { return [] }
        let w = words(rt), values = rt.preferences.resolved(m.settings)
        return m.settings.map { s in
            let own = w?.settings[s.key]
            return ExtensionSettingRow(extensionId: rt.record.id, key: s.key, type: s.type, title: own?.title ?? s.title, detail: own?.detail ?? s.detail,
                                       options: s.options.map { .init(value: $0.value, title: own?.options[$0.value] ?? $0.title) },
                                       minimum: s.minimum, maximum: s.maximum, step: s.step, length: s.length ?? 200, value: values[s.key] ?? s.fallback)
        }
    }

    /// The settings of one extension, whether or not it is on: Settings › Add-ons shows them either way.
    public func settings(extensionId id: String) -> [ExtensionSettingRow] { runtimes[id].map(settingRows) ?? [] }

    /// Changes a setting after checking it against the schema, keeps it, and tells the running program. Reached through the
    /// `extensions.setting` tool, so Guard and History see every change.
    func setSetting(extensionId id: String, key: String, value: JSONValue) async throws -> ExtensionSettingRow {
        guard let rt = runtimes[id], let meta = rt.manifest?.settings.first(where: { $0.key == key }) else {
            throw ToolError.invalidInput(String(localized: "There's no such setting."))
        }
        guard let checked = meta.checked(value) else {
            throw ToolError.invalidInput(String(localized: "That isn't a value for “\(meta.title)”.", comment: "An extension's setting, by its title"))
        }
        await updatePreferences(id) { $0.values[key] = checked }
        await tellSettings(id)
        events.changed(.extensions)
        guard let row = runtimes[id].flatMap({ settingRows($0).first { $0.key == key } }) else {
            throw ToolError.unavailable(String(localized: "That extension is no longer installed."))
        }
        return row
    }

    private func tellSettings(_ id: String) async {
        guard let rt = runtimes[id], let m = rt.manifest else { return }
        await rt.client?.notify("sidefolk/settings.changed", params: ["settings": .object(rt.preferences.resolved(m.settings))])
    }

    /// Saves what the host keeps for an extension, and refreshes what goes with its requests.
    func updatePreferences(_ id: String, _ change: (inout ExtensionPreferences) -> Void) async {
        guard var rt = runtimes[id] else { return }
        change(&rt.preferences)
        runtimes[id] = rt
        shelveAbilities()
        try? await KVStore(preferencesDatabase).set(ExtensionPreferences.key(id), rt.preferences)
    }

    func loadPreferences(_ id: String) async -> ExtensionPreferences {
        (try? await KVStore(preferencesDatabase).get(ExtensionPreferences.key(id), as: ExtensionPreferences.self)) ?? ExtensionPreferences()
    }

    func forgetPreferences(_ id: String) async {
        try? await KVStore(preferencesDatabase).remove(ExtensionPreferences.key(id))
    }

    /// What goes with every request to the program, beside its language (D76, D100): its settings, and the AI's name while it may
    /// ask. Kept where the client can read it without waiting on this actor.
    func publishRequestContext() {
        var context: [String: [String: JSONValue]] = [:]
        var asking: Set<String> = []
        for (id, rt) in runtimes {
            guard let m = rt.manifest else { continue }
            var extras: [String: JSONValue] = [:]
            if !m.settings.isEmpty { extras["settings"] = .object(rt.preferences.resolved(m.settings)) }
            if rt.pin.permissions?.ai != nil, rt.preferences.aiOn != false, aiHelper != nil { asking.insert(id) }
            if !extras.isEmpty { context[id] = extras }
        }
        requestContext.set(context, mayAsk: asking)
    }

    // MARK: What it used to have in the app

    /// Gives a Sidefolk extension, once, a section of settings the app used to keep for what it does now (`settings_from`). The
    /// program answers with the settings to store from it. Generic on purpose: the section's name comes from the signed
    /// manifest, and the host doesn't know what's in it.
    func deliverCarried(_ id: String) async {
        guard let rt = runtimes[id], rt.pin.origin?.firstParty == true, let from = rt.manifest?.settingsFrom, !rt.preferences.carried.contains(from),
              let client = rt.client else { return }
        guard let values = await configuration.carriedSettings(from) else {
            await updatePreferences(id) { $0.carried.append(from) }
            return
        }
        guard let reply = try? await client.request("sidefolk/settings.carry", params: ["from": .string(from), "values": values], timeout: 10) else { return }
        guard let m = runtimes[id]?.manifest else { return }
        let given = reply["settings"]?.objectValue ?? [:]
        await updatePreferences(id) { p in
            for s in m.settings { if let value = s.checked(given[s.key]) { p.values[s.key] = value } }
            p.carried.append(from)
        }
        await configuration.forgetCarried(from)
        await tellSettings(id)
        events.changed(.extensions)
        Log.shared.info("extensions", "received its old settings", ["id": id, "section": from])
    }

    // MARK: One History row

    /// `sidefolk/activity.add` (D100): a surface or a game adds one row to History, as the person's game does when it ends.
    /// At most one every few seconds, whatever the program sends.
    func addActivity(_ id: String, params: JSONValue) async {
        guard let rt = runtimes[id], rt.record.enabled, rt.record.kind == .sidefolk, let run = configuration.runTool else { return }
        let now = Date()
        guard now.timeIntervalSince(rt.lastActivity) >= ExtensionAbilityLimits.activitySeconds,
              let text = params["text"]?.stringValue.map({ ExtensionText.line($0, characters: 120) }), !text.isEmpty else { return }
        runtimes[id]?.lastActivity = now
        var input: [String: JSONValue] = ["extension": .string(id), "text": .string(text)]
        if let key = params["key"]?.stringValue, key.range(of: ManifestValidator.namePattern, options: .regularExpression) != nil { input["key"] = .string(key) }
        if let result = params["result"]?.stringValue, ExtensionAbilityLimits.results.contains(result) { input["result"] = .string(result) }
        _ = await run(ExtensionActivityTool.name, .object(input), .extension(id: id), 10)
    }

    /// `sidefolk/settings.set`: the program changes one of its own settings (a speaker button on its surface). Through the same
    /// tool as the person's click.
    func programSetsSetting(_ id: String, params: JSONValue) async {
        guard let rt = runtimes[id], rt.record.enabled, let key = params["key"]?.stringValue, let value = params["value"], let run = configuration.runTool else { return }
        _ = await run(ExtensionSettingTool.name, ["extension": .string(id), "key": .string(key), "value": value], .extension(id: id), 10)
    }

    // MARK: AI help

    /// The app hands over how the person's AI is reached, once it exists.
    public func setAIHelper(_ helper: AIHelper) {
        aiHelper = helper
        publishRequestContext()
    }

    /// The person's switch for this extension's use of the AI.
    public func setAIAllowed(extensionId id: String, _ on: Bool) async {
        await updatePreferences(id) { $0.aiOn = on }
        events.changed(.extensions)
    }

    func aiStatus(_ rt: Runtime) -> ExtensionAIStatus? {
        guard let ai = rt.pin.permissions?.ai else { return nil }
        return ExtensionAIStatus(purpose: words(rt)?.aiPurpose ?? ai.purpose, dailyCap: ai.dailyCap, usedToday: rt.preferences.calls(on: AIHelper.dayKey(Date())),
                                 on: rt.preferences.aiOn != false)
    }

    /// `sidefolk/ai.request`: answered with one `sidefolk/ai.answer` notice, always, so the program never waits for nothing.
    func answerAI(_ id: String, request: String, params: JSONValue) async {
        guard let rt = runtimes[id], let client = rt.client else {
            runtimes[id]?.aiAsking = false
            return
        }
        let reply = await aiReply(id, request: request, params: params)
        runtimes[id]?.aiAsking = false
        await client.notify("sidefolk/ai.answer", params: reply)
    }

    private func aiReply(_ id: String, request: String, params: JSONValue) async -> JSONValue {
        func refused(_ reason: AIHelper.Refusal) -> JSONValue { ["request": .string(request), "ok": false, "reason": .string(reason.rawValue)] }
        // The pin is what the person saw on the install sheet; the manifest of a running program can't widen it.
        guard let rt = runtimes[id], rt.record.enabled, let ai = rt.pin.permissions?.ai, let helper = aiHelper, let run = configuration.runTool else { return refused(.off) }
        guard rt.preferences.aiOn != false, configuration.aiName() != nil else { return refused(.off) }
        guard let question = AIHelpQuestion(params: params, extensionId: id, purpose: ai.purpose) else { return refused(.unusable) }
        if let kept = await helper.kept(question) { return AIHelper.reply(request: request, kept) }
        let today = AIHelper.dayKey(Date())
        guard rt.preferences.calls(on: today) < ai.dailyCap else { return refused(.limit) }
        // Counted before the call: a call that fails may still have cost the person's quota.
        await updatePreferences(id) { p in
            p.aiCalls = p.calls(on: today) + 1
            p.aiDay = today
        }
        events.changed(.extensions)
        await helper.lodge(request, question)
        let input: JSONValue = ["extension": .string(id), "request": .string(request), "label": .string(question.label), "asked": .string(question.asked)]
        let outcome = await run(AIHelpTool.name, input, .extension(id: id), 120)
        guard let result = await helper.take(request) else { return refused(outcome.isOK ? .failed : .denied) }
        switch result {
        case .success(let answer): return AIHelper.reply(request: request, answer)
        case .failure: return refused(.failed)
        }
    }
}

/// The limits of what the program side can ask for (D100).
enum ExtensionAbilityLimits {
    static let activitySeconds: TimeInterval = 5
    /// How a row may say something ended, for a surface that counts its own rows.
    static let results: Set<String> = ["win", "loss", "draw", "done"]
}

/// What goes with each request of each extension, readable from the client's own thread.
final class ExtensionRequestContext: Sendable {
    private let state = Mutex<(values: [String: [String: JSONValue]], mayAsk: Set<String>)>(([:], []))

    func set(_ context: [String: [String: JSONValue]], mayAsk: Set<String>) { state.withLock { $0 = (context, mayAsk) } }

    /// The AI's name is asked for at each request: the person may set one up, or turn it off, while the program runs.
    func extras(_ id: String, aiName: () -> String?) -> [String: JSONValue] {
        let (values, may) = state.withLock { ($0.values[id] ?? [:], $0.mayAsk.contains(id)) }
        guard may, let name = aiName() else { return values }
        return values.merging(["ai": .string(name)]) { own, _ in own }
    }
}
