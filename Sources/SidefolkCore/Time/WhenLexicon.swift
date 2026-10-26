import Foundation

/// An ISO 8601 date or date-time found in the text.
struct WhenISOStamp: Sendable, Equatable {
    var year: Int, month: Int, day: Int
    var hour = 0, minute = 0, second = 0
    var hasTime = false
    /// Seconds from UTC when the text names a zone ("Z", "+01:00"); nil means the user's calendar zone.
    var offset: Int?
}

/// One piece of the input: a word (canonicalised, typos fixed), a number, a clock time, an ISO
/// stamp or a single punctuation character. `range` always points into the original text.
struct WhenToken: Sendable {
    enum Kind: Sendable { case word, number, clock, iso, punct }
    var kind: Kind
    var text: String
    var range: Range<String.Index>
    var number = 0.0
    var ordinal = false
    var clockHour = 0
    var clockMinute = 0
    /// "09:30": written like a 24-hour time.
    var leadingZero = false
    /// Weekday or month written short ("fri", "nov"); only trusted next to other date words.
    var abbreviated = false
    var iso: WhenISOStamp?

    /// A whole number small enough for any time to use. Typing "dec 99999999999999999999" must not
    /// crash the hint line: `Int(_:)` traps on a Double past Int.max, so every conversion checks this.
    var isInteger: Bool { kind == .number && number == number.rounded() && abs(number) < 1_000_000_000 }
}

/// The words the time parser knows, including common typos and short forms.
enum WhenLexicon {
    static let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    static let weekdayShorts: [String: Int] = [
        "mon": 1, "tue": 2, "tues": 2, "wed": 3, "weds": 3, "thu": 4, "thur": 4, "thurs": 4, "fri": 5, "sat": 6, "sun": 7,
    ]
    static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
                         "november", "december"]
    static let monthShorts: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    /// Exact spellings and abbreviations mapped to the canonical word.
    static let aliases: [String: String] = [
        "tmrw": "tomorrow", "tmr": "tomorrow", "tmrrw": "tomorrow", "tmrow": "tomorrow", "tmw": "tomorrow",
        "tomorow": "tomorrow", "tomorrrow": "tomorrow", "tommorow": "tomorrow", "tommorrow": "tomorrow",
        "tomoro": "tomorrow", "tomorro": "tomorrow",
        "tonite": "tonight", "2nite": "tonight", "tnite": "tonight",
        "sec": "second", "secs": "second", "seconds": "second",
        "min": "minute", "mins": "minute", "minutes": "minute",
        "hr": "hour", "hrs": "hour", "hours": "hour",
        "days": "day", "wk": "week", "wks": "week", "weeks": "week", "months": "month",
        "yr": "year", "yrs": "year", "years": "year",
        "midday": "noon", "oclock": "o'clock",
    ]

    /// Longer words a typo may stand for, with the canonical form each maps to.
    static let fuzzyTargets: [String: String] = {
        var t: [String: String] = [
            "tomorrow": "tomorrow", "tonight": "tonight", "midnight": "midnight", "morning": "morning",
            "afternoon": "afternoon", "evening": "evening", "minute": "minute", "minutes": "minute", "second": "second",
            "seconds": "second", "weekday": "weekday", "weekdays": "weekdays", "weekend": "weekend",
        ]
        for w in weekdays + months where w.count >= 6 { t[w] = w }
        return t
    }()

    /// Canonical form of a lowercase word: aliases, abbreviations and typos resolved.
    static func canonical(_ word: String) -> (text: String, abbreviated: Bool) {
        if let alias = aliases[word] { return (alias, false) }
        if let n = weekdayShorts[word] { return (weekdays[n - 1], true) }
        if let n = monthShorts[word] { return (months[n - 1], true) }
        if let exact = fuzzyTargets[word] { return (exact, false) }
        guard word.count >= 6, word.allSatisfy(\.isLetter), !isPlural(word) else { return (word, false) }
        var best: (target: String, distance: Int)?
        var tied = false
        for target in fuzzyTargets.keys where target.first == word.first {
            let limit = target.count >= 8 ? 2 : (target.count >= 6 ? 1 : 0)
            guard abs(target.count - word.count) <= limit else { continue }
            let d = editDistance(Array(word), Array(target), limit: limit)
            guard d <= limit else { continue }
            if let b = best, d == b.distance, fuzzyTargets[b.target] != fuzzyTargets[target] { tied = true }
            if best == nil || d < best!.distance { best = (target, d); tied = false }
        }
        if let best, !tied { return (fuzzyTargets[best.target]!, false) }
        return (word, false)
    }

    /// "mondays": a weekday name used as a repeating day.
    static func isPlural(_ word: String) -> Bool {
        word.hasSuffix("s") && weekdays.contains(String(word.dropLast()))
    }

    /// 1...7 for a canonical weekday word ("monday", "mondays").
    static func weekdayNumber(_ word: String) -> (iso: Int, plural: Bool)? {
        if let i = weekdays.firstIndex(of: word) { return (i + 1, false) }
        if isPlural(word), let i = weekdays.firstIndex(of: String(word.dropLast())) { return (i + 1, true) }
        return nil
    }

    static func monthNumber(_ word: String) -> Int? { months.firstIndex(of: word).map { $0 + 1 } }

    static let numberWords: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
    ]

    /// Damerau-Levenshtein (adjacent swaps count once); stops early beyond `limit`.
    static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev2 = [Int](repeating: 0, count: b.count + 1)
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var row = [Int](repeating: 0, count: b.count + 1)
            row[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                row[j] = min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { row[j] = min(row[j], prev2[j - 2] + 1) }
            }
            if (row.min() ?? 0) > limit { return limit + 1 }
            prev2 = prev
            prev = row
        }
        return prev[b.count]
    }
}

