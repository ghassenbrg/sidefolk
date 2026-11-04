#if DEBUG
import AppKit
import SidefolkCore
import SwiftUI

/// The desktop of D84 for the UI snapshots: the Sidecard's moments with sample notices, and the companion on its floor
/// (light, shoulder mark, folks, pins, agents lane) on a plain wallpaper, as the mockups show them. The real window's
/// layout is checked in the debug app (`swift scripts/dev.swift snap`); these show the parts and how they read.
enum DesktopScenes {
    static let now = Date()

    // MARK: Sidecard moments

    static func sidecards(face: NSImage) -> [(String, SidecardModel)] {
        func moment(_ item: AttentionItem, _ shape: SidecardModel.Shape = .card, tail: CGFloat? = 0.78) -> SidecardModel {
            let model = SidecardModel()
            model.item = item
            model.shape = shape
            model.tailAt = tail
            model.face = face
            model.companionName = "Mochi"
            if shape == .whisper { model.deadline = now.addingTimeInterval(3.6) }
            return model
        }
        let actions = ReminderScheduler.ActionID.self
        let paused = moment(AttentionItem(level: .gentle, source: "external:claude-code", title: "Claude Code saved a note to Ideas",
                                          actions: [AttentionAction(id: SidecardItemCard.undo, title: String(localized: "Undo"))], refKind: "credit"),
                            .whisper)
        paused.pausedLeft = 2.4
        let stack = SidecardModel()
        stack.shape = .stack
        stack.waiting = 12
        stack.tailAt = nil
        stack.stack = [
            AttentionItem(level: .attention, source: "watcher", title: "staging.sidefolk.app is down", refKind: "watcher", now: now.addingTimeInterval(-900)),
            AttentionItem(level: .attention, source: "reminder", title: "Stretch and refill water", refKind: "reminder", now: now.addingTimeInterval(-300)),
            // As `ask.user` makes it: the question is the title, who asks is under it, and the offered answers are its actions.
            AttentionItem(level: .attention, source: "external:codex", title: "Deploy to staging?", body: "Codex asks",
                          actions: [AttentionAction(id: "option-0", title: "Yes", isPrimary: true), AttentionAction(id: "option-1", title: "No")],
                          refKind: "ask", now: now.addingTimeInterval(-60)),
        ]
        let needsYou = moment(AttentionItem(level: .attention, source: "session:cc-1", title: "Claude needs you in sidefolk",
                                            body: "Asks to use Bash: git push origin main",
                                            actions: [AttentionAction(id: "open", title: String(localized: "Open"), isPrimary: true),
                                                      AttentionAction(id: "dismiss", title: String(localized: "Dismiss"))],
                                            refKind: "session", refId: "cc-1"))
        needsYou.sessions = ["cc-1": AgentSession(id: "cc-1", agent: "claude-code", cwd: NSHomeDirectory() + "/git/sidefolk", state: .needsYou)]
        return [
            ("whisper", moment(AttentionItem(level: .gentle, source: "external:claude-code", title: "Claude Code saved a note to Ideas",
                                             actions: [AttentionAction(id: SidecardItemCard.undo, title: String(localized: "Undo"))], refKind: "credit"),
                               .whisper)),
            ("whisper-paused", paused),
            ("whisper-own", moment(AttentionItem(level: .gentle, source: AppCoordinator.ownVoice,
                                                 title: String(localized: "All clear. Nothing waits for you.", comment: "A whisper when the last held card was answered"),
                                                 refKind: "clear"), .whisper, tail: 0.5)),
            // A retired theme at launch (D92): moved to its successor, or offered it.
            ("theme-moved", moment(AppCoordinator.successionItem(.moved(from: ThemeSuccession.retired["dev.sidefolk.theme.field-notes"]!,
                                                                         to: "dev.sidefolk.theme.paper-garden"),
                                                                  successorName: "Paper Garden"), .whisper, tail: 0.5)),
            ("theme-offer", moment(AppCoordinator.successionItem(.offer(ThemeSuccession.retired["dev.sidefolk.theme.daylight"]!,
                                                                         id: "dev.sidefolk.theme.daylight"),
                                                                  successorName: "Harbor"), .card, tail: 0.5)),
            ("reminder", moment(AttentionItem(level: .attention, source: "reminder", title: "Stretch and refill water",
                                              body: "It's 17:00. Next one at 19:00, the last at 21:00.",
                                              actions: [AttentionAction(id: actions.done, title: String(localized: "Done"), isPrimary: true),
                                                        AttentionAction(id: actions.snooze10, title: String(localized: "In 10 min", comment: "A reminder card's snooze button: remind again in ten minutes")),
                                                        AttentionAction(id: actions.stop, title: String(localized: "Stop repeating"))],
                                              refKind: "reminder", refId: "r1"))),
            ("reminder-task", moment(AttentionItem(level: .attention, source: "reminder", title: "Write the onboarding email",
                                                   body: "From your note “Pockito launch plan”.",
                                                   actions: [AttentionAction(id: actions.taskDone, title: String(localized: "Mark done"), isPrimary: true),
                                                             AttentionAction(id: actions.snooze10, title: String(localized: "In 10 min", comment: "A reminder card's snooze button: remind again in ten minutes")),
                                                             AttentionAction(id: actions.open, title: String(localized: "Open"))],
                                                   refKind: "reminder", refId: "r2"))),
            ("watch", moment(AttentionItem(level: .attention, source: "watcher", title: "Pricing changed",
                                           body: "example.com/pricing: Pro went from $12 to $15.",
                                           actions: [AttentionAction(id: "open", title: String(localized: "Open"), isPrimary: true),
                                                     AttentionAction(id: "stop", title: String(localized: "Stop watching"))],
                                           refKind: "watcher", refId: "w1"))),
            ("agent-needs-you", needsYou),
            ("job-failed", moment(AttentionItem(level: .attention, source: "job", title: "npm test failed in pockito (exit 1)",
                                                body: "billing › team needs three seats\nExpected 36, received 24",
                                                actions: [AttentionAction(id: "copy", title: String(localized: "Copy command"), isPrimary: true),
                                                          AttentionAction(id: "open", title: String(localized: "Open folder"))],
                                                refKind: "job", refId: "j1"))),
            ("question", moment(AttentionItem(level: .attention, source: "external:codex", title: "Deploy to staging now?",
                                              actions: [AttentionAction(id: "yes", title: "Yes", isPrimary: true), AttentionAction(id: "no", title: "No")],
                                              refKind: "ask"))),
            ("brief", moment(AttentionItem(level: .gentle, source: "brief", title: "Good morning · 2 reminders today",
                                           body: "10:00 Team standup\n13:00 Lunch with Priya\n16:30 Design review\n17:00 Stretch and refill water\n3 open tasks · 3 watchers on duty",
                                           actions: [AttentionAction(id: "open", title: String(localized: "Open"), isPrimary: true)], refKind: "brief"))),
            ("digest", moment(AttentionItem(level: .attention, source: "summary",
                                            title: String(localized: "While you were focused: \(4) things",
                                                          comment: "One card after Focus ends: what waited during it"),
                                            body: "• Codex asks: deploy to staging now?\n• staging.sidefolk.app is down\n• Stretch and refill water\n• npm test passed in pockito",
                                            actions: [AttentionAction(id: "open", title: String(localized: "Show"), isPrimary: true)], refKind: "focus"))),
            ("intro", moment(AttentionItem(level: .gentle, source: AppCoordinator.ownVoice, title: AppCoordinator.introduction(.scout).0,
                                           body: AppCoordinator.introduction(.scout).1, refKind: "intro"))),
            ("welcome", moment(Onboarding.item(for: .hello, name: "Mochi", hotkey: "⇧⌘Space"))),
            ("update", moment({
                let n = UpdateController.notice(UpdateController.sampleOffer)
                return AttentionItem(level: n.level, source: n.source, title: n.title, body: n.body, actions: n.actions, refKind: n.refKind, refId: n.refId)
            }())),
            ("stack", stack),
        ] + keyed(reminder: moment, needsYou: needsYou, stack: stack)
    }

