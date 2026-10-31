import Foundation
import SidefolkCore

/// What Today, the sidebar's nook and On duty read from Now's data (D84): the companion's state as light, the brief,
/// what comes next, and what's on duty. Nothing here is stored; it is the same data said another way.
extension NowModel {
    /// Things working for the person, by folk (`OnDuty`).
    var onDuty: OnDuty {
        OnDuty(watchers: watchers + reports, reminders: reminders, sessions: workingSessions + sessionsNeedingYou, jobs: jobs)
    }

    var quiet: Bool { quietUntil.map { $0 > Date() } ?? false }

    /// The companion's light, as the desktop's rule reads it: quiet first, then what waits on the person, then work.
    var poolState: LightPoolState {
        if quiet { return .quiet }
        if needsYouCount > 0 { return .waiting(needsYouCount) }
        if watchers.contains(where: { $0.state == .error }) { return .alert }
        if !workingSessions.isEmpty || !jobs.isEmpty || ownRun != nil { return .working }
        return .idle
    }

    /// The companion's pose in its nook, for the same state.
    var poolPose: CharacterStateName {
        switch poolState {
        case .quiet: .sleeping
        case .waiting, .alert: .waiting
        case .working: .working
        default: .idle
        }
    }

    /// The nook's state word ("Waiting on you", "Working", "Quiet").
    var stateWord: String? {
        switch poolState {
        case .waiting: String(localized: "Waiting on you", comment: "The companion's state in Home's nook: something waits on the person")
        case .working: String(localized: "Working", comment: "The companion's state in Home's nook")
        case .alert: String(localized: "Having trouble", comment: "The companion's state in Home's nook: a watch keeps failing")
        case .quiet: String(localized: "Quiet", comment: "The companion's state in Home's nook: only urgent things get through")
        default: nil
        }
    }

    /// What comes next today: the next event or reminder still to come.
    var nextUp: (title: String, at: Date)? {
        let now = Date()
        let cal = Calendar.current
        let reminder = reminders.compactMap { r -> (String, Date)? in
            let due = r.nextDue ?? r.fireAt
            return due > now && cal.isDateInToday(due) ? (r.title, due) : nil
        }
        let event = events.filter { !$0.allDay && $0.start > now && cal.isDateInToday($0.start) }.map { ($0.title, $0.start) }
        return (reminder + event).min { $0.1 < $1.1 }.map { (title: $0.0, at: $0.1) }
    }

    /// Watches whose change still waits to be seen, by what they watch.
    var changedWatches: [String] {
        watchers.filter { changeWaiting(for: $0) != nil }.map { Describe.watcherTarget($0) ?? $0.title }
    }

    /// The person's first name, as the Mac knows it, for the greeting.
    static var firstName: String? {
        NSFullUserName().split(separator: " ").first.map(String.init)
    }
}

/// The companion's poses Home uses (`CharacterState` without its props).
enum CharacterStateName { case idle, sleeping, waiting, working }
