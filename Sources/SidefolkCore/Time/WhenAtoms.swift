import Foundation

enum WhenMeridiem: Sendable, Equatable { case am, pm }
enum WhenDayPart: String, Sendable, Equatable { case morning, afternoon, evening, night }

/// "in 2 hours" is exact seconds; "in 3 days" is calendar arithmetic and keeps the date semantics.
struct WhenSpan: Sendable, Equatable {
    var seconds = 0.0
    var days = 0
    var months = 0
    var years = 0
}

enum WhenDay: Sendable, Equatable {
    case today, tomorrow, dayAfterTomorrow
    case weekday(Int, next: Bool)
    case nextWeek, nextMonth, nextYear, weekend
    case date(month: Int, day: Int, year: Int?)
    case dayOfMonth(Int)
    case relative(days: Int, months: Int, years: Int)
    case iso(WhenISOStamp)
}

enum WhenTime: Sendable, Equatable {
    case clock(hour: Int, minute: Int, meridiem: WhenMeridiem?, exact24: Bool)
    case noon, midnight
    case part(WhenDayPart)
    /// The time comes with the ISO stamp.
    case fromISO
}

struct WhenRepeat: Sendable, Equatable {
    var frequency: Recurrence.Frequency
    var interval = 1
    var weekdays: [Int] = []
    /// Monthly: day of the month (31 also stands for "the last day").
    var dayOfMonth: Int?
    /// Yearly: the date.
    var month: Int?
    var day: Int?
}

/// "until 6pm", "until friday": where a repeating series stops.
struct WhenEnd: Sendable {
    var day: WhenDay?
    var time: WhenTime?
    var partHint: WhenDayPart?
}

/// One recognised piece of a time phrase and the tokens it covers (`start..<end`).
struct WhenAtom: Sendable {
    var day: WhenDay?
    var time: WhenTime?
    /// "tomorrow evening at 7": the part of day that decides am/pm for the clock time.
    var partHint: WhenDayPart?
    var duration: WhenSpan?
    var repeats: WhenRepeat?
    /// A repeat's last moment ("every 10 minutes until 6pm").
    var until: WhenEnd?
    var start = 0
    var end = 0

    /// Combines two atoms of one phrase ("tomorrow" + "at 5"); nil when they contradict each other.
    func merged(with next: WhenAtom) -> WhenAtom? {
        var out = self
        out.end = max(end, next.end)
        if duration != nil || next.duration != nil { return nil }
        if let d = next.day {
            if let own = day {
                // "Friday, October 24": the date decides, the weekday is only a label.
                switch (own, d) {
                case (.weekday, .date), (.weekday, .dayOfMonth), (.weekday, .iso): out.day = d
                case (.date, .weekday), (.dayOfMonth, .weekday), (.iso, .weekday): break
                default: return nil
                }
            } else {
                out.day = d
            }
        }
        if let t = next.time {
            if let own = time {
                switch (own, t) {
                case (.part(let p), .clock): out.time = t; out.partHint = p
                case (.clock, .part(let p)): out.partHint = p
                default: return nil
                }
            } else {
                out.time = t
            }
            if next.partHint != nil { out.partHint = next.partHint }
        }
        if let r = next.repeats {
            guard repeats == nil else { return nil }
            out.repeats = r
        }
        if next.until != nil {
            guard until == nil else { return nil }
            out.until = next.until
        }
        if out.repeats != nil, out.day != nil { return nil }
        if let r = out.repeats, r.frequency.isElapsed, out.time != nil { return nil }
        return out
    }
}

/// Recognises time phrases in tokens. Purely syntactic: nothing here knows what "now" is.
struct WhenScanner {
    let tokens: [WhenToken]
    /// First and last token that are not punctuation (-1 when there are none).
    let firstContent: Int
    let lastContent: Int

    init(tokens: [WhenToken]) {
        self.tokens = tokens
        firstContent = tokens.firstIndex { $0.kind != .punct } ?? -1
        lastContent = tokens.lastIndex { $0.kind != .punct } ?? -1
    }

