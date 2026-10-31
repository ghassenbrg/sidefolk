import Foundation

/// Today's glasses. Kept as JSON in the extension's data folder (`Paths.data`, Sidefolk's SIDEFOLK_DATA_DIR): the one
/// place the sandbox lets an extension without permissions write, kept across updates and removed with it.
struct Tally: Codable, Equatable {
    /// The local day the glasses belong to, "2026-10-31".
    var day: String
    /// When each glass was logged, oldest first.
    var times: [Date] = []
    var goal = 8
    /// 500 ml glasses instead of 250 ml.
    var largeGlasses = false

    var glasses: Int { times.count }
    var millilitres: Int { glasses * (largeGlasses ? 500 : 250) }
    var left: Int { max(0, goal - glasses) }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The tally for the day `now` falls on: a new day starts from none, keeping the goal and the glass size.
    func on(_ now: Date, calendar: Calendar = .current) -> Tally {
        let today = Self.dayKey(now, calendar: calendar)
        return day == today ? self : Tally(day: today, goal: goal, largeGlasses: largeGlasses)
    }

    /// Whether to tell the person they're behind: past `afterHour`, under half the goal, and not told yet today
    /// (`toldOn` is the day the watcher last triggered, which Sidefolk keeps in the watcher's state).
    func behind(now: Date, afterHour: Int, toldOn: String?, calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: now) >= afterHour && glasses * 2 < goal && toldOn != day
    }

    /// One line for answers and the bubble.
    var sentence: String {
        let count = glasses == 1 ? "1 glass" : "\(glasses) glasses"
        if glasses >= goal { return "\(count) of water today (\(millilitres) ml): your goal of \(goal) is reached." }
        return "\(count) of water today (\(millilitres) ml), \(left) to go for your goal of \(goal)."
    }
}

/// Reads and writes the tally file. One process answers every request, so nothing else writes it meanwhile.
@MainActor
final class TallyStore {
    private let file: URL

    init(folder: URL) {
        file = folder.appendingPathComponent("tally.json")
    }

    func today(_ now: Date = Date()) -> Tally {
        let saved = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Tally.self, from: $0) }
        return (saved ?? Tally(day: Tally.dayKey(now))).on(now)
    }

    /// Changes today's tally and saves it.
    @discardableResult
    func change(_ now: Date = Date(), _ edit: (inout Tally) -> Void) -> Tally {
        var t = today(now)
        edit(&t)
        if let data = try? JSONEncoder().encode(t) { try? data.write(to: file, options: .atomic) }
        return t
    }
}
