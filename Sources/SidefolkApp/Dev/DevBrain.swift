#if DEBUG
import Foundation
import SidefolkCore

/// A brain for QA in debug builds: every request gets the same fixed answer, with no network and no
/// quota spent, so spoken replies, cards and languages can be checked end to end in the running app.
/// `swift scripts/dev.swift "brain:scripted:<answer>"` turns it on (only on a SIDEFOLK_HOME, never the
/// person's own data), `brain:scripted:off` turns it off. The answer lives in `dev-brain.txt` in that
/// home, so it survives `language:` relaunches.
nonisolated enum DevBrain {
    static func file(_ paths: SidefolkPaths) -> URL { paths.home.appendingPathComponent("dev-brain.txt") }

    /// The fixed answer, when the scripted brain is on.
    static func answer(_ paths: SidefolkPaths) -> String? {
        guard !paths.isDefaultHome, let text = try? String(contentsOf: file(paths), encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    /// `brain:scripted:<answer>` or `brain:scripted:off`. Sets an AI provider that is never contacted, so the
    /// request goes past the no-AI check to the agent, where `factory` answers it.
    static func set(_ value: String, paths: SidefolkPaths, settings: SettingsStore) async {
        guard !paths.isDefaultHome else {
            Log.shared.info("dev", "scripted brain refused on the person's own data folder")
            return
        }
        if value == "off" {
            try? FileManager.default.removeItem(at: file(paths))
            return
        }
        try? value.write(to: file(paths), atomically: true, encoding: .utf8)
        await settings.update { settings in
            guard settings.provider.kind == .none else { return }
            settings.provider.kind = .openAICompatible
            settings.provider.preset = .custom
            settings.provider.baseURL = "http://127.0.0.1:9/scripted"
            settings.provider.model = "scripted"
        }
    }

    /// The standard factory, unless the scripted brain is on.
    static func factory(_ standard: BrainFactory, paths: SidefolkPaths) -> BrainFactory {
        BrainFactory { (provider: ProviderSettings, thinkHarder: Bool) throws(UserFacingError) -> BrainChoice in
            guard let answer = answer(paths) else { return try standard.make(provider, thinkHarder: thinkHarder) }
            return BrainChoice(backend: LoopBackend(model: FixedAnswer(answer: answer), checkModel: "scripted"), model: "scripted")
        }
    }
}

/// Answers every turn with the same words.
nonisolated private struct FixedAnswer: TurnModel {
    let answer: String
    var providerName: String { "Scripted" }
    func respond(to request: TurnRequest) async throws -> ModelTurn { .reply(answer) }
    func check(model: String) async -> Result<String, UserFacingError> { .success("Scripted model ready.") }
}
#endif