    // MARK: Scanning

    func atoms() -> [WhenAtom] {
        var out: [WhenAtom] = []
        var i = 0
        while i < tokens.count {
            if var atom = match(at: i, previous: out.last) {
                atom.start = i
                // Right after the repeat ("every hour until 6") or after its time ("every day at 8 until friday").
                let repeating = atom.repeats != nil || (out.last?.repeats != nil && atom.time != nil && atom.day == nil)
                if repeating, let (end, after) = matchUntil(atom.end) {
                    atom.until = end
                    atom.end = after
                }
                out.append(atom)
                i = max(atom.end, i + 1)
            } else {
                i += 1
            }
        }
        return out
    }

    /// "until 6pm", "till friday", "until tomorrow at noon" right after a repeat. A bare hour counts as a time here
    /// ("until 6" is 18:00), as it does after "at".
    private func matchUntil(_ k: Int) -> (WhenEnd, Int)? {
        guard ["until", "till", "til"].contains(word(k) ?? "") else { return nil }
        if let day = matchDay(k + 1) {
            var end = WhenEnd(day: day.day, time: day.time, partHint: day.partHint)
            var after = day.end
            var j = day.end
            if word(j) == "at" || punct(j) == "," { j += 1 }
            if end.time == nil, let time = matchTime(j, previous: day, explicit: true), time.time != nil {
                end.time = time.time
                end.partHint = time.partHint
                after = time.end
            }
            return (end, after)
        }
        if let time = matchTime(k + 1, previous: nil, explicit: true), time.time != nil {
            return (WhenEnd(time: time.time, partHint: time.partHint), time.end)
        }
        return nil
    }

    private func match(at i: Int, previous: WhenAtom?) -> WhenAtom? {
        if let a = matchRepeat(i) { return a }
        if let a = matchOffset(i) { return a }
        if tokens[i].kind == .iso, let stamp = tokens[i].iso {
            return WhenAtom(day: .iso(stamp), time: stamp.hasTime ? .fromISO : nil, end: i + 1)
        }
        if let a = matchTime(i, previous: previous) { return a }
        return matchDay(i)
    }

    // MARK: Token access

    private func word(_ i: Int) -> String? {
        tokens.indices.contains(i) && tokens[i].kind == .word ? tokens[i].text : nil
    }

    private func punct(_ i: Int) -> String? {
        tokens.indices.contains(i) && tokens[i].kind == .punct ? tokens[i].text : nil
    }

    private func number(_ i: Int) -> WhenToken? {
        tokens.indices.contains(i) && tokens[i].kind == .number ? tokens[i] : nil
    }

    private func partWord(_ i: Int) -> WhenDayPart? {
        word(i).flatMap(WhenDayPart.init(rawValue:))
    }

    private func weekdayWord(_ i: Int) -> (iso: Int, plural: Bool, abbreviated: Bool)? {
        guard let w = word(i), let (n, plural) = WhenLexicon.weekdayNumber(w) else { return nil }
        return (n, plural, tokens[i].abbreviated)
    }

    private func monthWord(_ i: Int) -> Int? {
        word(i).flatMap(WhenLexicon.monthNumber)
    }

    /// A clock time starts at `i` ("at 5", "5pm", "17:30").
    private func timeStarts(at i: Int) -> Bool {
        if word(i) == "at" || punct(i) == "@" { return true }
        if tokens.indices.contains(i), tokens[i].kind == .clock { return true }
        return number(i) != nil && ["am", "pm"].contains(word(i + 1) ?? "")
    }

    // MARK: Durations

    private static let unitNames: Set<String> = ["second", "minute", "hour", "day", "week", "month", "year"]

