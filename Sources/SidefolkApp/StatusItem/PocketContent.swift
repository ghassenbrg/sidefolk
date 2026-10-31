import AppKit
import SidefolkCore

/// What the menu bar's Pocket shows (D84), gathered by the app when it opens: the companion and its state, Open, Focus
/// or Quiet, Full access, an update, then what needs the person, what's next and which agents are at work. Only what
/// Sidefolk keeps: nothing here is made up for the picture.
struct PocketContent {
    struct Row: Identifiable {
        var id: String
        var title: String
        var detail: String?
        /// A time or a duration on the trailing side ("16:30", "14 min").
        var trailing: String?
        var symbol: String
        /// The folk whose domain it is (its avatar), or nil for a symbol on a well.
        var folk: String?
        /// Something going on right now (an agent working): a live dot.
        var live = false
        var open: () -> Void
    }

    var name = "Mochi"
    var avatar: NSImage?
    var attention: AttentionMode = .open
    var attentionEnds: Date?
    var quietHours: QuietHours?
    /// The ends offered for Focus and Quiet, with the person's own morning and evening hours.
    var spans: [AttentionSpan] = []
    /// Held for the end of Focus or Quiet.
    var held = 0
    var fullAccess = false
    var fullAccessEnds: Date?
    /// A version of Sidefolk waiting ("0.1.0 snapshot 560"), and whether it is downloaded and checked.
    var update: String?
    var updateReady = false
    var companionVisible = true
    var needsYou: [Row] = []
    var nextUp: [Row] = []
    var agents: [Row] = []
    var watching = 0
    var hotkey = ""

    /// The line under the name: what the menu bar mark says, in words.
    var stateLine: String {
        var parts: [String] = []
        switch attention {
        case .open:
            parts.append(needsYou.isEmpty ? String(localized: "All clear", comment: "The Pocket: nothing waits")
                         : String(localized: "Waiting on you · \(needsYou.count)", comment: "The Pocket: things wait, “Waiting on you · 3”"))
        case .focus:
            parts.append(attentionEnds.map { String(localized: "Focus until \(TimeText.short($0))", comment: "Settings › Attention: “Focus until 17:00”") }
                         ?? String(localized: "Focus", comment: "Attention: only cards that need an answer; whispers wait"))
        case .quiet:
            parts.append(attentionEnds.map { String(localized: "Quiet until \(TimeText.short($0))") }
                         ?? String(localized: "Quiet", comment: "Attention: only what can't wait"))
        }
        if attention != .open, held > 0 {
            parts.append(String(localized: "holding \(held)", comment: "The Pocket: things held for the end of Focus or Quiet, “holding 2”"))
        }
        if watching > 0 { parts.append(String(localized: "watching \(watching)", comment: "The Pocket: “watching 3”")) }
        return parts.joined(separator: " · ")
    }
}

/// What the Pocket can ask of the app.
@MainActor
struct PocketActions {
    var ask: (String) -> Void = { _ in }
    var setAttention: (AttentionMode, Date?) -> Void = { _, _ in }
    var turnOffFullAccess: () -> Void = {}
    var showCompanion: () -> Void = {}
    var update: () -> Void = {}
    var openHome: () -> Void = {}
    var openToday: () -> Void = {}
    var openSettings: () -> Void = {}
    var openAttentionSettings: () -> Void = {}
    var toggleCompanion: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var about: () -> Void = {}
    var openPalette: (String) -> Void = { _ in }
    var quit: () -> Void = {}
}
