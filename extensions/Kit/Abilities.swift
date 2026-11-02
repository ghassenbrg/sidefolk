import Foundation

/// What the host gives an extension beyond its requests (D100): its settings, one History row, and the person's AI.
@MainActor enum ExtensionServices {
    static var send: ((_ method: String, _ params: [String: Any]) -> Void)?
}

/// The settings the manifest declares (`settings`), as the host keeps them. They come with every request, so they are current when
/// the request is answered; the person changes them on the extension's page or in Settings › Add-ons.
@MainActor public enum ExtensionSettings {
    private static var values: [String: Any] = [:]

    static func use(_ any: Any?) {
        if let new = any as? [String: Any] { values = new }
    }

    public static var all: Arguments { Arguments(values) }
    public static func bool(_ key: String) -> Bool? { all.bool(key) }
    public static func string(_ key: String) -> String? { all.string(key) }
    public static func double(_ key: String) -> Double? { all.double(key) }
    public static func int(_ key: String) -> Int? { all.int(key) }

    /// Changes one of its own settings (a speaker button on its surface): checked against the schema, through Guard, in History.
    public static func set(_ key: String, _ value: Any) {
        ExtensionServices.send?("sidefolk/settings.set", ["key": key, "value": value])
    }
}

/// One row in History from a surface or a game, in the extension's words (D100). `key` is its own name for what it was about, `result`
/// `win`, `loss`, `draw` or `done`. At most one every five seconds.
public enum Activity {
    @MainActor public static func add(_ text: String, key: String? = nil, result: String? = nil) {
        var params: [String: Any] = ["text": text]
        if let key { params["key"] = key }
        if let result { params["result"] = result }
        ExtensionServices.send?("sidefolk/activity.add", params)
    }
}

/// The person's AI, for an extension that declares `permissions.ai` (D100). It gets the words sent here and nothing else, has no tools,
/// and its answer comes back only to this program: check it before use, as anything from outside.
///
/// ```swift
/// guard AI.available != nil else { return }                   // on, within reach, the person's switch not off
/// switch await AI.ask("Three riddles about {topic} as JSON…", label: "Riddles about the sea") {
/// case .answer(let text, let madeBy): …                      // label it "Made by \(madeBy), not checked"
/// case .refused(let reason): …                               // off, busy, limit, unusable, failed, denied
/// }
/// ```
@MainActor public enum AI {
    public enum Result: Equatable, Sendable {
        case answer(text: String, madeBy: String)
        case refused(String)
    }

    /// The person's AI by name while this extension may ask; nil when it is off or there is none.
    public private(set) static var available: String?
    private static var waiting: [String: CheckedContinuation<Result, Never>] = [:]

    /// Requests say whether it may ask: a request without the key means no.
    static func use(_ name: String?, asked method: String) {
        guard method == "tools/call" || method.hasPrefix("sidefolk/") else { return }
        available = name
    }

    /// Asks once and waits, at most `seconds`. One at a time; `label` is a few words for History ("Riddles about the sea").
    public static func ask(_ prompt: String, label: String? = nil, seconds: Double = 90) async -> Result {
        let id = UUID().uuidString
        var params: [String: Any] = ["request": id, "prompt": prompt]
        if let label { params["label"] = label }
        params["language"] = Language.code
        return await withCheckedContinuation { (c: CheckedContinuation<Result, Never>) in
            waiting[id] = c
            ExtensionServices.send?("sidefolk/ai.request", params)
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                finish(id, .refused("failed"))
            }
        }
    }

    static func receive(_ args: Arguments) {
        guard let id = args.string("request") else { return }
        if args.bool("ok") == true, let text = args.string("text") {
            finish(id, .answer(text: text, madeBy: args.string("made_by") ?? ""))
        } else {
            finish(id, .refused(args.string("reason") ?? "failed"))
        }
    }

    private static func finish(_ id: String, _ result: Result) {
        waiting.removeValue(forKey: id)?.resume(returning: result)
    }
}
