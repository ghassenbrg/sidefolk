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
            AttentionItem(level: .attention, source: "external:codex", title: "Codex asks: deploy to staging?", refKind: "ask", now: now.addingTimeInterval(-60)),
        ]
        return [
            ("whisper", moment(AttentionItem(level: .gentle, source: "external:claude-code", title: "Claude Code saved a note to Ideas",
                                             actions: [AttentionAction(id: SidecardItemCard.undo, title: String(localized: "Undo"))], refKind: "credit"),
                               .whisper)),
            ("whisper-paused", paused),
            ("whisper-own", moment(AttentionItem(level: .gentle, source: AppCoordinator.ownVoice,
                                                 title: String(localized: "All clear. Nothing waits for you.", comment: "A whisper when the last held card was answered"),
                                                 refKind: "clear"), .whisper, tail: 0.5)),
            ("reminder", moment(AttentionItem(level: .attention, source: "reminder", title: "Stretch and refill water",
                                              body: "It's 17:00. Next one at 19:00, the last at 21:00.",
                                              actions: [AttentionAction(id: actions.done, title: String(localized: "Done"), isPrimary: true),
                                                        AttentionAction(id: actions.snooze10, title: String(localized: "10 min")),
                                                        AttentionAction(id: actions.stop, title: String(localized: "Stop repeating"))],
                                              refKind: "reminder", refId: "r1"))),
            ("reminder-task", moment(AttentionItem(level: .attention, source: "reminder", title: "Write the onboarding email",
                                                   body: "From your note “Pockito launch plan”.",
                                                   actions: [AttentionAction(id: actions.taskDone, title: String(localized: "Mark done"), isPrimary: true),
                                                             AttentionAction(id: actions.snooze10, title: String(localized: "10 min")),
                                                             AttentionAction(id: actions.open, title: String(localized: "Open"))],
                                                   refKind: "reminder", refId: "r2"))),
            ("watch", moment(AttentionItem(level: .attention, source: "watcher", title: "Pricing changed",
                                           body: "example.com/pricing: Pro went from $12 to $15.",
                                           actions: [AttentionAction(id: "open", title: String(localized: "Open"), isPrimary: true),
                                                     AttentionAction(id: "stop", title: String(localized: "Stop watching"))],
                                           refKind: "watcher", refId: "w1"))),
            ("agent-needs-you", moment(AttentionItem(level: .attention, source: "session:cc-1", title: "Claude needs you in sidefolk",
                                                     body: "Asks to use Bash: git push origin main",
                                                     actions: [AttentionAction(id: "open", title: String(localized: "Open"), isPrimary: true),
                                                               AttentionAction(id: "dismiss", title: String(localized: "Dismiss"))],
                                                     refKind: "session", refId: "cc-1"))),
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
                                            title: String(localized: "While Quiet was on: \(4) things", comment: "A card when quiet mode ends"),
                                            body: "• Codex asks: deploy to staging now?\n• staging.sidefolk.app is down\n• Stretch and refill water\n• npm test passed in pockito",
                                            actions: [AttentionAction(id: "open", title: String(localized: "Show"), isPrimary: true)], refKind: "digest"))),
            ("intro", moment(AttentionItem(level: .gentle, source: AppCoordinator.ownVoice, title: AppCoordinator.introduction(.scout).0,
                                           body: AppCoordinator.introduction(.scout).1, refKind: "intro"))),
            ("welcome", moment(Onboarding.item(for: .hello, name: "Mochi", hotkey: "⇧⌘Space"))),
            ("update", moment({
                let n = UpdateController.notice(UpdateController.sampleOffer)
                return AttentionItem(level: n.level, source: n.source, title: n.title, body: n.body, actions: n.actions, refKind: n.refKind, refId: n.refId)
            }())),
            ("stack", stack),
        ]
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
        var share = ApprovalRequest(tool: "ext.miraya.share_screen", title: "Share your screen to the living room TV",
                                    summary: "Until you stop it", risk: .medium, caller: .agent(runId: "r"), details: .none, canAlways: false,
                                    tainted: true, effect: .usesInternet, extensionId: "dev.sidefolk.miraya")
        share.taintedBy = .web
        share.expiresAt = now.addingTimeInterval(20 * 60)
        let remove = ApprovalRequest(tool: "applenotes.remove", title: "Remove 2 notes from Apple Notes",
                                     summary: "Move 2 notes in Apple Notes to Recently Deleted", risk: .high, caller: .user,
                                     details: .text("“Pasta carbonara” (iCloud › Recipes)\n“Sourdough” (iCloud › Recipes)"), canAlways: false,
                                     effect: .changesThings)
        return [("calm", move, false), ("firm-app", clipboard, false), ("firm-app-exact", clipboard, true), ("firm-outside", share, false),
                ("high-risk", remove, false)]
    }

    // MARK: The companion on its floor

    struct Floor {
        var light: LightPoolState = .idle
        var count = 0
        var folks: [String] = []
        var pins: [Readout] = []
        var agents: [AgentChip] = []
        var sidecard: SidecardModel?
    }

    static var pins: [Readout] {
        [Readout(id: "cpu", label: String(localized: "CPU"), value: "23%", symbol: "cpu", spark: [14, 22, 18, 25, 21, 30, 24, 23], at: now, interval: 10),
         Readout(id: "w", label: "Fukuoka", value: "18.4 °C", symbol: "cloud.sun", spark: [18.9, 18.8, 18.6, 18.5, 18.4], at: now, interval: 60),
         Readout(id: "net", label: String(localized: "Network"), value: "↓ 1.2 MB/s", symbol: "network", paused: true, at: now, interval: 10),
         Readout(id: "old", label: "Pro plan", value: "$15", symbol: "globe", at: now.addingTimeInterval(-2 * 3600), interval: 300)]
    }

    static var agents: [AgentChip] {
        [AgentChip(id: "cc", agent: "Claude Code", project: "sidefolk", needsYou: true, since: now.addingTimeInterval(-1500)),
         AgentChip(id: "cx", agent: "Codex", project: "pockito", needsYou: false, since: now.addingTimeInterval(-840))]
    }

    /// One board of every state, as the mockup's B1 board (b01-states): the light says it before a word is read.
    static func statesBoard(portrait: NSImage) -> some View {
        let cells: [(LocalizedStringKey, LightPoolState, Int, [String])] = [
            ("Idle", .idle, 0, []), ("Working", .working, 0, ["byte"]), ("Waiting on you", .waiting(3), 3, []),
            ("Alert", .alert, 1, []), ("Something failed", .failed, 0, []), ("Quiet", .quiet, 0, []),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.l), count: 3), spacing: Theme.Space.l) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                VStack(alignment: .leading, spacing: 0) {
                    Text(cell.0).font(Theme.Font.headline).foregroundStyle(Theme.ink).padding(Theme.Space.l)
                    FloorScene(portrait: portrait, floor: Floor(light: cell.1, count: cell.2, folks: cell.3), height: 220)
                }
                .background(Wallpaper())
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
        }
        .padding(Theme.Space.xl)
        .background(Theme.surfaceSunken)
    }

    static func scenes(portrait: NSImage, face: NSImage) -> [(String, Floor)] {
        let sidecards = Dictionary(uniqueKeysWithValues: Self.sidecards(face: face))
        return [
            ("rest", Floor(folks: ["scout", "byte"], pins: Array(pins.prefix(2)), agents: [agents[1]])),
            ("reminder", Floor(light: .alert, count: 1, folks: ["tempo"], pins: Array(pins.prefix(2)), sidecard: sidecards["reminder"])),
            ("whisper", Floor(light: .working, folks: ["byte"], sidecard: sidecards["whisper"])),
            ("agents", Floor(light: .alert, count: 1, folks: ["byte", "scout"], agents: agents, sidecard: sidecards["agent-needs-you"])),
            ("stack", Floor(light: .waiting(12), folks: ["scout"], sidecard: sidecards["stack"])),
            ("pins", Floor(folks: ["scout", "byte"], pins: pins, agents: [agents[1]])),
            ("quiet", Floor(light: .quiet, folks: ["scout"])),
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

/// The companion at the bottom of a wallpaper with what stands around it: the pool under its feet, the mark on its
/// shoulder, its folks, the pins above them, the agents lane beyond them, and the Sidecard above its head.
struct FloorScene: View {
    var portrait: NSImage
    var floor: DesktopScenes.Floor
    var height: CGFloat = 520
    var body: some View {
        let side = min(150, height * 0.62)
        VStack(alignment: .trailing, spacing: 0) {
            Spacer(minLength: 0)
            if let sidecard = floor.sidecard {
                SidecardView(model: sidecard)
                    .padding(.trailing, max(0, side / 2 - 150))
            }
            HStack(alignment: .bottom, spacing: Theme.Space.s) {
                Spacer(minLength: 0)
                if !floor.agents.isEmpty { AgentsColumn(chips: floor.agents, alignment: .trailing).padding(.bottom, 6) }
                VStack(alignment: .trailing, spacing: Theme.Space.m) {
                    if !floor.pins.isEmpty { PinsColumn(pins: floor.pins, alignment: .trailing) }
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(floor.folks, id: \.self) { folk in
                            FolkArt.image(folk, size: side * 0.5).map { Image(nsImage: $0).resizable().frame(width: side * 0.5, height: side * 0.5) }
                        }
                    }
                }
                ZStack(alignment: .bottom) {
                    LightPool(state: floor.light, width: side * 1.3).offset(y: side * 0.1)
                    Image(nsImage: portrait).resizable().scaledToFit().frame(width: side, height: side)
                        .opacity(floor.light == .quiet ? 0.92 : 1)
                }
                .overlay(alignment: .topTrailing) { ShoulderBadge(state: floor.light, count: floor.count).offset(x: -side * 0.12, y: side * 0.08) }
                .padding(.trailing, Theme.Space.l)
            }
        }
        .padding(.bottom, Theme.Space.m)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(Wallpaper())
    }
}
#endif
