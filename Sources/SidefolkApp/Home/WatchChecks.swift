import SidefolkCore
import SwiftUI

// A watch's checks as people see them (D87): a bar of the last few as ticks (On duty, the detail page) and the timeline's
// rows. Colours are D78's (`StatusTone.check`): a change is news, a failed check amber, the rest quiet ink; each tick
// is also said in words for VoiceOver.

/// The last `slots` checks as ticks, oldest first, newest at the trailing end. Slots no check has filled yet are faint
/// dots, so every bar is as wide and reads from the same side.
struct CheckTicks: View {
    var ticks: [WatchCheck.Result]
    var slots = 24
    var tick = CGSize(width: 3, height: 14)
    var gap: CGFloat = 1.5

    var body: some View {
        let shown = Array(ticks.suffix(slots))
        HStack(spacing: gap) {
            ForEach(0..<(slots - shown.count), id: \.self) { _ in
                Circle().fill(Theme.line).frame(width: tick.width, height: tick.width).frame(height: tick.height)
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, result in
                mark(result)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: CheckWords.summary(shown)))
        .help(Text(verbatim: CheckWords.summary(shown)))
    }

    @ViewBuilder private func mark(_ result: WatchCheck.Result) -> some View {
        let shape = RoundedRectangle(cornerRadius: tick.width / 2, style: .continuous)
        switch result {
        // A pause is a gap in the watching: an outline, not a filled tick.
        case .paused: shape.strokeBorder(Theme.inkFaint, lineWidth: 1).frame(width: tick.width, height: tick.height * 0.6)
        // A quiet check is shorter, so the changes and failures stand up out of the line.
        case .unchanged: shape.fill(Theme.inkFaint.opacity(0.55)).frame(width: tick.width, height: tick.height * 0.6)
        case .changed, .failed: shape.fill(Theme.color(StatusTone.check(result))).frame(width: tick.width, height: tick.height)
        }
    }
}

/// Words a watch's buttons share with nothing else.
enum WatchWordsUI {
    /// Its own key: "Check now" in Settings › Updates looks for a new version ("Jetzt suchen"), a watch looks again.
    static let checkNow = String(localized: "watch.checkNow", defaultValue: "Check now",
                                 comment: "A watch's button: look at the page, site or file again right now")
}

enum CheckWords {
    /// "Last 24 checks: 21 with no change, 2 changed, 1 failed", or "Not checked yet".
    static func summary(_ ticks: [WatchCheck.Result]) -> String {
        guard !ticks.isEmpty else { return String(localized: "Not checked yet", comment: "A watch's bar of checks, before the first") }
        let counts = Dictionary(grouping: ticks, by: { $0 }).mapValues(\.count)
        var parts: [String] = []
        if let n = counts[.unchanged] { parts.append(String(localized: "\(n) with no change", comment: "A watch's bar of checks")) }
        if let n = counts[.changed] { parts.append(String(localized: "\(n) changed", comment: "A watch's bar of checks: checks that saw a change")) }
        if let n = counts[.failed] { parts.append(String(localized: "\(n) failed", comment: "A watch's bar of checks: checks that couldn't look")) }
        if let n = counts[.paused] { parts.append(String(localized: "\(n) paused", comment: "A watch's bar of checks: times it was paused")) }
        return String(localized: "Last \(ticks.count) checks: \(parts.formatted(.list(type: .and)))", comment: "A watch's bar of checks, read aloud")
    }

    static func symbol(_ result: WatchCheck.Result) -> String {
        switch result {
        case .unchanged: "equal"
        case .changed: "sparkle"
        case .failed: "exclamationmark.triangle"
        case .paused: "pause"
        }
    }

    /// The timeline's line for a run: "No change", "notes.md changed", "Couldn't check", "Paused".
    static func title(_ check: WatchCheck) -> String {
        switch check.result {
        case .unchanged:
            check.count > 1 ? String(localized: "No change in \(check.count) checks", comment: "A watch's timeline: a run of quiet checks")
                : String(localized: "No change", comment: "A watch's timeline: one quiet check")
        case .changed: check.reason ?? String(localized: "Changed", comment: "A watch tile: what it watches changed")
        case .failed:
            check.count > 1 ? String(localized: "Couldn't check, \(check.count) times", comment: "A watch's timeline: failed checks in a row")
                : String(localized: "Couldn't check", comment: "A watch's timeline: a failed check")
        case .paused: String(localized: "Paused", comment: "A watch's timeline: the person paused it")
        }
    }

    /// When: "Today 10:02"; for a run "Today 09:00 – 10:30", or "Yesterday 22:00 – Today 06:00" across midnight. The
    /// times are isolated, so a range keeps its order in a right-to-left language.
    static func when(_ check: WatchCheck, now: Date = Date()) -> String {
        let calendar = Calendar.autoupdatingCurrent
        guard check.count > 1, check.firstAt < check.lastAt else { return TimeText.short(check.lastAt, now: now) }
        if calendar.isDate(check.firstAt, inSameDayAs: check.lastAt) {
            let day = TimeFormat.day(check.firstAt, now: now, calendar: calendar)
            return "\(day) \u{2066}\(TimeFormat.clock(check.firstAt, calendar: calendar)) – \(TimeFormat.clock(check.lastAt, calendar: calendar))\u{2069}"
        }
        return "\u{2068}\(TimeText.short(check.firstAt, now: now))\u{2069} – \u{2068}\(TimeText.short(check.lastAt, now: now))\u{2069}"
    }

    /// "120 ms", "2.4 s" in the app's language: how long the check took.
    static func took(_ ms: Int) -> String {
        let style = Measurement<UnitDuration>.FormatStyle(width: .abbreviated, locale: Wording.locale,
                                                          numberFormatStyle: .number.precision(.fractionLength(ms < 1000 ? 0 : 1)))
        return ms < 1000 ? Measurement(value: Double(ms), unit: UnitDuration.milliseconds).formatted(style)
            : Measurement(value: Double(ms) / 1000, unit: UnitDuration.seconds).formatted(style)
    }
}

/// One run on the detail page's timeline: what it found, when, and why it couldn't look.
struct CheckRow: View {
    var check: WatchCheck

    var body: some View {
        let tone = StatusTone.check(check.result)
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: CheckWords.symbol(check.result)).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tone == .neutral ? Theme.inkMuted : Theme.color(tone))
                .frame(width: 24, height: 24)
                .background(tone == .neutral ? Theme.well : Theme.soft(tone), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: CheckWords.title(check)).font(check.result == .changed ? Theme.Font.bodyStrong : Theme.Font.body)
                    .foregroundStyle(check.result == .unchanged ? Theme.inkMuted : Theme.ink)
                    .lineLimit(2)
                if check.result == .failed, let reason = check.reason {
                    Text(verbatim: reason).font(Theme.Font.callout).foregroundStyle(Theme.inkMuted).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: CheckWords.when(check)).font(Theme.Font.callout).foregroundStyle(Theme.inkFaint).monospacedDigit()
                if let ms = check.durationMs, ms > 0, check.result != .paused {
                    Text(verbatim: CheckWords.took(ms)).font(Theme.Font.caption).foregroundStyle(Theme.inkFaint).monospacedDigit()
                }
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }
}
