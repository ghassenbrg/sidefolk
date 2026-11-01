import AppKit
import SidefolkCharacter
import SidefolkCore

/// The menu bar's Pocket (D84): what it shows, gathered from the stores each time it opens, what its buttons do, and the
/// mark on the icon that says the state at a glance.
extension AppCoordinator {
    func installPocket() {
        let menuBarImage = BrandAsset.menuBar.image ?? NSImage(
            cgImage: CharacterRenderer.menuBarTemplate(size: CGSize(width: 18, height: 18), scale: 2),
            size: NSSize(width: 18, height: 18))
        statusItem.install(image: menuBarImage)
        statusItem.palettes = { [weak self] in self?.palettes.current ?? [] }
        statusItem.contentProvider = { [weak self] in await self?.pocketContent() ?? PocketContent() }
        statusItem.actions = PocketActions(
            ask: { [weak self] text in
                guard let self else { return }
                statusItem.closePocket()
                showAsk(prefill: text)
                ask.submit()
            },
            setAttention: { [weak self] mode, until in
                self?.setAttention(mode, until: until)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    self?.statusItem.refresh()
                }
            },
            turnOffFullAccess: { [weak self] in
                guard let self else { return }
                Task {
                    let before = (try? await self.runtime.permissions.policy())?.beforeFullAccess ?? .askOncePerKind
                    self.setMode(before)
                }
            },
            showCompanion: { [weak self] in
                self?.showCompanion(true)
                self?.statusItem.refresh()
            },
            update: { [weak self] in
                guard let self else { return }
                statusItem.closePocket()
                if updater.model.readyOffer != nil { updater.restartNow() } else { updater.showUpdates() }
            },
            openHome: { [weak self] in self?.pocketClosing { $0.openHome() } },
            openToday: { [weak self] in self?.pocketClosing { $0.openNow() } },
            openSettings: { [weak self] in self?.pocketClosing { $0.openSettings() } },
            openAttentionSettings: { [weak self] in self?.pocketClosing { $0.openSettings(tab: .attention) } },
            toggleCompanion: { [weak self] in
                guard let self else { return }
                showCompanion(!companion.isVisible)
                statusItem.refresh()
            },
            checkForUpdates: { [weak self] in self?.pocketClosing { $0.updater.showUpdates() } },
            about: { [weak self] in self?.pocketClosing { $0.showAbout() } },
            openPalette: { [weak self] id in
                self?.statusItem.closePocket()
                Task { await self?.palettes.toggle(id) }
            },
            quit: { NSApp.terminate(nil) })
        statusItem.setCompanionHidden(!companion.isVisible)
    }

    private func pocketClosing(_ action: (AppCoordinator) -> Void) {
        statusItem.closePocket()
        action(self)
    }

    /// The mark on the menu bar icon: Quiet and Focus first (they say why nothing pops up), then something waiting.
    func refreshMark() {
        let mode = runtime.settings.current.attentionMode(at: Date())
        statusItem.setMark(mode == .quiet ? .quiet : mode == .focus ? .focus : backlog > 0 ? .waiting : .idle)
    }

    /// Everything the Pocket shows, from what Sidefolk keeps.
    func pocketContent() async -> PocketContent {
        let now = Date()
        let s = runtime.settings.current
        var c = PocketContent()
        c.name = s.companionName
        c.avatar = CompanionArt.avatar(for: s, side: 72)
        c.attention = s.attentionMode(at: now)
        c.attentionEnds = s.attentionEnds(at: now)
        c.quietHours = s.quietHours.on ? s.quietHours : nil
        c.spans = AttentionSpan.choices(settings: s, now: now)
        c.held = await runtime.attention.heldCount
        let policy = (try? await runtime.permissions.policy()) ?? GuardPolicy()
        c.fullAccess = policy.mode == .fullAccess
        c.fullAccessEnds = policy.fullAccessEnds
        c.update = updater.waitingVersion
        c.updateReady = updater.model.readyOffer != nil
        c.companionVisible = companion.isVisible
        c.hotkey = hotkeyLabel

        // Needs you: agents' sessions asking, cards waiting, steps skipped while nobody answered.
        let sessions = (try? await runtime.sessions.live()) ?? []
        for session in sessions where session.state == .needsYou {
            c.needsYou.append(.init(id: "session-\(session.id)", title: String(localized: "\(Self.agentName(session.agent)) needs you"),
                                    detail: [session.projectName, session.detail].compactMap { $0 }.joined(separator: " · "),
                                    trailing: TimeText.clock(session.updatedAt), symbol: "hand.raised", folk: "byte",
                                    open: { [weak self] in self?.pocketClosing { $0.openSession(session) } }))
        }
        for item in await runtime.attention.open().filter({ $0.level >= .attention }) {
            c.needsYou.append(.init(id: "attention-\(item.id)", title: item.title, detail: item.body?.clipped(60),
                                    trailing: TimeText.clock(item.createdAt), symbol: "tray.full", folk: Self.folk(for: item.refKind == "watcher" ? "watcher" : item.source),
                                    open: { [weak self] in self?.pocketClosing { $0.openNow() } }))
        }
        // Add-on updates (D89): one row, however many.
        let pending = updates.addonPending
        if !pending.isEmpty {
            c.needsYou.append(.init(id: "addon-updates", title: AddonUpdateWords.count(pending.count),
                                    detail: Wording.list(pending.map(\.shownName)).clipped(60), symbol: "arrow.down.circle",
                                    open: { [weak self] in self?.pocketClosing { $0.addonUpdater.showAddonUpdates() } }))
        }
        let skipped = await runtime.executor.skipped.list()
        if let newest = skipped.first {
            c.needsYou.append(.init(id: "skipped", title: String(localized: "Skipped while you were away (\(skipped.count))"),
                                    detail: newest.request.summary.clipped(60), trailing: TimeText.clock(newest.skippedAt),
                                    symbol: "clock.badge.xmark", folk: "guard",
                                    open: { [weak self] in self?.pocketClosing { $0.openNow() } }))
        }

        // Next up: reminders in the next twelve hours.
        for r in ((try? await runtime.reminderStore.pending()) ?? []).prefix(4) {
            guard let due = r.nextDue, due.timeIntervalSince(now) < 12 * 3600 else { continue }
            c.nextUp.append(.init(id: "reminder-\(r.id)", title: r.title.clipped(60), detail: nil,
                                  trailing: TimeFormat.when(due, now: now, calendar: .autoupdatingCurrent),
                                  symbol: "alarm", folk: "tempo",
                                  open: { [weak self] in self?.pocketClosing { $0.openNow() } }))
        }

        // Agents at work: sessions working, commands running.
        for session in sessions where session.state == .working {
            c.agents.append(.init(id: "working-\(session.id)",
                                  title: session.projectName.map { String(localized: "\(Self.agentName(session.agent)) in \($0)", comment: "The Pocket: “Codex in pockito”") }
                                      ?? Self.agentName(session.agent),
                                  detail: session.detail, trailing: TimeText.duration(now.timeIntervalSince(session.startedAt)),
                                  symbol: "terminal", folk: "byte", live: true,
                                  open: { [weak self] in self?.pocketClosing { $0.openSession(session) } }))
        }
        for job in ((try? await runtime.jobs.running()) ?? []).prefix(2) {
            c.agents.append(.init(id: "job-\(job.id)", title: job.title.clipped(60), detail: nil,
                                  trailing: TimeText.duration(now.timeIntervalSince(job.startedAt)), symbol: "terminal", live: true,
                                  open: { [weak self] in self?.pocketClosing { $0.openNow() } }))
        }
        c.watching = ((try? await runtime.watcherStore.active()) ?? []).count
        return c
    }

    static func agentName(_ agent: String) -> String { agent == "codex" ? "Codex" : "Claude Code" }

    /// The folk whose domain a card's source is (D30): Tempo for reminders, Scout for watches, Byte for agents.
    static func folk(for source: String) -> String? {
        if source == "reminder" { return "tempo" }
        if source == "watcher" { return "scout" }
        if source.hasPrefix("external:") || source.hasPrefix("session:") { return "byte" }
        return nil
    }
}
