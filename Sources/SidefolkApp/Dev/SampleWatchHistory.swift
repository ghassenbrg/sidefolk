import Foundation
import SidefolkCore

/// The sample watches' history for the UI snapshots (D87): runs of checks with a change, failures and a pause, and the two
/// versions of the pricing page that changed 25 minutes ago (the change Today's card is about).
enum SampleWatchHistory {
    static func fill(_ rt: SidefolkRuntime, now: Date) async throws {
        let log = WatchHistoryStore(rt.db)
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        func run(_ id: String, _ result: WatchCheck.Result, from: Double, to: Double, count: Int, reason: String? = nil, ms: Int = 180) async throws {
            var check = WatchCheck(watcherId: id, result: result, at: ago(from), count: count, reason: reason, durationMs: ms)
            check.lastAt = ago(to)
            try await log.save(check)
        }
        try await run("w-pricing", .unchanged, from: 60 * 24, to: 60 * 9, count: 30, ms: 240)
        try await run("w-pricing", .failed, from: 60 * 8.5, to: 60 * 8, count: 2, reason: "The site didn't answer in time.", ms: 30_000)
        try await run("w-pricing", .unchanged, from: 60 * 7.5, to: 55, count: 14, ms: 210)
        try await run("w-pricing", .changed, from: 25, to: 25, count: 1, reason: "example.com/pricing changed", ms: 260)
        try await run("w-pricing", .unchanged, from: 4, to: 4, count: 1, ms: 190)
        let page = """
            Pricing
            Simple plans for every team
            Free
            $0 / month
            Up to 3 projects
            Pro
            Pro $12 / month, billed yearly
            Unlimited projects
            Priority support
            Team
            $29 / month per seat
            Single sign-on
            Questions? Write to us.
            """
        try await log.addVersion(watcherId: "w-pricing", text: page, at: ago(55))
        try await log.addVersion(watcherId: "w-pricing", text: page.replacingOccurrences(of: "Pro $12 / month, billed yearly", with: "Pro $15 / month, billed yearly")
            .replacingOccurrences(of: "Priority support", with: "Priority support\nAudit log"), at: ago(25))

        try await run("w-staging", .unchanged, from: 60 * 2, to: 22, count: 20, ms: 90)
        try await run("w-staging", .failed, from: 20, to: 1, count: 4, reason: "Couldn't reach staging.sidefolk.app (timed out).", ms: 10_000)
        try await run("w-report", .unchanged, from: 60 * 5, to: 60 * 3, count: 12, ms: 2)
        try await run("w-report", .paused, from: 60 * 3, to: 60 * 3, count: 1)
    }
}