    /// The card shortcut's moments (D84): a calm reminder with the keyboard on its main answer, the second of three held
    /// cards; a firm card that only ⌘↩ answers; the held cards fanned from the keyboard with one chosen.
    private static func keyed(reminder moment: (AttentionItem, SidecardModel.Shape, CGFloat?) -> SidecardModel, needsYou: SidecardModel,
                              stack: SidecardModel) -> [(String, SidecardModel)] {
        let actions = ReminderScheduler.ActionID.self
        let item = AttentionItem(level: .attention, source: "reminder", title: "Stretch and refill water",
                                 body: "It's 17:00. Next one at 19:00, the last at 21:00.",
                                 actions: [AttentionAction(id: actions.done, title: String(localized: "Done"), isPrimary: true),
                                           AttentionAction(id: actions.snooze10, title: String(localized: "In 10 min", comment: "A reminder card's snooze button: remind again in ten minutes")),
                                           AttentionAction(id: actions.stop, title: String(localized: "Stop repeating"))],
                                 refKind: "reminder", refId: "r1")
        let calm = moment(item, .card, 0.78)
        calm.keys = CardKeys(answers: [SidecardController.moreAnswers, actions.snooze10, actions.done], main: actions.done, takesReturn: true,
                             deck: ["a", item.id, "c"], current: item.id)
        let firm = SidecardModel()
        firm.item = needsYou.item
        firm.sessions = needsYou.sessions
        firm.shape = .card
        firm.tailAt = 0.78
        firm.companionName = "Mochi"
        firm.keys = CardKeys(answers: ["dismiss", "open"], main: "open", takesReturn: false)
        let fanned = SidecardModel()
        fanned.shape = .stack
        fanned.tailAt = nil
        fanned.waiting = stack.stack.count
        fanned.stack = stack.stack
        fanned.stackFocus = stack.stack[1].id
        return [("keys-calm", calm), ("keys-firm", firm), ("keys-stack", fanned)]
    }

