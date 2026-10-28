import Foundation
import Testing
@testable import SidefolkCore

/// The built-ins' own commands (D50), from the sentence a person types to the answer their real program gives, through
/// the parser, the runner and the executor, with no AI anywhere.
@Suite struct ExtensionCommandBuiltInTests {
    let runtime: SidefolkRuntime
    let runner: LocalIntentRunner

    init() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sidefolk-commands-\(UUID().uuidString)", isDirectory: true)
        runtime = await SidefolkRuntime(paths: SidefolkPaths(home: home), db: try AppDatabase.inMemory(), platform: NullPlatform(),
                                        clock: ManualClock(TestEnv.referenceDate))
        runner = LocalIntentRunner(runtime: runtime)
    }

    func install(_ folders: String...) async throws {
        for folder in folders { _ = try await runtime.extensions.install(from: ExtFixtures.builtIn(folder)) }
    }

    /// What the command answered, or nil when the sentence wasn't one.
    func answer(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) async -> String? {
        guard let parsed = await runner.parse(text) else { return nil }
        guard case .extensionCommand = parsed.intent else {
            Issue.record("“\(text)” became \(QA.describe(parsed.intent))", sourceLocation: sourceLocation)
            return nil
        }
        let outcome = await runner.run(parsed.intent)
        guard case .answer(let card, _) = outcome else {
            Issue.record("“\(text)” gave \(outcome)", sourceLocation: sourceLocation)
            return nil
        }
        return card.detail
    }

    @Test func calculatorAnswersSumsUnitsAndDays() async throws {
        try await install("calculator")
        #expect(await answer("what's 12*7") == "12*7 = 84")
        #expect(await answer("15% of 80") == "15% of 80 = 12")
        #expect(await answer("100 °F in celsius") == "100 °F = 37.7778 °C")
        #expect(await answer("convert 5 km to miles")?.hasPrefix("5 km = 3.10") == true)
        #expect(await answer("how many cups in 1 l")?.contains("cups") == true)
        #expect(await answer("days until 2030-01-01")?.contains("days") == true)
        #expect(await runner.parse("days until christmas") == nil, "the AI reads christmas")
        #expect(await runner.parse("2026-10-28") == nil, "a pasted date isn't a sum")
        await runtime.extensions.shutdown()
    }

    @Test func worldClockPlaytimeToolboxAndVitalsAnswerAtOnce() async throws {
        try await install("world-clock", "playtime", "dev-toolbox", "system-vitals")
        #expect(await answer("what time is it in Tokyo")?.contains("Tokyo") == true)
        let number = try #require(await answer("pick a number between 1 and 6"))
        #expect(number.contains(where: { "123456".contains($0) }), "\(number)")
        let pick = try #require(await answer("pick one: tea, coffee or juice"))
        #expect(["tea", "coffee", "juice"].contains { pick.contains($0) }, "\(pick)")
        let uuid = try #require(await answer("new uuid"))
        #expect(uuid.range(of: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-"#, options: .regularExpression) != nil, "\(uuid)")
        #expect(await answer("3 uuids")?.split(separator: "\n").count ?? 0 >= 3)
        #expect(await answer("timestamp 1730000000")?.contains("2024") == true)
        #expect(await answer("about this mac")?.hasPrefix("This Mac: ") == true)
        await runtime.extensions.shutdown()
    }

    @Test func aPlaceTheClockDoesntKnowGoesToTheAI() async throws {
        try await install("world-clock")
        let parsed = try #require(await runner.parse("what time is it in my head"))
        guard case .declined(let error) = await runner.run(parsed.intent) else { Issue.record("expected the AI to take it"); return }
        #expect(error.message.hasPrefix("World Clock couldn't answer that"), "\(error.message)")
        await runtime.extensions.shutdown()
    }

    @Test func aSwitchedOffExtensionAnswersNothing() async throws {
        try await install("calculator")
        #expect(await runner.parse("what's 12*7") != nil)
        try await runtime.extensions.setEnabled(false, id: "dev.sidefolk.calculator")
        #expect(await runner.parse("what's 12*7") == nil)
        await runtime.extensions.shutdown()
    }

    @Test func currencyAndUnitsNeverClaimTheSameSentence() async throws {
        try await install("calculator", "currency")
        func tool(_ text: String) async -> String? {
            guard case .extensionCommand(let call)? = await runner.parse(text)?.intent else { return nil }
            return call.tool
        }
        #expect(await tool("5 pounds in kg") == "ext.calculator.convert_units")
        #expect(await tool("5 pounds in euros") == "ext.currency.convert_currency")
        #expect(await tool("100 usd in eur") == "ext.currency.convert_currency")
        #expect(await tool("usd to eur") == "ext.currency.convert_currency")
        guard case .extensionCommand(let call)? = await runner.parse("$100 in yen")?.intent else { Issue.record("expected a command"); return }
        #expect(call.input == ["amount": 100, "from": "$", "to": ["yen"]])
        await runtime.extensions.shutdown()
    }

    @Test func theDetailsListTheCommandsAndWhatTheAISees() async throws {
        try await install("world-clock")
        let info = try #require(await runtime.extensions.info(id: "dev.sidefolk.world-clock"))
        let now = try #require(info.tools.first { $0.name == "ext.world-clock.current_time" })
        #expect(now.commands.contains("time in …") && now.forAI)
        #expect(ExtensionListQuery(text: "what time is it").matches(ExtensionListQuery.texts(for: info)), "a search finds it by its words")
        await runtime.extensions.shutdown()
    }
}