    /// "in 20 min", "in an hour and a half", "in 1 hour 30 minutes", "20 minutes from now".
    private func matchOffset(_ i: Int) -> WhenAtom? {
        var j = i
        let hasIn = ["in", "after", "within"].contains(word(j) ?? "")
        if hasIn { j += 1 } else if readQuantity(j) == nil { return nil }

        var span = WhenSpan()
        var parsed = false
        while let (amount, afterAmount) = readQuantity(j), let (name, afterUnit) = readUnit(afterAmount, afterNumber: tokens[j].kind == .number) {
            guard add(amount, name, to: &span) else { return nil }
            j = afterUnit
            // "an hour and a half"
            if word(j) == "and", ["a", "an"].contains(word(j + 1) ?? ""), word(j + 2) == "half" {
                guard add(0.5, name, to: &span) else { return nil }
                j += 3
            }
            parsed = true
            // Another term: "1 hour 30 minutes", "2 hours and 15 min".
            var next = j
            if punct(next) == "," { next += 1 }
            if word(next) == "and" { next += 1 }
            guard let (_, afterNext) = readQuantity(next), readUnit(afterNext, afterNumber: tokens[next].kind == .number) != nil else { break }
            j = next
        }
        guard parsed else { return nil }
        if !hasIn {
            guard word(j) == "from", word(j + 1) == "now" else { return nil }
            j += 2
        }
        if span.seconds == 0 {
            return WhenAtom(day: .relative(days: span.days, months: span.months, years: span.years), end: j)
        }
        return WhenAtom(duration: span, end: j)
    }

    /// How many: "20", "an", "half an", "a couple of", "two".
    private func readQuantity(_ i: Int) -> (Double, Int)? {
        if let n = number(i), !n.ordinal, n.number > 0 { return (n.number, i + 1) }
        guard let w = word(i) else { return nil }
        if w == "half" { return (0.5, ["a", "an"].contains(word(i + 1) ?? "") ? i + 2 : i + 1) }
        if w == "a" || w == "an" {
            if word(i + 1) == "couple" { return (2, word(i + 2) == "of" ? i + 3 : i + 2) }
            if word(i + 1) == "half" { return (0.5, i + 2) }
            return (1, i + 1)
        }
        if w == "couple" { return (2, word(i + 1) == "of" ? i + 2 : i + 1) }
        if let v = WhenLexicon.numberWords[w] { return (v, i + 1) }
        return nil
    }

    /// The unit word, or a single letter right after a number ("20m", "2h").
    private func readUnit(_ i: Int, afterNumber: Bool) -> (String, Int)? {
        guard let w = word(i) else { return nil }
        if Self.unitNames.contains(w) { return (w, i + 1) }
        if afterNumber {
            switch w {
            case "s": return ("second", i + 1)
            case "m": return ("minute", i + 1)
            case "h": return ("hour", i + 1)
            case "d": return ("day", i + 1)
            case "w": return ("week", i + 1)
            default: break
            }
        }
        return nil
    }

    private func add(_ amount: Double, _ unit: String, to span: inout WhenSpan) -> Bool {
        // Checked first: `Int(amount)` below traps on a number past Int.max ("in 99999999999999999999 days").
        guard amount < 100_000 else { return false }
        let whole = amount == amount.rounded()
        switch unit {
        case "second": span.seconds += amount
        case "minute": span.seconds += amount * 60
        case "hour": span.seconds += amount * 3600
        case "day":
            if whole { span.days += Int(amount) } else { span.seconds += amount * 86400 }
        case "week":
            if whole { span.days += Int(amount) * 7 } else { span.seconds += amount * 7 * 86400 }
        case "month":
            guard whole else { return false }
            span.months += Int(amount)
        case "year":
            guard whole else { return false }
            span.years += Int(amount)
        default: return false
        }
        return true
    }

    // MARK: Clock times and parts of the day

    private static let unitNouns: Set<String> = [
        "page", "pages", "people", "person", "items", "item", "times", "things", "words", "lines", "files", "steps", "tasks",
        "minute", "hour", "second", "day", "week", "month", "year", "dollars", "euros", "bucks", "percent", "points",
        "degrees", "miles", "km", "kg", "pounds", "cards", "tabs", "emails", "messages", "calls", "meetings",
    ]