    // MARK: Permission slips

    /// Each slip, and whether its exact request shows unfolded.
    static func slips() -> [(String, ApprovalRequest, Bool)] {
        let home = NSHomeDirectory()
        var move = ApprovalRequest(tool: "files.move", title: "Move 12 PDFs from Downloads to Documents › Invoices",
                                   summary: "invoice-acme-2026-10.pdf and 11 more", risk: .medium, caller: .agent(runId: "r"),
                                   details: .paths((1...12).map { "\(home)/Downloads/invoice-\($0).pdf" }), canAlways: true, effect: .changesFiles)
        move.expiresAt = now.addingTimeInterval(15 * 60)
        var clipboard = ApprovalRequest(tool: "clipboard.read", title: "Read what you copied last", summary: "Read the clipboard", risk: .medium,
                                        caller: .external(client: "codex"), details: .none, canAlways: false, tainted: true, effect: .readsPrivateData)
        clipboard.expiresAt = now.addingTimeInterval(15 * 60)
        clipboard.input = "Read the clipboard\nasked by Codex · session in ~/git/pockito\ngets the last text you copied (212 characters)"
        var share = ApprovalRequest(tool: "ext.cast-along.share_screen", title: "Share your screen to the living room TV",
                                    summary: "Until you stop it", risk: .medium, caller: .agent(runId: "r"), details: .none, canAlways: false,
                                    tainted: true, effect: .usesInternet, extensionId: SampleAddons.castAlong)
        share.taintedBy = .web
        share.expiresAt = now.addingTimeInterval(20 * 60)
        let remove = ApprovalRequest(tool: "applenotes.remove", title: "Remove 2 notes from Apple Notes",
                                     summary: "Move 2 notes in Apple Notes to Recently Deleted", risk: .high, caller: .user,
                                     details: .text("“Pasta carbonara” (iCloud › Recipes)\n“Sourdough” (iCloud › Recipes)"), canAlways: false,
                                     effect: .changesThings)
        var folder = ApprovalRequest(tool: "files.move", title: "Let Mochi work in ~/Downloads?", summary: "Move 12 PDFs from Downloads to Documents › Invoices",
                                     risk: .medium, caller: .agent(runId: "r"), details: .folderAccess(folder: "\(home)/Downloads", write: true), canAlways: true,
                                     effect: .changesFiles)
        folder.expiresAt = now.addingTimeInterval(15 * 60)
        return [("calm", move, false), ("firm-app", clipboard, false), ("firm-app-exact", clipboard, true), ("firm-outside", share, false),
                ("high-risk", remove, false), ("folder", folder, false)]
    }

    // MARK: The companion on its floor