/// Splits text into `WhenToken`s. "5pm" becomes a number and "pm"; "17:30" is one clock token;
/// "1st" is an ordinal number; "a.m." is "am"; ISO stamps stay whole.
enum WhenTokenizer {
    static func tokenize(_ text: String) -> [WhenToken] {
        var tokens: [WhenToken] = []
        var i = text.startIndex
        let end = text.endIndex

        func isDigit(_ c: Character) -> Bool { c.isASCII && c.isWholeNumber }
        func at(_ index: String.Index, _ offset: Int) -> Character? {
            guard let j = text.index(index, offsetBy: offset, limitedBy: end), j < end else { return nil }
            return text[j]
        }

        while i < end {
            let c = text[i]
            if c.isWhitespace { i = text.index(after: i); continue }

            if isDigit(c) {
                if let (stamp, length) = scanISO(text, from: i) {
                    let j = text.index(i, offsetBy: length)
                    tokens.append(WhenToken(kind: .iso, text: String(text[i..<j]), range: i..<j, iso: stamp))
                    i = j
                    continue
                }
                var j = i
                while j < end, isDigit(text[j]) { j = text.index(after: j) }
                let digits = String(text[i..<j])

                // 17:30, 5:30 (exactly two minute digits)
                if j < end, text[j] == ":", let d1 = at(j, 1), let d2 = at(j, 2), isDigit(d1), isDigit(d2),
                   !(at(j, 3).map(isDigit) ?? false) {
                    var k = text.index(j, offsetBy: 3)
                    // optional :ss
                    if k < end, text[k] == ":", let s1 = at(k, 1), let s2 = at(k, 2), isDigit(s1), isDigit(s2) { k = text.index(k, offsetBy: 3) }
                    var t = WhenToken(kind: .clock, text: String(text[i..<k]), range: i..<k)
                    t.clockHour = Int(digits) ?? 0
                    t.clockMinute = Int(String([d1, d2])) ?? 0
                    t.leadingZero = digits.count > 1 && digits.hasPrefix("0")
                    tokens.append(t)
                    i = k
                    continue
                }
                // 1.5
                if j < end, text[j] == ".", let d = at(j, 1), isDigit(d) {
                    var k = text.index(after: j)
                    while k < end, isDigit(text[k]) { k = text.index(after: k) }
                    var t = WhenToken(kind: .number, text: String(text[i..<k]), range: i..<k)
                    t.number = Double(text[i..<k]) ?? 0
                    tokens.append(t)
                    i = k
                    continue
                }
                var t = WhenToken(kind: .number, text: digits, range: i..<j)
                t.number = Double(digits) ?? 0
                // 1st, 2nd, 3rd, 12th
                var k = j
                while k < end, text[k].isLetter { k = text.index(after: k) }
                if k > j, ["st", "nd", "rd", "th"].contains(text[j..<k].lowercased()) {
                    t.ordinal = true
                    t.range = i..<k
                    j = k
                }
                tokens.append(t)
                i = j
                continue
            }

            if c.isLetter {
                var j = text.index(after: i)
                // a.m. / p.m.
                if "aApP".contains(c), at(i, 1) == ".", let m = at(i, 2), m == "m" || m == "M" {
                    j = text.index(i, offsetBy: 3)
                    if j < end, text[j] == "." { j = text.index(after: j) }
                    tokens.append(WhenToken(kind: .word, text: c.lowercased() + "m", range: i..<j))
                    i = j
                    continue
                }
                while j < end {
                    let d = text[j]
                    if d.isLetter { j = text.index(after: j); continue }
                    // o'clock, don't, tomorrow's: keep the apostrophe inside the word
                    if d == "'" || d == "\u{2019}", let n = at(j, 1), n.isLetter { j = text.index(after: j); continue }
                    break
                }
                let raw = String(text[i..<j]).lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
                let (word, abbreviated) = WhenLexicon.canonical(raw)
                var t = WhenToken(kind: .word, text: word, range: i..<j)
                t.abbreviated = abbreviated
                tokens.append(t)
                i = j
                continue
            }

            let j = text.index(after: i)
            tokens.append(WhenToken(kind: .punct, text: String(c), range: i..<j))
            i = j
        }
        return tokens
    }

