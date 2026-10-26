import Foundation
import Observation
import SidefolkCore

/// The audit trail: every tool call, who asked, what Guard decided and how it ended.
@MainActor @Observable
final class ActivityModel {
    enum Show: Hashable { case all, needsAttention }

    /// Caller kinds as the filter names them; nil means everyone.
    static let callerKinds: [(kind: String, title: LocalizedStringResource)] = [
        ("user", "You"), ("agent", "Sidefolk"), ("routine", "Routines"), ("external", "Other agents"), ("extension", "Extensions"),
    ]

    var show: Show = .all
    var callerKind: String?
    private(set) var entries: [ActivityEntry] = []
    private(set) var weekRuns = 0
    private(set) var weekInputTokens = 0
    private(set) var weekOutputTokens = 0
    private(set) var weekActions = 0

    let services: AppServices
    private var runtime: SidefolkRuntime { services.runtime }

    init(services: AppServices) {
        self.services = services
    }

    var companionName: String { runtime.settings.current.companionName }

    var visible: [ActivityEntry] {
        entries.filter { e in
            (show == .all || Self.needsAttention(e)) && (callerKind == nil || Describe.callerKind(e.caller) == callerKind)
        }
    }

    var attentionCount: Int { entries.filter(Self.needsAttention).count }

    static func needsAttention(_ e: ActivityEntry) -> Bool {
        [.denied, .blocked, .failed].contains(e.decision)
    }

    func reload() async {
        entries = (try? await runtime.activity.recent(limit: 1000)) ?? []
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date().addingTimeInterval(-7 * 86400)
        if let totals = try? await runtime.runs.totals(since: weekStart) {
            weekRuns = totals.runs
            weekInputTokens = totals.input
            weekOutputTokens = totals.output
        }
        weekActions = entries.filter { $0.at >= weekStart }.count
    }
}
