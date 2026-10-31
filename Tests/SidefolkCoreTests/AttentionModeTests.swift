import Foundation
import Testing
@testable import SidefolkCore

/// Open, Focus and Quiet (D84): what each lets through, when each ends, quiet hours and full-screen apps.
@Suite struct AttentionModeTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    func at(_ hour: Int, _ minute: Int = 0, day: Int = 22) -> Date {
        calendar.date(from: DateComponents(year: 2025, month: 10, day: day, hour: hour, minute: minute))!
    }

    func decide(_ level: AttentionLevel, _ env: AttentionEnvironment, source: String = "watcher") -> AttentionDecision {
        AttentionPolicy.decide(level: level, source: source, createdAt: at(10), now: at(10), env: env, recent: [])
    }

    @Test func focusHoldsWhispersAndLetsCardsThrough() {
        var env = AttentionEnvironment()
        env.focus = true
        #expect(decide(.gentle, env) == .hold(until: nil))
        #expect(decide(.attention, env) == .present(.attention(expandFor: AttentionPolicy.expandSeconds)))
        #expect(decide(.critical, env, source: "reminder") == .present(.system(sound: true, alsoOnDesktop: true)))
        // Quiet lets less through, so it wins.
        env.quiet = true
        #expect(!env.isFocused)
        #expect(decide(.attention, env) == .present(.system(sound: false, alsoOnDesktop: false)))
    }

    @Test func aFullScreenAppDoesWhatThePersonChose() {
        var env = AttentionEnvironment()
        env.fullscreen = true
        #expect(env.isQuiet, "Quiet, as before")
        env.fullScreenRule = .focus
        #expect(!env.isQuiet && env.isFocused)
        #expect(decide(.gentle, env) == .hold(until: nil))
        env.fullScreenRule = .nothing
        #expect(!env.isQuiet && !env.isFocused)
        #expect(decide(.gentle, env) == .present(.gentle(autoDismiss: AttentionPolicy.gentleSeconds)))
    }

    @Test func choosingAModeReplacesTheOtherAndEndsWhenSaid() {
        var s = AppSettings()
        let now = at(15)
        s.setAttention(.focus, until: at(17), now: now, calendar: calendar)
        #expect(s.attentionMode(at: now, calendar: calendar) == .focus)
        #expect(s.attentionEnds(at: now, calendar: calendar) == at(17))
        #expect(s.attentionMode(at: at(17), calendar: calendar) == .open, "ends by itself")

        s.setAttention(.quiet, until: nil, now: now, calendar: calendar)
        #expect(s.focusUntil == nil)
        #expect(s.attentionMode(at: at(23), calendar: calendar) == .quiet)
        #expect(s.attentionEnds(at: now, calendar: calendar) == nil, "until turned off")
        #expect(s.nextAttentionChange(after: now, calendar: calendar) == nil)

        s.setAttention(.open, until: nil, now: now, calendar: calendar)
        #expect(s.quietUntil == nil && s.focusUntil == nil)
    }

    @Test func quietHoursRunAcrossMidnight() {
        var s = AppSettings()
        #expect(s.attentionMode(at: at(23), calendar: calendar) == .open, "off until turned on")
        s.quietHours = QuietHours(on: true, start: 22 * 60, end: 8 * 60)
        #expect(s.attentionMode(at: at(23), calendar: calendar) == .quiet)
        #expect(s.attentionMode(at: at(7, 59), calendar: calendar) == .quiet)
        #expect(s.attentionMode(at: at(8), calendar: calendar) == .open)
        #expect(s.attentionEnds(at: at(23), calendar: calendar) == at(8, day: 23))
        #expect(s.nextAttentionChange(after: at(15), calendar: calendar) == at(22))
        #expect(s.nextAttentionChange(after: at(23), calendar: calendar) == at(8, day: 23))
    }

    @Test func openInsideQuietHoursSetsTheRestOfThemAside() {
        var s = AppSettings()
        s.quietHours = QuietHours(on: true, start: 22 * 60, end: 8 * 60)
        s.setAttention(.open, until: nil, now: at(23), calendar: calendar)
        #expect(s.attentionMode(at: at(23, 30), calendar: calendar) == .open)
        #expect(s.attentionMode(at: at(22, day: 23), calendar: calendar) == .quiet, "the next night is quiet again")
    }

    @Test func olderSettingsReadWithTheNewFieldsAtTheirDefaults() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"companionName":"Mochi","quietUntil":null}"#.utf8))
        #expect(old.focusUntil == nil && old.quietHours == QuietHours() && old.fullScreen == .quiet && old.density == nil)
        var s = AppSettings()
        s.quietHours = QuietHours(on: true, start: 21 * 60, end: 7 * 60)
        s.fullScreen = .focus
        s.density = .compact
        s.focusUntil = at(17)
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.quietHours == s.quietHours && back.fullScreen == .focus && back.density == .compact && back.focusUntil == at(17))
    }

    @Test func whatWaitedDuringFocusComesAsOneCard() async throws {
        let events = EventBus()
        let center = AttentionCenter(store: AttentionStore(try AppDatabase.inMemory()), events: events)
        await center.update { $0.focus = true }
        _ = await center.post(AttentionRequest(level: .gentle, source: "job", title: "Build finished"))
        _ = await center.post(AttentionRequest(level: .gentle, source: "watcher", title: "Price changed"))
        #expect(await center.heldCount == 2)
        let stream = events.stream()
        await center.update { $0.focus = false }
        for await e in stream {
            if case .attention(.present(let item, _)) = e {
                #expect(item.title == "While you were focused: 2 things")
                break
            }
        }
        #expect(await center.heldCount == 0)
    }
}
