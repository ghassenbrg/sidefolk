#if DEBUG
import AppKit
import SidefolkCore

/// The Pocket's sample states for the UI snapshots (D84): sample content, as Home's samples are.
enum SamplePocket {
    static func states(name: String) -> [(String, PocketContent)] {
        let now = Date()
        var base = PocketContent()
        base.name = name
        base.avatar = CompanionArt.avatar(for: AppSettings(), side: 72)
        base.hotkey = "⇧⌘Space"
        base.watching = 3
        base.spans = AttentionSpan.choices(settings: AppSettings(), now: now)
        base.needsYou = [
            .init(id: "1", title: "Move 12 PDFs to Invoices", detail: "Mochi asks first", trailing: "15:58", symbol: "folder", folk: "guard", open: {}),
            .init(id: "2", title: "Claude Code needs you", detail: "sidefolk · wants to run git push", trailing: "15:55", symbol: "hand.raised",
                  folk: "byte", open: {}),
            .init(id: "3", title: "Pricing changed", detail: "example.com · Pro $12 → $15", trailing: "15:52", symbol: "binoculars",
                  folk: "scout", open: {}),
        ]
        base.nextUp = [
            .init(id: "4", title: "Stretch and refill water", trailing: "17:00", symbol: "alarm", folk: "tempo", open: {}),
        ]
        base.agents = [
            .init(id: "5", title: "Codex in pockito", detail: "last: watch “npm test”", trailing: "14 min", symbol: "terminal", folk: "byte",
                  live: true, open: {}),
        ]

        var quiet = base
        quiet.attention = .quiet
        quiet.attentionEnds = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
            .flatMap { Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: $0) }
        quiet.held = 2
        quiet.needsYou = []

        var update = base
        update.needsYou = []
        update.update = "0.1.0 snapshot 560"

        var hidden = base
        hidden.companionVisible = false
        hidden.needsYou = Array(base.needsYou.suffix(1))

        var full = base
        full.fullAccess = true
        full.fullAccessEnds = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: now)

        var empty = base
        (empty.needsYou, empty.nextUp, empty.agents, empty.watching) = ([], [], [], 0)
        return [("waiting", base), ("quiet", quiet), ("update", update), ("hidden", hidden), ("full-access", full), ("empty", empty)]
    }
}
#endif
