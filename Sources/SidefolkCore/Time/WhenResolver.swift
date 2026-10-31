import Foundation

/// Turns a recognised phrase into a date, given what "now" is. All the rolling-forward rules live here:
/// nothing resolved from relative words ends up in the past.
struct WhenResolver {
    let calendar: Calendar
    let now: Date
    let morning: Int
    let afternoon: Int
    let evening: Int

    struct Outcome {
        var date: Date
        /// Start of the series for a repeating reminder (may be earlier than `date`); equals `date` otherwise.
        var anchor: Date
        var recurrence: Recurrence?
        var hasTime: Bool
        var confidence: WhenResult.Confidence
        /// Came from an ISO 8601 string: the caller decides whether the past is acceptable.
        var exact: Bool
    }

    func resolve(_ atom: WhenAtom) -> Outcome? {
        if let span = atom.duration { return offset(span) }
        if atom.repeats != nil { return ending(repeating(atom), atom.until) }
        return single(atom)
    }

    // MARK: Helpers

    private var today: Date { calendar.startOfDay(for: now) }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today) ?? today.addingTimeInterval(Double(offset) * 86400)
    }

    private func stamp(_ day: Date, _ time: (hour: Int, minute: Int)) -> Date {
        calendar.wallClock(on: day, hour: time.hour, minute: time.minute)
    }

    private func isoWeekday(_ date: Date) -> Int { TimeFormat.isoWeekday(of: date, calendar: calendar) }

    private func hour(for part: WhenDayPart) -> Int {
        switch part {
        case .morning: morning
        case .afternoon: afternoon
        case .evening: evening
        case .night: 21
        }
    }

    /// The clock time an atom stands for. Bare hours follow the usual habit: 1-7 mean the afternoon,
    /// 8-11 the morning (with the evening as a fallback when the morning is over), 12 is noon.
    private struct Choice {
        var primary: (hour: Int, minute: Int)
        var alternate: (hour: Int, minute: Int)?
    }

    private func choice(_ atom: WhenAtom) -> Choice {
        switch atom.time {
        case nil, .fromISO: return Choice(primary: (morning, 0))
        case .noon: return Choice(primary: (12, 0))
        case .midnight: return Choice(primary: (0, 0))
        case .part(let p): return Choice(primary: (hour(for: p), 0))
        case .clock(let h, let m, let meridiem, let exact24):
            if let meridiem { return Choice(primary: (h % 12 + (meridiem == .pm ? 12 : 0), m)) }
            if exact24 { return Choice(primary: (h, m)) }
            if h == 12 { return Choice(primary: (12, m)) }
            if let hint = atom.partHint { return Choice(primary: (hint == .morning ? h : h + 12, m)) }
            if h <= 7 { return Choice(primary: (h + 12, m)) }
            return Choice(primary: (h, m), alternate: (h + 12, m))
        }
    }

    // MARK: Offsets

    private func offset(_ span: WhenSpan) -> Outcome? {
        var base = now
        if span.days != 0 || span.months != 0 || span.years != 0 {
            guard let moved = calendar.date(byAdding: DateComponents(year: span.years, month: span.months, day: span.days), to: now) else { return nil }
            base = moved
        }
        let date = base.addingTimeInterval(span.seconds)
        return Outcome(date: date, anchor: date, recurrence: nil, hasTime: true, confidence: date > now ? .high : .low, exact: false)
    }

    // MARK: One-off dates

    private func single(_ atom: WhenAtom) -> Outcome? {
        let pick = choice(atom)
        let hasTime = atom.time != nil
        func out(_ date: Date, _ confidence: WhenResult.Confidence = .high, exact: Bool = false) -> Outcome {
            Outcome(date: date, anchor: date, recurrence: nil, hasTime: hasTime, confidence: confidence, exact: exact)
        }
        /// Today at the time if it is still ahead, else the evening alternative, else nil.
        func laterToday() -> Outcome? {
            let first = stamp(today, pick.primary)
            if first > now { return out(first) }
            if let alt = pick.alternate, stamp(today, alt) > now { return out(stamp(today, alt), .medium) }
            return nil
        }

        guard let spec = atom.day else {
            if let t = laterToday() { return t }
            return out(stamp(day(1), pick.primary), pick.alternate == nil ? .high : .medium)
        }
        switch spec {
        case .today:
            // Asking for a moment of today that is over: hand back tomorrow's as a suggestion, flagged low.
            return laterToday() ?? out(stamp(day(1), pick.primary), .low)
        case .tomorrow: return out(stamp(day(1), pick.primary))
        case .dayAfterTomorrow: return out(stamp(day(2), pick.primary))
        case .weekday(let wanted, let next):
            var skippedToday = false
            for k in (next ? 1 : 0)...14 where isoWeekday(day(k)) == wanted {
                let t = stamp(day(k), pick.primary)
                if t > now { return out(t, skippedToday ? .medium : .high) }
                skippedToday = true
            }
            return nil
        case .nextWeek:
            for k in 1...7 where isoWeekday(day(k)) == 1 { return out(stamp(day(k), pick.primary)) }
            return nil
        case .nextMonth:
            guard let start = calendar.dateInterval(of: .month, for: today)?.end else { return nil }
            return out(stamp(start, pick.primary))
        case .nextYear:
            guard let start = calendar.dateInterval(of: .year, for: today)?.end else { return nil }
            return out(stamp(start, pick.primary))
        case .weekend:
            for k in 0...7 where isoWeekday(day(k)) == 6 {
                let t = stamp(day(k), pick.primary)
                if t > now { return out(t) }
            }
            return nil
        case .date(let month, let dayOfMonth, let year):
            guard let found = calendarDate(month: month, day: dayOfMonth, year: year, time: pick.primary) else { return nil }
            return out(found.date, found.confidence)
        case .dayOfMonth(let wanted):
            guard let thisMonth = calendar.dateInterval(of: .month, for: today)?.start else { return nil }
            for m in 0...13 {
                guard let start = calendar.date(byAdding: .month, value: m, to: thisMonth),
                      let length = calendar.range(of: .day, in: .month, for: start)?.count, wanted <= length,
                      let d = calendar.date(byAdding: .day, value: wanted - 1, to: start) else { continue }
                let t = stamp(d, pick.primary)
                if t > now { return out(t, m == 0 ? .high : .medium) }
            }
            return nil
        case .relative(let days, let months, let years):
            guard let d = calendar.date(byAdding: DateComponents(year: years, month: months, day: days), to: today) else { return nil }
            let t = stamp(d, pick.primary)
            return out(t, t > now ? .high : .low)
        case .iso(let s):
            guard let d = isoDate(s) else { return nil }
            if atom.time == .fromISO { return out(d, exact: true) }
            return out(stamp(d, pick.primary), exact: true)
        }
    }

    /// A month and day (with an optional year): the next one that is still ahead.
    private func calendarDate(month: Int, day dayOfMonth: Int, year: Int?, time: (hour: Int, minute: Int)) -> (date: Date, confidence: WhenResult.Confidence)? {
        func make(_ y: Int) -> Date? {
            var c = DateComponents()
            c.year = y; c.month = month; c.day = dayOfMonth
            guard let d = calendar.date(from: c), calendar.component(.day, from: d) == dayOfMonth else { return nil }
            return d
        }
        let thisYear = calendar.component(.year, from: now)
        if let year {
            guard let d = make(year) else { return nil }
            let t = stamp(d, time)
            return (t, t > now ? .high : .low)
        }
        var passedToday = false
        for y in thisYear...(thisYear + 8) {
            guard let d = make(y) else { continue }
            let t = stamp(d, time)
            if t > now { return (t, passedToday ? .low : (y == thisYear ? .high : .medium)) }
            if d == today { passedToday = true }
        }
        return nil
    }

    private func isoDate(_ s: WhenISOStamp) -> Date? {
        // ISO 8601 years are Gregorian: on a Buddhist or Japanese calendar "2026" isn't this year.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = calendar.timeZone
        if let offset = s.offset, let zone = TimeZone(secondsFromGMT: offset) { cal.timeZone = zone }
        var c = DateComponents()
        c.year = s.year; c.month = s.month; c.day = s.day
        if s.hasTime { c.hour = s.hour; c.minute = s.minute; c.second = s.second }
        guard let d = cal.date(from: c), cal.component(.day, from: d) == s.day else { return nil }
        return d
    }

    // MARK: Repeating

    private func repeating(_ atom: WhenAtom) -> Outcome? {
        guard let spec = atom.repeats else { return nil }
        let time = choice(atom).primary
        var rule = Recurrence(frequency: spec.frequency, interval: spec.interval, weekdays: spec.weekdays)
        func result(first: Date, anchor: Date) -> Outcome {
            Outcome(date: first, anchor: anchor, recurrence: rule, hasTime: atom.time != nil, confidence: .high, exact: false)
        }
        /// The soonest day (today counts while its time is ahead) that satisfies `fits`.
        func soonest(_ fits: (Date) -> Bool) -> Date? {
            for k in 0...(7 * spec.interval + 7) where fits(day(k)) {
                let t = stamp(day(k), time)
                if t > now { return t }
            }
            return nil
        }

        switch spec.frequency {
        case .minutely, .hourly:
            let first = now.addingTimeInterval(Double(spec.interval) * (spec.frequency == .minutely ? 60 : 3600))
            return result(first: first, anchor: first)
        case .daily:
            guard let first = soonest({ _ in true }) else { return nil }
            return result(first: first, anchor: first)
        case .weekdays:
            guard let first = soonest({ (1...5).contains(isoWeekday($0)) }) else { return nil }
            return result(first: first, anchor: first)
        case .weekly:
            rule.weekdays = Array(Set(spec.weekdays)).sorted()
            let wanted = rule.weekdays.isEmpty ? [isoWeekday(today)] : rule.weekdays
            guard let first = soonest({ wanted.contains(isoWeekday($0)) }) else { return nil }
            return result(first: first, anchor: first)
        case .monthly:
            let wanted = spec.dayOfMonth ?? calendar.component(.day, from: today)
            return anchored(rule: rule, time: time, atom: atom) { back in
                guard let start = calendar.dateInterval(of: .month, for: today)?.start,
                      let month = calendar.date(byAdding: .month, value: -back, to: start),
                      let length = calendar.range(of: .day, in: .month, for: month)?.count, wanted <= length else { return nil }
                return calendar.date(byAdding: .day, value: wanted - 1, to: month)
            }
        case .yearly:
            let month = spec.month ?? calendar.component(.month, from: today)
            let wanted = spec.day ?? calendar.component(.day, from: today)
            let thisYear = calendar.component(.year, from: now)
            return anchored(rule: rule, time: time, atom: atom) { back in
                var c = DateComponents()
                c.year = thisYear - back; c.month = month; c.day = wanted
                guard let d = calendar.date(from: c), calendar.component(.day, from: d) == wanted else { return nil }
                return d
            }
        }
    }

    /// "until 6pm", "until friday": the series' last moment goes into the rule. A day without a time ends when that day
    /// does. A clock time alone means today: when it has already passed (or comes before the first time), the phrase
    /// is not used at all rather than stretched into tomorrow.
    private func ending(_ outcome: Outcome?, _ end: WhenEnd?) -> Outcome? {
        guard var outcome, let end else { return outcome }
        guard let stop = single(WhenAtom(day: end.day, time: end.time, partHint: end.partHint)), stop.confidence != .low else { return nil }
        if end.day == nil, !calendar.isDate(stop.date, inSameDayAs: now) { return nil }
        var last = stop.date
        if end.time == nil, let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) {
            last = nextDay.addingTimeInterval(-1)
        }
        guard last >= outcome.date else { return nil }
        outcome.recurrence?.until = last
        outcome.confidence = min(outcome.confidence, stop.confidence)
        return outcome
    }

    /// Monthly and yearly series: the anchor is placed on a real date that has the wanted day (a month or
    /// year earlier if need be, such as the 31st or 29 February), so later months keep that day and
    /// only clamp when they are too short.
    private func anchored(rule: Recurrence, time: (hour: Int, minute: Int), atom: WhenAtom, anchorDay: (Int) -> Date?) -> Outcome? {
        var everyOne = rule
        everyOne.interval = 1
        for back in 0...8 {
            guard let day = anchorDay(back) else { continue }
            let anchor = stamp(day, time)
            guard let first = RecurrenceMath.nextOccurrence(after: now, recurrence: everyOne, anchor: anchor, calendar: calendar) else { return nil }
            // "Every 2 months": start with the soonest occurrence and count from there.
            return Outcome(date: first, anchor: rule.interval > 1 ? first : anchor, recurrence: rule, hasTime: atom.time != nil,
                           confidence: .high, exact: false)
        }
        return nil
    }
}
