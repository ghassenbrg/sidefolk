import Foundation

enum Meridiem: Sendable, Equatable { case am, pm }
enum DayPart: String, Sendable, Equatable { case morning, afternoon, evening, night }

/// "in 2 hours" is exact seconds; "in 3 days" is calendar arithmetic and keeps the date semantics.
struct SpanDuration: Sendable, Equatable {
    var seconds = 0.0
    var days = 0
    var months = 0
    var years = 0
}

enum DaySpec: Sendable, Equatable {
    case today, tomorrow, dayAfterTomorrow
    case weekday(Int, next: Bool)
    case nextWeek, nextMonth, nextYear, weekend
    case date(month: Int, day: Int, year: Int?)
    case dayOfMonth(Int)
    case relative(days: Int, months: Int, years: Int)
    case iso(ISOStamp)
}

enum TimeSpec: Sendable, Equatable {
    case clock(hour: Int, minute: Int, meridiem: Meridiem?, exact24: Bool)
    case noon, midnight
    case part(DayPart)
    /// The time comes with the ISO stamp.
    case fromISO
}

struct RepeatSpec: Sendable, Equatable {
    var frequency: Recurrence.Frequency
    var interval = 1
    var weekdays: [Int] = []
    /// Monthly: day of the month (31 also stands for "the last day").
    var dayOfMonth: Int?
    /// Yearly: the date.
    var month: Int?
    var day: Int?
}

/// One recognised piece of a time phrase and the tokens it covers (`start..<end`).
struct Atom: Sendable {
    var day: DaySpec?
    var time: TimeSpec?
    /// "tomorrow evening at 7": the part of day that decides am/pm for the clock time.
    var partHint: DayPart?
    var duration: SpanDuration?
    var repeats: RepeatSpec?
    var start = 0
    var end = 0