    /// - Parameter explicit: the words before already said a time comes ("until 6"), as "at" does.
    private func matchTime(_ i: Int, previous: WhenAtom?, explicit: Bool = false) -> WhenAtom? {
        // "in the morning/afternoon/evening", "in the night"
        if word(i) == "in", word(i + 1) == "the", let p = partWord(i + 2) {
            return WhenAtom(time: .part(p), end: i + 3)
        }
        // a part of the day right after a day ("tomorrow morning")
        if let p = partWord(i), let prev = previous, prev.end == i, prev.day != nil, prev.time == nil {
            return WhenAtom(time: .part(p), end: i + 1)
        }

        var k = i
        var explicitAt = explicit
        if let w = word(k), ["at", "by", "around"].contains(w) { explicitAt = true; k += 1 }
        else if punct(k) == "@" { explicitAt = true; k += 1 }

        // "end of (the) day", "eod", "cob": the working day ends at 17:00
        if word(k) == "eod" || word(k) == "cob" { return WhenAtom(time: .clock(hour: 17, minute: 0, meridiem: nil, exact24: true), end: k + 1) }
        if word(k) == "end", word(k + 1) == "of" {
            let dayAt = word(k + 2) == "the" ? k + 3 : k + 2
            if word(dayAt) == "day" { return WhenAtom(time: .clock(hour: 17, minute: 0, meridiem: nil, exact24: true), end: dayAt + 1) }
        }
        if let w = word(k) {
            if w == "noon" { return WhenAtom(time: .noon, end: k + 1) }
            if w == "midnight" { return WhenAtom(time: .midnight, end: k + 1) }
            if explicitAt, let p = partWord(k) { return WhenAtom(time: .part(p), end: k + 1) }
            if explicitAt, let spelled = WhenLexicon.numberWords[w], spelled <= 12 {
                return clock(hour: Int(spelled), minute: 0, hasColon: false, leadingZero: false, tokenAt: k, explicitAt: true)
            }
        }
        guard tokens.indices.contains(k) else { return nil }
        let t = tokens[k]
        if t.kind == .clock, t.clockHour < 24, t.clockMinute < 60 {
            return clock(hour: t.clockHour, minute: t.clockMinute, hasColon: true, leadingZero: t.leadingZero, tokenAt: k, explicitAt: explicitAt)
        }
        if t.kind == .number, t.isInteger, !t.ordinal, t.number < 24 {
            // "friday 3" or "tomorrow 9" as the last words: a day followed by a bare hour.
            let closesADay = k == lastContent && (1...12).contains(Int(t.number)) && previous.map { $0.end == k && $0.day != nil && $0.time == nil } == true
            return clock(hour: Int(t.number), minute: 0, hasColon: false, leadingZero: false, tokenAt: k, explicitAt: explicitAt || closesADay)
        }
        return nil
    }

    /// Reads what follows the hour/minute token: am/pm, "o'clock", "in the evening", "sharp".
    private func clock(hour: Int, minute: Int, hasColon: Bool, leadingZero: Bool, tokenAt k: Int, explicitAt: Bool) -> WhenAtom? {
        var j = k + 1
        var meridiem: WhenMeridiem?
        var hint: WhenDayPart?
        var oclock = false
        if let w = word(j), w == "am" || w == "pm" {
            guard (1...12).contains(hour) else { return nil }
            meridiem = w == "am" ? .am : .pm
            j += 1
        } else if word(j) == "o'clock" {
            j += 1
            oclock = true
        } else if word(j) == "in", word(j + 1) == "the", let p = partWord(j + 2) {
            hint = p
            j += 3
        }
        if ["sharp", "exactly"].contains(word(j) ?? "") { j += 1 }

        // Without am/pm or a colon, only "at 5" counts as a time; "5" alone is just a number.
        if meridiem == nil, !hasColon, !explicitAt, !oclock { return nil }
        // "look at 5 pages" is not a time.
        if meridiem == nil, !hasColon, hint == nil, let follower = word(j), Self.unitNouns.contains(follower) { return nil }

        let exact24 = hour == 0 || hour >= 13 || leadingZero
        var atom = WhenAtom(time: .clock(hour: hour, minute: minute, meridiem: meridiem, exact24: exact24), end: j)
        atom.partHint = hint
        return atom
    }

