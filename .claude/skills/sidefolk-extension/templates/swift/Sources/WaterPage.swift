import Foundation
import SidefolkExtensionKit

/// The Water page in Home, and its tile on Today (the summary). It says what is true; Sidefolk draws it in the
/// person's theme. Text is English, like every extension page for now (D62).
enum WaterPage {
    static func make(_ t: Tally, now: Date = Date()) -> Page {
        let done = t.glasses >= t.goal
        let tone: Tone = done ? .good : t.glasses * 2 < t.goal ? .warn : .info
        let last = t.times.last.map { $0.formatted(date: .omitted, time: .shortened) }
        let summary = Summary("\(t.glasses) of \(t.goal) glasses", detail: done ? "Goal reached" : "\(t.left) to go" + (last.map { " · last at \($0)" } ?? ""),
                              tone: tone, symbol: "drop.fill")

        var sections = [
            Section("Today", [
                .gauge("Glasses", "\(t.glasses)/\(t.goal)", fraction: Double(t.glasses) / Double(max(t.goal, 1)), tone: tone),
                .stat("Drunk", "\(t.millilitres) ml", caption: t.largeGlasses ? "500 ml glasses" : "250 ml glasses"),
                .stat("Last glass", last ?? "None yet"),
            ]),
            // Buttons and switches run this extension's own tools as the person, through Guard (D63).
            Section(nil, [
                .button("Log a glass", tool: "log_water", input: ["glasses": 1], style: .primary, symbol: "drop.fill"),
                .toggle("Large glasses", detail: "Count each glass as 500 ml instead of 250 ml.", on: t.largeGlasses,
                        tool: "set_option", input: ["option": "large_glasses"]),
            ]),
            // A chart sends only the value now; Sidefolk keeps its past ("history": true reads it once a minute).
            Section("Over the day", [
                .chart(id: "today", "Glasses today", unit: "glasses", max: Double(max(t.goal, t.glasses)),
                       series: [Series("glasses", "Glasses", Double(t.glasses), display: "\(t.glasses)")]),
            ]),
        ]
        if !t.times.isEmpty {
            let times = t.times.suffix(24).enumerated().map { ("Glass \($0.offset + 1)", $0.element.formatted(date: .omitted, time: .shortened)) }
            sections.append(Section("When", [.facts(nil, times)]))
        }
        // An ask button sends the sentence to Ask, as if typed: it reaches the commands above, or the AI.
        sections.append(Section("Ask", [
            .ask("How am I doing?", "How much water today"),
            .ask("Goal of 10", "Set my water goal to 10"),
        ]))
        sections.append(Section(nil, [
            .note("Glasses start again at midnight. Turn on “Behind on water” below and the companion tells you once in the afternoon "
                + "when you've had less than half your goal."),
        ]))
        return Page(summary: summary, sections: sections)
    }
}