    /// Combines two atoms of one phrase ("tomorrow" + "at 5"); nil when they contradict each other.
    func merged(with next: Atom) -> Atom? {
        var out = self
        out.end = max(end, next.end)
        if duration != nil || next.duration != nil { return nil }
        if let d = next.day {
            guard day == nil else { return nil }
            out.day = d
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
        if out.repeats != nil, out.day != nil { return nil }
        if let r = out.repeats, r.frequency == .hourly, out.time != nil { return nil }
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

    func atoms() -> [Atom] {
        var out: [Atom] = []
        var i = 0
        while i < tokens.count {
            if var atom = match(at: i, previous: out.last) {
                atom.start = i
                out.append(atom)
                i = max(atom.end, i + 1)
            } else {
                i += 1
            }
        }
        return out
    }

    private func match(at i: Int, previous: Atom?) -> Atom? {
        if let a = matchRepeat(i) { return a }
        if let a = matchOffset(i) { return a }
        if tokens[i].kind == .iso, let stamp = tokens[i].iso {
            return Atom(day: .iso(stamp), time: stamp.hasTime ? .fromISO : nil, end: i + 1)
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

    private func partWord(_ i: Int) -> DayPart? {
        word(i).flatMap(DayPart.init(rawValue:))
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
    private func matchOffset(_ i: Int) -> Atom? {
        var j = i
        let hasIn = ["in", "after", "within"].contains(word(j) ?? "")
        if hasIn { j += 1 } else if number(j) == nil { return nil }

        var span = SpanDuration()
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
            return Atom(day: .relative(days: span.days, months: span.months, years: span.years), end: j)
        }
        return Atom(duration: span, end: j)
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

    private func add(_ amount: Double, _ unit: String, to span: inout SpanDuration) -> Bool {
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
        return amount < 100_000
    }

    // MARK: Clock times and parts of the day

    private static let unitNouns: Set<String> = [
        "page", "pages", "people", "person", "items", "item", "times", "things", "words", "lines", "files", "steps", "tasks",
        "minute", "hour", "second", "day", "week", "month", "year", "dollars", "euros", "bucks", "percent", "points",
        "degrees", "miles", "km", "kg", "pounds", "cards", "tabs", "emails", "messages", "calls", "meetings",
    ]

    private func matchTime(_ i: Int, previous: Atom?) -> Atom? {
        // "in the morning/afternoon/evening", "in the night"
        if word(i) == "in", word(i + 1) == "the", let p = partWord(i + 2) {
            return Atom(time: .part(p), end: i + 3)
        }
        // a part of the day right after a day ("tomorrow morning")
        if let p = partWord(i), let prev = previous, prev.end == i, prev.day != nil, prev.time == nil {
            return Atom(time: .part(p), end: i + 1)
        }

        var k = i
        var explicitAt = false
        if let w = word(k), ["at", "by", "around"].contains(w) { explicitAt = true; k += 1 }
        else if punct(k) == "@" { explicitAt = true; k += 1 }

        if let w = word(k) {
            if w == "noon" { return Atom(time: .noon, end: k + 1) }
            if w == "midnight" { return Atom(time: .midnight, end: k + 1) }
            if explicitAt, let p = partWord(k) { return Atom(time: .part(p), end: k + 1) }
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
            return clock(hour: Int(t.number), minute: 0, hasColon: false, leadingZero: false, tokenAt: k, explicitAt: explicitAt)
        }
        return nil
    }

    /// Reads what follows the hour/minute token: am/pm, "o'clock", "in the evening", "sharp".
    private func clock(hour: Int, minute: Int, hasColon: Bool, leadingZero: Bool, tokenAt k: Int, explicitAt: Bool) -> Atom? {
        var j = k + 1
        var meridiem: Meridiem?
        var hint: DayPart?
        if let w = word(j), w == "am" || w == "pm" {
            guard (1...12).contains(hour) else { return nil }
            meridiem = w == "am" ? .am : .pm
            j += 1
        } else if word(j) == "o'clock" {
            j += 1
        } else if word(j) == "in", word(j + 1) == "the", let p = partWord(j + 2) {
            hint = p
            j += 3
        }
        if ["sharp", "exactly"].contains(word(j) ?? "") { j += 1 }

        // Without am/pm or a colon, only "at 5" counts as a time; "5" alone is just a number.
        if meridiem == nil, !hasColon, !explicitAt { return nil }
        // "look at 5 pages" is not a time.
        if meridiem == nil, !hasColon, hint == nil, let follower = word(j), Self.unitNouns.contains(follower) { return nil }

        let exact24 = hour == 0 || hour >= 13 || leadingZero
        var atom = Atom(time: .clock(hour: hour, minute: minute, meridiem: meridiem, exact24: exact24), end: j)
        atom.partHint = hint
        return atom
    }

    // MARK: Days and dates

    private static let dayPrefixes: Set<String> = ["on", "by", "this", "next", "coming", "upcoming"]

    private func matchDay(_ i: Int) -> Atom? {
        // "(the) day after tomorrow"
        var s = i
        if word(s) == "the" { s += 1 }
        if word(s) == "day", word(s + 1) == "after", word(s + 2) == "tomorrow" {
            return Atom(day: .dayAfterTomorrow, end: s + 3)
        }

        var k = i
        var prefix: String?
        if let w = word(k), Self.dayPrefixes.contains(w) { prefix = w; k += 1 }
        let isNext = prefix == "next"
        let isThis = prefix == "this"
        var the = k
        if word(the) == "the", prefix == nil || prefix == "on" { the += 1 }

        if let w = word(k) {
            if !isNext, !isThis, w == "tomorrow" { return Atom(day: .tomorrow, end: k + 1) }
            if prefix != "next", w == "today" { return Atom(day: .today, end: k + 1) }
            if prefix == nil, w == "tonight" { return Atom(day: .today, time: .part(.night), end: k + 1) }
            if isThis, let p = partWord(k) { return Atom(day: .today, time: .part(p), end: k + 1) }
            if isNext, w == "week" { return Atom(day: .nextWeek, end: k + 1) }
            if isNext, w == "month" { return Atom(day: .nextMonth, end: k + 1) }
            if isNext, w == "year" { return Atom(day: .nextYear, end: k + 1) }
        }
        if word(the) == "weekend", prefix != "by" { return Atom(day: .weekend, end: the + 1) }

        if let wd = weekdayWord(k), !wd.plural {
            // "sat" and "sun" are also ordinary words: trust them only with a day word before or a time after.
            if wd.abbreviated, prefix == nil, !timeStarts(at: k + 1) { return nil }
            return Atom(day: .weekday(wd.iso, next: isNext), end: k + 1)
        }

        if prefix == nil || prefix == "on" || prefix == "by" {
            if let md = monthDay(at: the) { return Atom(day: .date(month: md.month, day: md.day, year: md.year), end: md.end) }
            if prefix == "on", let n = number(the), n.ordinal, (1...31).contains(Int(n.number)) {
                return Atom(day: .dayOfMonth(Int(n.number)), end: the + 1)
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

    private func matchRepeat(_ i: Int) -> Atom? {
        guard let w = word(i) else { return nil }
        switch w {
        case "every", "each": return matchEvery(i)
        case "daily", "everyday": return adverb(RepeatSpec(frequency: .daily), from: i, to: i + 1)
        case "hourly": return adverb(RepeatSpec(frequency: .hourly), from: i, to: i + 1)
        case "weekdays": return adverb(RepeatSpec(frequency: .weekdays), from: i, to: i + 1)
        case "fortnightly": return adverb(RepeatSpec(frequency: .weekly, interval: 2), from: i, to: i + 1)
        case "weekly":
            if let (days, end) = onWeekdays(i + 1) { return adverb(RepeatSpec(frequency: .weekly, weekdays: days), from: i, to: end) }
            return adverb(RepeatSpec(frequency: .weekly), from: i, to: i + 1)
        case "monthly":
            if let (day, end) = onDayOfMonth(i + 1) { return adverb(RepeatSpec(frequency: .monthly, dayOfMonth: day), from: i, to: end) }
            return adverb(RepeatSpec(frequency: .monthly), from: i, to: i + 1)
        case "yearly", "annually":
            if let (md, end) = onDate(i + 1) { return adverb(RepeatSpec(frequency: .yearly, month: md.month, day: md.day), from: i, to: end) }
            return adverb(RepeatSpec(frequency: .yearly), from: i, to: i + 1)
        case "on":
            // "on mondays", "on tuesdays and thursdays"
            if let wd = weekdayWord(i + 1), wd.plural, let (days, end) = weekdayList(i + 1) {
                return Atom(repeats: RepeatSpec(frequency: .weekly, weekdays: days), end: end)
            }
            return nil
        default:
            if let wd = weekdayWord(i), wd.plural, let (days, end) = weekdayList(i) {
                return adverb(RepeatSpec(frequency: .weekly, weekdays: days), from: i, to: end)
            }
            return nil
        }
    }

    /// "daily" or "weekly" as a bare word is only a schedule at the edge of the sentence or before a time;
    /// "the weekly report" is not one.
    private func adverb(_ spec: RepeatSpec, from i: Int, to end: Int) -> Atom? {
        let atEdge = i <= firstContent || end > lastContent
        let beforeTime = word(end) == "at" || word(end) == "on" || punct(end) == "@" || (tokens.indices.contains(end) && tokens[end].kind == .clock)
        guard atEdge || beforeTime else { return nil }
        return Atom(repeats: spec, end: end)
    }

    private func matchEvery(_ i: Int) -> Atom? {
        var k = i + 1
        var interval = 1
        if word(k) == "other" {
            interval = 2
            k += 1
        } else if let n = number(k), n.isInteger, !n.ordinal, (1...999).contains(Int(n.number)) {
            guard let u = word(k + 1) else { return nil }
            // "every 30 minutes" cannot be a Recurrence (the smallest step is an hour).
            guard ["hour", "day", "week", "month", "year"].contains(u) else { return nil }
            interval = Int(n.number)
            k += 1
        }
        guard let u = word(k) else { return nil }
        switch u {
        case "day": return Atom(repeats: RepeatSpec(frequency: .daily, interval: interval), end: k + 1)
        case "hour": return Atom(repeats: RepeatSpec(frequency: .hourly, interval: interval), end: k + 1)
        case "week":
            let (days, end) = onWeekdays(k + 1) ?? ([], k + 1)
            return Atom(repeats: RepeatSpec(frequency: .weekly, interval: interval, weekdays: days), end: end)
        case "month":
            let (day, end) = onDayOfMonth(k + 1) ?? (nil, k + 1)
            return Atom(repeats: RepeatSpec(frequency: .monthly, interval: interval, dayOfMonth: day), end: end)
        case "year":
            let (md, end) = onDate(k + 1) ?? (nil, k + 1)
            return Atom(repeats: RepeatSpec(frequency: .yearly, interval: interval, month: md?.month, day: md?.day), end: end)
        case "weekday", "weekdays":
            return interval == 1 ? Atom(repeats: RepeatSpec(frequency: .weekdays), end: k + 1) : nil
        case "weekend":
            return Atom(repeats: RepeatSpec(frequency: .weekly, interval: interval, weekdays: [6, 7]), end: k + 1)
        case "working", "business":
            return word(k + 1) == "day" && interval == 1 ? Atom(repeats: RepeatSpec(frequency: .weekdays), end: k + 2) : nil
        case "morning", "afternoon", "evening", "night":
            return Atom(time: .part(DayPart(rawValue: u)!), repeats: RepeatSpec(frequency: .daily, interval: interval), end: k + 1)
        default:
            if weekdayWord(k) != nil, let (days, end) = weekdayList(k) {
                return Atom(repeats: RepeatSpec(frequency: .weekly, interval: interval, weekdays: days), end: end)
            }
            if let md = monthDay(at: k) {
                return Atom(repeats: RepeatSpec(frequency: .yearly, interval: interval, month: md.month, day: md.day), end: md.end)
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
        if let n = number(j), n.ordinal, (1...31).contains(Int(n.number)) { return (Int(n.number), j + 1) }
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