    struct Floor {
        var light: LightPoolState = .idle
        var count = 0
        var folks: [String] = []
        var pins: [Readout] = []
        var agents: [AgentChip] = []
        var sidecard: SidecardModel?
        /// The short card the pointer brings up on an extra.
        var tip: FloorTip.Content?
        /// The person works under the corner: the extras step back.
        var receded = false
        /// The microphone listens: the light follows the voice (D84).
        var voiceLevel: Double?
    }

    static var pins: [Readout] {
        [Readout(id: "cpu", label: String(localized: "CPU"), value: "23%", atRest: PinValue.atRest("23%"), symbol: "cpu", spark: [14, 22, 18, 25, 21, 30, 24, 23], at: now, interval: 10),
         Readout(id: "w", label: "Fukuoka", value: "18.4 °C", atRest: PinValue.atRest("18.4 °C"), symbol: "cloud.sun", spark: [18.9, 18.8, 18.6, 18.5, 18.4], at: now, interval: 60),
         Readout(id: "net", label: String(localized: "Network"), value: "↓ 1.2 MB/s", atRest: PinValue.atRest("↓ 1.2 MB/s"), symbol: "network", paused: true, at: now, interval: 10),
         Readout(id: "old", label: "Pro plan", value: "$15", atRest: PinValue.atRest("$15"), symbol: "globe", at: now.addingTimeInterval(-2 * 3600), interval: 300)]
    }

    static var agents: [AgentChip] {
        [AgentChip(id: "cc", agent: "Claude Code", project: "sidefolk", needsYou: true, since: now.addingTimeInterval(-1500)),
         AgentChip(id: "cx", agent: "Codex", project: "pockito", needsYou: false, since: now.addingTimeInterval(-840))]
    }

    /// One board of every state, as the mockup's B1 board (b01-states): the light says it before a word is read.
    static func statesBoard(portrait: NSImage) -> some View {
        // The board's own labels stay English: it is a review sheet, not something people read in the app.
        let cells: [(String, LightPoolState, Int, [String])] = [
            ("Idle", .idle, 0, []), ("Working", .working, 0, ["byte"]), ("Waiting on you", .waiting(3), 3, []),
            ("Alert", .alert, 1, []), ("Something failed", .failed, 0, []), ("Focus", .focus, 2, []), ("Quiet", .quiet, 0, []),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.l), count: 3), spacing: Theme.Space.l) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: cell.0).font(Theme.Font.headline).foregroundStyle(Theme.ink).padding(Theme.Space.l)
                    FloorScene(portrait: portrait, floor: Floor(light: cell.1, count: cell.2, folks: cell.3), height: 220)
                }
                .background(Wallpaper())
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
        }
        .padding(Theme.Space.xl)
        .background(Theme.surfaceSunken)
    }

    static func scenes(portrait: NSImage, face: NSImage) -> [(String, Floor, Bool)] {
        let sidecards = Dictionary(uniqueKeysWithValues: Self.sidecards(face: face))
        let busy = Floor(folks: ["tempo", "scout", "byte"], pins: Array(pins.prefix(2)), agents: agents)
        var hoverPin = busy
        hoverPin.tip = .pin(pins[0])
        var hoverAgent = busy
        hoverAgent.tip = .agent(agents[0])
        var receded = busy
        receded.receded = true
        return [
            // The founder's busy day, measured: two agents, two pins, three folks, in the corner it had before D84.
            ("busy", busy, true),
            ("busy-hover-pin", hoverPin, true),
            ("busy-hover-agent", hoverAgent, true),
            ("busy-receded", receded, true),
            ("reminder", Floor(light: .alert, count: 1, folks: ["tempo"], pins: Array(pins.prefix(1)), sidecard: sidecards["reminder"]), false),
            ("whisper", Floor(light: .working, folks: ["byte"], agents: [agents[1]], sidecard: sidecards["whisper"]), false),
            ("agents", Floor(light: .alert, count: 1, folks: ["byte", "scout"], agents: agents, sidecard: sidecards["agent-needs-you"]), false),
            ("stack", Floor(light: .waiting(12), folks: ["scout"], sidecard: sidecards["stack"]), false),
            ("focus", Floor(light: .focus, count: 2, folks: ["scout"], pins: Array(pins.prefix(1))), false),
            ("quiet", Floor(light: .quiet, folks: ["scout"], pins: Array(pins.prefix(1))), false),
            // Talking (D84): a soft voice and a raised one.
            ("listening-soft", Floor(light: .working, voiceLevel: 0.25), false),
            ("listening-loud", Floor(light: .working, voiceLevel: 1), false),
        ]
    }
}