    // MARK: Days and dates

    private static let dayPrefixes: Set<String> = ["on", "by", "this", "next", "coming", "upcoming"]

    private func matchDay(_ i: Int) -> WhenAtom? {
        // "(the) day after tomorrow"
        var s = i
        if word(s) == "the" { s += 1 }
        if word(s) == "day", word(s + 1) == "after", word(s + 2) == "tomorrow" {
            return WhenAtom(day: .dayAfterTomorrow, end: s + 3)
        }

        var k = i
        var prefix: String?
        if let w = word(k), Self.dayPrefixes.contains(w) { prefix = w; k += 1 }
        // "this coming friday"
        if prefix == "this" || prefix == "next", ["coming", "upcoming"].contains(word(k) ?? "") { k += 1 }
        let isNext = prefix == "next"
        let isThis = prefix == "this"
        var the = k
        if word(the) == "the", prefix == nil || prefix == "on" { the += 1 }

        if let w = word(k) {
            if !isNext, !isThis, w == "tomorrow" { return WhenAtom(day: .tomorrow, end: k + 1) }
            if prefix != "next", w == "today" { return WhenAtom(day: .today, end: k + 1) }
            if prefix == nil, w == "tonight" { return WhenAtom(day: .today, time: .part(.night), end: k + 1) }
            if isThis, let p = partWord(k) { return WhenAtom(day: .today, time: .part(p), end: k + 1) }
            if isNext, w == "week" { return WhenAtom(day: .nextWeek, end: k + 1) }
            if isNext, w == "month" { return WhenAtom(day: .nextMonth, end: k + 1) }
            if isNext, w == "year" { return WhenAtom(day: .nextYear, end: k + 1) }
        }
        if word(the) == "weekend", prefix != "by" { return WhenAtom(day: .weekend, end: the + 1) }

        if let wd = weekdayWord(k), !wd.plural {
            // "sat" and "sun" are also ordinary words: trust them only with a day word before or a time after.
            if wd.abbreviated, prefix == nil, !timeStarts(at: k + 1) { return nil }
            return WhenAtom(day: .weekday(wd.iso, next: isNext), end: k + 1)
        }

        if prefix == nil || prefix == "on" || prefix == "by" {
            if let md = monthDay(at: the) { return WhenAtom(day: .date(month: md.month, day: md.day, year: md.year), end: md.end) }
            if prefix == "on", let n = number(the), n.ordinal, n.isInteger, (1...31).contains(Int(n.number)) {
                return WhenAtom(day: .dayOfMonth(Int(n.number)), end: the + 1)
            }
        }
        return nil
    }

    private static let maxDays = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    /// "nov 12", "november 12th, 2026", "12 nov", "the 12th of november". Needs a day number next to the month.
    private func monthDay(at k: Int) -> (month: Int, day: Int, year: Int?, end: Int)? {
        func finish(_ month: Int, _ day: Int, _ end: Int) -> (month: Int, day: Int, year: Int?, end: Int)? {
            guard (1...31).contains(day), day <= Self.maxDays[month - 1] else { return nil }
            // "march 5pm" is a time, not the fifth of March.
            if ["am", "pm"].contains(word(end) ?? "") { return nil }
            var e = end
            var year: Int?
            var y = e
            if punct(y) == "," { y += 1 }
            if let t = number(y), t.isInteger, !t.ordinal, (2000...2200).contains(Int(t.number)) {
                year = Int(t.number)
                e = y + 1
            }
            return (month, day, year, e)
        }
        if let m = monthWord(k), let n = number(k + 1), n.isInteger { return finish(m, Int(n.number), k + 2) }
        if let n = number(k), n.isInteger, !["am", "pm"].contains(word(k + 1) ?? "") {
            var m = k + 1
            if word(m) == "of" { m += 1 }
            if let month = monthWord(m) { return finish(month, Int(n.number), m + 1) }
        }
        return nil
    }

