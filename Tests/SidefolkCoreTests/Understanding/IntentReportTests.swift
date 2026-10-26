import Foundation
import Testing
@testable import SidefolkCore

/// Reports and stopping them, understood without AI. "Now" is Wednesday 22 October 2025, 10:00 UTC.
@Suite struct IntentReportTests {
    let now = TimeTest.wednesday10
    let parser = IntentParser(when: TimeTest.parser(), home: "/Users/test")

    func parse(_ text: String, watching: [Watcher] = []) -> ParsedIntent? {
        parser.parse(text, now: now, watching: watching.map(WatchName.init))
    }

    func report(_ text: String) -> ReportIntent? {
        if case .report(let r)? = parse(text)?.intent { return r }
        return nil
    }

    // MARK: Reports

    @Test func theFoundersPhrases() {
        #expect(report("every 10 seconds tell me the CPU usage") == ReportIntent(source: .metric(.cpu), everySeconds: 10))
        #expect(report("tell me the CPU every minute") == ReportIntent(source: .metric(.cpu), everySeconds: 60))
        #expect(report("show my battery every 5 minutes") == ReportIntent(source: .metric(.battery), everySeconds: 300))
        #expect(report("watch the CPU usage and every 10 seconds tell me how much it is now") == ReportIntent(source: .metric(.cpu), everySeconds: 10))
        #expect(report("temperature in Fukuoka every minute") == ReportIntent(source: .weather(place: "Fukuoka", quantity: .temperature), everySeconds: 60))
        #expect(report("check the temperature in Fukuoka every 1 minute and tell me")
            == ReportIntent(source: .weather(place: "Fukuoka", quantity: .temperature), everySeconds: 60))
    }

    @Test func theHintSaysWhatAndHowOften() {
        #expect(parse("every 10 seconds tell me the CPU usage")?.hint == "Show CPU every 10 s · no AI")
        #expect(parse("temperature in Fukuoka every minute")?.hint == "Show Temperature in Fukuoka every 1 min · no AI")
        #expect(parse("show my battery every 5 minutes until 6pm")?.hint == "Show Battery every 5 min · until 18:00 · no AI")
        #expect(parse("tell me the CPU every 10s until I stop it")?.hint == "Show CPU every 10 s · until you stop it · no AI")
    }

    @Test func otherWaysToSayIt() {
        #expect(report("what's the memory usage every 30 seconds")?.source == .metric(.memory))
        #expect(report("every 2 min show free disk space")?.source == .metric(.disk))
        #expect(report("network speed every 5s")?.everySeconds == 5)
        #expect(report("report the ram every half hour")?.everySeconds == 1800)
        #expect(report("once a minute tell me the processor load")?.everySeconds == 60)
        #expect(report("every other minute tell me the battery level")?.everySeconds == 120)
        #expect(report("every ten seconds show the cpu")?.everySeconds == 10)
        #expect(report("weather in Paris, France every hour")?.source == .weather(place: "Paris, France", quantity: .conditions))
        #expect(report("humidity in new york every 15 minutes")?.source == .weather(place: "New york", quantity: .humidity))
        #expect(report("the Fukuoka temperature every minute")?.source == .weather(place: "Fukuoka", quantity: .temperature))
    }

    @Test func endsAndNotifications() {
        #expect(report("tell me the CPU every 10 seconds until I stop it")?.untilStopped == true)
        #expect(report("every minute tell me the battery until 6pm")?.until == "6pm")
        #expect(report("every 10 seconds until 6pm tell me the cpu")?.until == "6pm")
        #expect(report("show the cpu every 10 seconds for an hour")?.until == "in an hour")
        let notify = report("notify me of the temperature in Fukuoka every hour")
        #expect(notify?.notify == true && notify?.source == .weather(place: "Fukuoka", quantity: .temperature))
    }

    @Test func notAReportLeavesItAlone() {
        // A reminder that mentions the battery is a reminder.
        if case .remind? = parse("remind me every 2 hours to check the battery")?.intent {} else { Issue.record("expected a reminder") }
        #expect(parse("every 10 seconds tell me a joke") == nil)
        #expect(parse("tell me when the battery is below 20% every minute") == nil)
        #expect(parse("tell me the CPU") == nil, "no interval: a question for the AI")
        #expect(parse("every day tell me the weather in Paris") == nil, "a daily brief is a routine, not a live value")
        #expect(parse("every 10 seconds and every minute show the cpu") == nil)
        #expect(parse("show the cpu and the memory every minute") == nil, "one value per report")
        #expect(parse("every minute tell me the temperature") == nil, "where?")
        #expect(report("every minute tell me the cpu until I feel better") == nil)
    }

    // MARK: Stopping

    func w(_ kind: String, _ config: JSONValue, title: String, mode: Watcher.Mode = .report) -> Watcher {
        Watcher(kind: kind, title: title, config: config, intervalS: 10, mode: mode, source: "user", now: now)
    }

    @Test func stopByWhatItShows() throws {
        let cpu = w(WatchKind.metric, ["metric": "cpu"], title: "CPU")
        let fukuoka = w(WatchKind.weather, ["place": "Fukuoka", "quantity": "temperature"], title: "Temperature in Fukuoka")
        let page = w(WatchKind.urlChange, ["url": "https://example.com/pricing"], title: "example.com/pricing", mode: .once)
        let live = [cpu, fukuoka, page]
        #expect(parse("stop telling me the CPU", watching: live)?.intent == .stopWatch(ids: [cpu.id], words: "the CPU"))
        #expect(parse("stop the Fukuoka temperature", watching: live)?.intent == .stopWatch(ids: [fukuoka.id], words: "the Fukuoka temperature"))
        #expect(parse("stop showing the processor usage", watching: live)?.intent == .stopWatch(ids: [cpu.id], words: "the processor usage"))
        #expect(parse("cancel the cpu report", watching: live)?.intent == .stopWatch(ids: [cpu.id], words: "the cpu report"))
        #expect(parse("stop watching example.com", watching: live)?.intent == .stopWatch(ids: [page.id], words: "example.com"))
        #expect(parse("stop the Fukuoka temperature", watching: live)?.hint == "Stop Temperature in Fukuoka · no AI")
    }

    @Test func stopWithoutNamingItWhenThereIsOnlyOne() {
        let cpu = w(WatchKind.metric, ["metric": "cpu"], title: "CPU")
        #expect(parse("stop telling me", watching: [cpu])?.intent == .stopWatch(ids: [cpu.id], words: ""))
        let battery = w(WatchKind.metric, ["metric": "battery"], title: "Battery")
        #expect(parse("stop telling me", watching: [cpu, battery]) == nil, "which one is for the AI or the person to say")
    }

    @Test func stoppingSomethingElseIsNotOurs() {
        let cpu = w(WatchKind.metric, ["metric": "cpu"], title: "CPU")
        #expect(parse("cancel the dentist reminder", watching: [cpu]) == nil)
        #expect(parse("end the meeting at 5", watching: [cpu]) == nil)
        #expect(parse("stop quiet mode", watching: [cpu])?.intent == .quietOff)
        // Telling-words with nothing that fits: answered here, plainly, rather than guessed.
        #expect(parse("stop telling me the battery", watching: [cpu])?.intent == .stopWatch(ids: [], words: "the battery"))
    }

    @Test func twoThatFitAreNamedBack() {
        let tokyo = w(WatchKind.weather, ["place": "Tokyo", "quantity": "temperature"], title: "Temperature in Tokyo")
        let fukuoka = w(WatchKind.weather, ["place": "Fukuoka", "quantity": "temperature"], title: "Temperature in Fukuoka")
        let p = parse("stop the temperature", watching: [tokyo, fukuoka])
        #expect(p?.intent == .stopWatch(ids: [tokyo.id, fukuoka.id], words: "the temperature"))
        #expect(p?.hint == "Stop · 2 match, which one? · no AI")
    }
}