/// A soft wallpaper like the mockups' (a light aqua and lilac wash, a deep blue at night), so glass reads as glass.
struct Wallpaper: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(colors: scheme == .dark ? [Color(hex: 0x1B2540), Color(hex: 0x10283A), Color(hex: 0x21203A)]
                                               : [Color(hex: 0xD8E6F6), Color(hex: 0xDDEFEE), Color(hex: 0xE7E2F2)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The companion at the bottom of a wallpaper, at its real size (medium, in 3D) with its real corner: the pool under
/// its feet, the mark on its shoulder, its folks, the extras above them, an optional tip, and the Sidecard above its
/// head. `measure` outlines the corner it takes (its window) and says how big it is.
struct FloorScene: View {
    var portrait: NSImage
    var floor: DesktopScenes.Floor
    var height: CGFloat = 420
    var measure = false
    /// As the window lays them out (CompanionWindowController): medium is 76 pt, a 3D box is 1.3 × that over 0.62.
    static let box: CGFloat = (76 / 0.62 * 1.3).rounded()
    static var folk: CGFloat { (76 * 0.62).rounded() }
    static var feet: CGFloat { box * 0.1 }
    static var reach: CGFloat { box * 0.17 }
    static var body: CGFloat { box * 0.62 }

    var body: some View {
        let extras = floor.pins.isEmpty && floor.agents.isEmpty ? .zero
            : NSHostingView(rootView: FloorExtras(pins: floor.pins, agents: floor.agents)).fittingSize
        let area = CompanionWindowController.area(box: Self.box, folk: Self.folk, extras: extras)
        let bodyInset = (Self.box - Self.body) / 2
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            ZStack(alignment: .bottomTrailing) {
                if measure {
                    Rectangle().strokeBorder(Theme.inkFaint, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(width: area.width, height: area.height)
                        .overlay(alignment: .topLeading) {
                            Text(verbatim: "\(Int(area.width)) × \(Int(area.height)) pt").font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
                                .padding(4)
                        }
                }
                LightPool(state: floor.light, width: min(max(Self.body * 1.9, 90), 240), level: floor.voiceLevel)
                    .offset(x: -(Self.box / 2) + min(max(Self.body * 1.9, 90), 240) / 2, y: min(max(Self.body * 1.9, 90), 240) * 0.14 - Self.feet - 2)
                    .frame(width: Self.box, alignment: .center)
                Image(nsImage: portrait).resizable().scaledToFit().frame(width: Self.box * 0.92, height: Self.box * 0.92)
                    .frame(width: Self.box, height: Self.box)
                    .overlay(alignment: .topTrailing) {
                        ShoulderBadge(state: floor.light, count: floor.count).offset(x: -bodyInset - Self.body * 0.1 + 14, y: bodyInset + 4)
                    }
                HStack(alignment: .bottom, spacing: Self.folk * 0.8 - Self.folk) {
                    ForEach(floor.folks, id: \.self) { folk in
                        FolkArt.image(folk, size: Self.folk).map { Image(nsImage: $0).resizable().frame(width: Self.folk, height: Self.folk) }
                    }
                }
                .padding(.trailing, Self.box - bodyInset + Self.reach - Self.folk * 0.15)
                .padding(.bottom, Self.feet - Self.folk * 0.1)
                VStack(alignment: .trailing, spacing: 0) {
                    if let tip = floor.tip { FloorTip(content: tip).padding(.bottom, -14) }
                    FloorExtras(pins: floor.pins, agents: floor.agents, alignment: .trailing)
                        .opacity(floor.receded ? 0.28 : 1)
                        .scaleEffect(floor.receded ? 0.86 : 1, anchor: .bottomTrailing)
                }
                .padding(.trailing, Self.box - bodyInset + Self.reach * 0.4)
                .padding(.bottom, Self.feet + Self.folk * 0.95)
            }
            .overlay(alignment: .bottomTrailing) {
                if let sidecard = floor.sidecard {
                    SidecardView(model: sidecard).fixedSize().offset(x: SidecardView.margin.trailing + 30, y: -Self.box + 14)
                }
            }
            .padding(.trailing, Theme.Space.xxl)
            .padding(.bottom, Theme.Space.l)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(Wallpaper())
    }
}
#endif