    // MARK: Repeating

    private func matchRepeat(_ i: Int) -> WhenAtom? {
        guard let w = word(i) else { return nil }
        switch w {
        case "every", "each": return matchEvery(i)
        case "daily", "everyday": return adverb(WhenRepeat(frequency: .daily), from: i, to: i + 1)
        case "hourly": return adverb(WhenRepeat(frequency: .hourly), from: i, to: i + 1)
        case "weekdays": return adverb(WhenRepeat(frequency: .weekdays), from: i, to: i + 1)
        case "fortnightly": return adverb(WhenRepeat(frequency: .weekly, interval: 2), from: i, to: i + 1)
        case "weekly":
            if let (days, end) = onWeekdays(i + 1) { return adverb(WhenRepeat(frequency: .weekly, weekdays: days), from: i, to: end) }
            return adverb(WhenRepeat(frequency: .weekly), from: i, to: i + 1)
        case "monthly":
            if let (day, end) = onDayOfMonth(i + 1) { return adverb(WhenRepeat(frequency: .monthly, dayOfMonth: day), from: i, to: end) }
            return adverb(WhenRepeat(frequency: .monthly), from: i, to: i + 1)
        case "yearly", "annually":
            if let (md, end) = onDate(i + 1) { return adverb(WhenRepeat(frequency: .yearly, month: md.month, day: md.day), from: i, to: end) }
            return adverb(WhenRepeat(frequency: .yearly), from: i, to: i + 1)
        case "on":
            // "on mondays", "on tuesdays and thursdays"
            if let wd = weekdayWord(i + 1), wd.plural, let (days, end) = weekdayList(i + 1) {
                return WhenAtom(repeats: WhenRepeat(frequency: .weekly, weekdays: days), end: end)
            }
            return nil
        default:
            if let wd = weekdayWord(i), wd.plural, let (days, end) = weekdayList(i) {
                return adverb(WhenRepeat(frequency: .weekly, weekdays: days), from: i, to: end)
            }
            return nil
        }
    }

    /// "daily" or "weekly" as a bare word is only a schedule at the edge of the sentence or before a time;
    /// "the weekly report" is not one.
    private func adverb(_ spec: WhenRepeat, from i: Int, to end: Int) -> WhenAtom? {
        let atEdge = i <= firstContent || end > lastContent
        let beforeTime = word(end) == "at" || word(end) == "on" || punct(end) == "@" || (tokens.indices.contains(end) && tokens[end].kind == .clock)
        guard atEdge || beforeTime else { return nil }
        return WhenAtom(repeats: spec, end: end)
    }