    /// 2025-11-12, 2025-11-12T09:30, 2025-11-12 09:30:15, with optional fraction and Z / +01:00.
    static func scanISO(_ text: String, from start: String.Index) -> (WhenISOStamp, Int)? {
        let chars = Array(text[start...].prefix(40))
        func digits(_ from: Int, _ count: Int) -> Int? {
            guard from + count <= chars.count else { return nil }
            var v = 0
            for k in from..<(from + count) {
                guard chars[k].isASCII, let d = chars[k].wholeNumberValue else { return nil }
                v = v * 10 + d
            }
            return v
        }
        guard chars.count >= 10, let y = digits(0, 4), chars[4] == "-", let m = digits(5, 2), chars[7] == "-", let d = digits(8, 2),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        var stamp = WhenISOStamp(year: y, month: m, day: d)
        var length = 10
        if chars.count >= 16, "Tt ".contains(chars[10]), let h = digits(11, 2), chars[13] == ":", let mi = digits(14, 2), h < 24, mi < 60 {
            stamp.hasTime = true
            stamp.hour = h
            stamp.minute = mi
            length = 16
            if chars.count >= 19, chars[16] == ":", let s = digits(17, 2), s < 60 {
                stamp.second = s
                length = 19
                if chars.count > 20, chars[19] == ".", chars[20].isASCII, chars[20].isNumber {
                    length = 20
                    while length < chars.count, chars[length].isASCII, chars[length].isNumber { length += 1 }
                }
            }
            if length < chars.count {
                if chars[length] == "Z" || chars[length] == "z" {
                    stamp.offset = 0
                    length += 1
                } else if chars[length] == "+" || chars[length] == "-", let oh = digits(length + 1, 2) {
                    var om = 0
                    var used = 3
                    if length + 3 < chars.count, chars[length + 3] == ":", let v = digits(length + 4, 2) { om = v; used = 6 }
                    else if let v = digits(length + 3, 2) { om = v; used = 5 }
                    stamp.offset = (chars[length] == "-" ? -1 : 1) * (oh * 3600 + om * 60)
                    length += used
                }
            }
        }
        return (stamp, length)
    }
}