    private func matchEvery(_ i: Int) -> WhenAtom? {
        var k = i + 1
        var interval = 1
        if word(k) == "other" {
            interval = 2
            k += 1
        } else if let n = number(k), n.isInteger, !n.ordinal, (1...999).contains(Int(n.number)) {
            guard let u = word(k + 1) else { return nil }
            // Seconds are too fine for a reminder (its smallest step is a minute): left alone, never rounded.
            guard ["minute", "hour", "day", "week", "month", "year"].contains(u) else { return nil }
            interval = Int(n.number)
            k += 1
        } else if word(k) == "half", word(k + 1) == "hour" || (["a", "an"].contains(word(k + 1) ?? "") && word(k + 2) == "hour") {
            // "every half hour", "every half an hour"
            return WhenAtom(repeats: WhenRepeat(frequency: .minutely, interval: 30), end: word(k + 1) == "hour" ? k + 2 : k + 3)
        }
        guard let u = word(k) else { return nil }
        switch u {
        case "minute": return WhenAtom(repeats: WhenRepeat(frequency: .minutely, interval: interval), end: k + 1)
        case "day": return WhenAtom(repeats: WhenRepeat(frequency: .daily, interval: interval), end: k + 1)
        case "hour": return WhenAtom(repeats: WhenRepeat(frequency: .hourly, interval: interval), end: k + 1)
        case "week":
            let (days, end) = onWeekdays(k + 1) ?? ([], k + 1)
            return WhenAtom(repeats: WhenRepeat(frequency: .weekly, interval: interval, weekdays: days), end: end)
        case "month":
            let (day, end) = onDayOfMonth(k + 1) ?? (nil, k + 1)
            return WhenAtom(repeats: WhenRepeat(frequency: .monthly, interval: interval, dayOfMonth: day), end: end)
        case "year":
            let (md, end) = onDate(k + 1) ?? (nil, k + 1)
            return WhenAtom(repeats: WhenRepeat(frequency: .yearly, interval: interval, month: md?.month, day: md?.day), end: end)
        case "weekday", "weekdays":
            return interval == 1 ? WhenAtom(repeats: WhenRepeat(frequency: .weekdays), end: k + 1) : nil
        case "weekend":
            return WhenAtom(repeats: WhenRepeat(frequency: .weekly, interval: interval, weekdays: [6, 7]), end: k + 1)
        case "working", "business":
            return word(k + 1) == "day" && interval == 1 ? WhenAtom(repeats: WhenRepeat(frequency: .weekdays), end: k + 2) : nil
        case "morning", "afternoon", "evening", "night":
            return WhenAtom(time: .part(WhenDayPart(rawValue: u)!), repeats: WhenRepeat(frequency: .daily, interval: interval), end: k + 1)
        default:
            if weekdayWord(k) != nil, let (days, end) = weekdayList(k) {
                return WhenAtom(repeats: WhenRepeat(frequency: .weekly, interval: interval, weekdays: days), end: end)
            }
            if let md = monthDay(at: k) {
                return WhenAtom(repeats: WhenRepeat(frequency: .yearly, interval: interval, month: md.month, day: md.day), end: md.end)
            }
            return nil
        }
    }

    /// "monday", "mon, wed and fri": ISO weekdays and where the list ends.
    private func weekdayList(_ k: Int) -> ([Int], Int)? {
        guard let first = weekdayWord(k) else { return nil }
        var days = [first.iso]
        var j = k + 1
        while true {
            var m = j
            if let p = punct(m), [",", "&", "/"].contains(p) { m += 1 }
            if ["and", "or"].contains(word(m) ?? "") { m += 1 }
            guard m != j, let next = weekdayWord(m) else { break }
            days.append(next.iso)
            j = m + 1
        }
        return (Array(Set(days)).sorted(), j)
    }

    /// "on tue and thu" after "weekly".
    private func onWeekdays(_ k: Int) -> ([Int], Int)? {
        guard word(k) == "on" else { return nil }
        return weekdayList(k + 1)
    }

    /// "on the 1st", "on the last day (of the month)".
    private func onDayOfMonth(_ k: Int) -> (Int, Int)? {
        guard word(k) == "on" else { return nil }
        var j = k + 1
        if word(j) == "the" { j += 1 }
        if let n = number(j), n.ordinal, n.isInteger, (1...31).contains(Int(n.number)) { return (Int(n.number), j + 1) }
        if word(j) == "last", word(j + 1) == "day" {
            j += 2
            if word(j) == "of", word(j + 1) == "the", word(j + 2) == "month" { j += 3 }
            return (31, j)
        }
        return nil
    }

    /// "on nov 12" after "yearly".
    private func onDate(_ k: Int) -> ((month: Int, day: Int), Int)? {
        guard word(k) == "on" else { return nil }
        var j = k + 1
        if word(j) == "the" { j += 1 }
        guard let md = monthDay(at: j) else { return nil }
        return ((md.month, md.day), md.end)
    }
}
