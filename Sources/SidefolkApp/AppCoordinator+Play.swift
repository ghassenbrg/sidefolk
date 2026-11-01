import AppKit
import SidefolkCore

/// Games in the Play panel beside the companion (D75): opening one (from words, the Play menu, Home or the AI, all
/// through `games.open`), playing its cues, one Activity row when it ends, and the coin and dice's Again pill.
extension AppCoordinator {
    func makePlayPanel() -> PlayPanelController {
        let panel = PlayPanelController()
        panel.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            self.companion.keepRaised(visible)
            if !visible { self.cues.reset() }
        }
        panel.onExpired = { [weak self] model in self?.finish(model, reason: .timeout) }
        panel.onSpeaker = { [weak self] in self?.toggleGameSounds() }
        return panel
    }

    func makeCueDirector() -> CueDirector {
        let cues = CueDirector(companion: companion, caption: player.caption)
        cues.panelFrame = { [weak self] in self?.playPanel.isVisible == true ? self?.playPanel.frame : nil }
        cues.restoreMood = { [weak self] in self?.renderMood() }
        cues.soundsAllowed = { [weak self] in
            guard let self else { return false }
            let s = self.runtime.settings.current
            let full = NSWorkspace.shared.frontmostApplication.map { Fullscreen.isFrontmostFullscreen(pid: $0.processIdentifier) } ?? false
            return !s.isQuiet(at: Date()) && !full
        }
        // Lines are said aloud only for someone who hears every reply (Settings › Voice), with the game's sound on.
        cues.speak = { [weak self] line in
            guard let self, let model = self.playPanel.model, model.soundsOn else { return }
            let voice = self.runtime.settings.current.voice
            guard voice.replies == .always else { return }
            self.voice.say(line, with: voice)
        }
        return cues
    }

    /// Opens a game, or brings back the one kept if it is the same.
    func openGame(_ request: GameRequest) {
        askPanel.hide()
        if !companion.isVisible { showCompanion(true) }
        tossRevealed = false
        guard let (frame, screen) = anchor() else { return }
        if let kept = playPanel.kept(request.info) {
            playPanel.show(kept, beside: frame, on: screen, focus: request.focus)
            return
        }
        if let previous = playPanel.model { finish(previous, reason: .closed) }
        let s = runtime.settings.current
        let provider: any GameProvider = request.info.isSidefolk
            ? HandsMatch(db: runtime.db, companionName: s.companionName)
            : ExtensionGame(info: request.info, host: runtime.extensions)
        let model = PlayModel(info: request.info, provider: provider, companionName: s.companionName,
                              portrait: CompanionArt.avatar(for: s, side: 40), soundsOn: s.games.soundsOn(request.info.id))
        // The person's own companion in the scene, in the pose of the moment where its look has poses.
        model.figure = { state in CompanionArt.portrait(for: s, state: state, side: 220) }
        model.you = GameFigures.accountPicture
        model.onBack = { [weak self] in self?.openPlayMenu(focus: true) }
        // Cues act only while the panel shows this game.
        func showing(_ model: PlayModel?) -> Bool { playPanel.shows(model) }
        model.onCue = { [weak self, weak model] board in
            guard let self, let model, showing(model) else { return }
            self.cues.play(board, tone: self.runtime.settings.current.games.tone, sounds: model.soundsOn)
        }
        model.onReveal = { [weak self, weak model] reveal in
            guard let self, let model, showing(model) else { return }
            self.cues.reveal(reveal, sounds: model.soundsOn)
        }
        model.onPadStep = { [weak self, weak model] pad in
            guard let self, let model, showing(model) else { return }
            self.cues.padStep(pad)
        }
        model.onBeat = { [weak self, weak model] in
            guard let self, let model, showing(model) else { return }
            self.cues.beat(sounds: model.soundsOn)
        }
        model.onOver = { [weak self, weak model] board in
            guard let self, let model else { return }
            self.record(model, board: board)
        }
        model.onClose = { [weak self] in self?.playPanel.hide() }
        playPanel.show(model, beside: frame, on: screen, focus: request.focus)
        // The companion's name lets a game word its buttons ("Ask Mochi"); nothing else about the person is passed.
        let options: [String: JSONValue] = ["tone": .string(s.games.tone.rawValue), "sneaky": .bool(s.games.sneaky),
                                            "companion": .string(s.companionName)]
        Task { await model.start(GameSetup(level: request.level, language: AppLanguage.current, options: options)) }
    }

    /// The Play panel's menu of games (its home): every game with its look, the person's stats from Activity, and the
    /// game put away, to resume. The one way to open it: the Play menu, a game's back button, "show me the games" and
    /// `games.open` without a game (`.gamesMenu`), Ask's Play tab and the Pocket all call this. A game opens from it as
    /// the person's own choice, through the tool like every way in.
    func openPlayMenu(focus: Bool) {
        askPanel.hide()
        if !companion.isVisible { showCompanion(true) }
        guard let (frame, screen) = anchor() else { return }
        cues.reset()
        let s = runtime.settings.current
        let games = [GameInfo.handsMatch] + runtime.extensions.gameShelf.all
        let kept = playPanel.model.flatMap { playPanel.kept($0.info) }?.info
        let menu = PlayMenuModel(games: games, stats: GameStats(), companionName: s.companionName,
                                 portrait: CompanionArt.avatar(for: s, side: 40),
                                 figure: CompanionArt.portrait(for: s, state: .listening, side: 220), kept: kept)
        menu.onOpen = { [weak self] info in self?.openGameFromMenu(info) }
        menu.onClose = { [weak self] in self?.playPanel.hide() }
        playPanel.showMenu(menu, beside: frame, on: screen, focus: focus)
        let activity = runtime.activity
        Task { @MainActor in
            if let rows = try? await activity.recent(limit: 1000, tool: "games.play") { menu.stats = GameStats(rows) }
        }
    }

    /// From the Play menu: the person's own choice, through the tool like every way in.
    func openGameFromMenu(_ info: GameInfo) {
        Task { _ = await runtime.executor.execute(name: "games.open", input: ["extension": .string(info.extensionId), "game": .string(info.game)],
                                                  caller: .user) }
    }

    /// The game ends for good: the game hears why, and a game that was played and never said it was over still gets its row.
    func finish(_ model: PlayModel, reason: GameEndReason) {
        model.stop()
        if model.played, !model.recorded { record(model, board: model.latest) }
        if playPanel.model === model {
            playPanel.hide()
            playPanel.drop()
        }
        Task { await model.provider.end(reason) }
    }

    private func record(_ model: PlayModel, board: GameBoard?) {
        let entry = GameRecord.entry(model.info, last: board, companionName: runtime.settings.current.companionName, at: Date())
        let activity = runtime.activity, events = runtime.events
        Task {
            _ = try? await activity.log(entry)
            events.changed(.activity)
        }
    }

    /// The speaker in the panel's header: this game's sounds on or off, remembered.
    func toggleGameSounds() {
        guard let model = playPanel.model else { return }
        model.soundsOn.toggle()
        let id = model.info.id, on = model.soundsOn
        if on { GameSounds.shared.play(.ding) }
        Task { await runtime.settings.update { $0.games.speakers[id] = on } }
    }

    /// The Again pill: the same coin or dice once more, through the tool as the person's own action.
    func tossAgain(_ toss: Toss) {
        switch toss {
        case .coins(let flips, _): self.toss(["kind": "coin", "count": .number(Double(flips.count))])
        case .dice(let sides, let rolls, let modifier):
            self.toss(["kind": "dice", "count": .number(Double(rolls.count)), "sides": .number(Double(sides)), "modifier": .number(Double(modifier))])
        case .hands: break
        }
    }

    #if DEBUG
    /// `game:<extension>/<game>[:level]` opens a game as the AI would, waiting for a click rather than taking the keyboard
    /// (a debug run must never catch the keys of someone typing elsewhere); `move:<json>` sends a move as a click on the
    /// board would (only one it offers); `drag:r,c,r2,c2` drags a puzzle's plot cell by cell, then lets go; `click:companion`
    /// clicks the companion in the scene, `click:x,y` a point of the panel; `key:<k>` presses a key in the panel; `closeGame` puts it away (D75); `playMenu`
    /// opens the panel's menu of games.
    func devGame(_ command: String) -> Bool {
        if command.hasPrefix("game:") {
            let parts = command.dropFirst(5).split(separator: ":").map(String.init)
            let path = parts.first?.split(separator: "/").map(String.init) ?? []
            guard path.count == 2 else { return true }
            var input: [String: JSONValue] = ["extension": .string(path[0]), "game": .string(path[1])]
            if parts.count > 1 { input["level"] = .string(parts[1]) }
            Task { _ = await runtime.executor.execute(name: "games.open", input: .object(input), caller: .agent(runId: "dev")) }
            return true
        }
        if command.hasPrefix("move:") {
            guard let json = try? JSONValue.parse(String(command.dropFirst(5))), let move = GameMove.parse(json) else { return true }
            playPanel.model?.send(move)
            return true
        }
        if command.hasPrefix("drag:") {
            // `drag:r,c,r2,c2`: a plot dragged corner to corner as the pointer would, a cell at a time, then let go.
            let n = command.dropFirst(5).split(separator: ",").compactMap { Int($0) }
            guard n.count == 4, let model = playPanel.model, let p = model.board?.puzzle else { return true }
            let w = p.columns
            Task { @MainActor in
                let steps = max(abs(n[2] - n[0]), abs(n[3] - n[1]), 1)
                for i in 0...steps {
                    let r = n[0] + (n[2] - n[0]) * i / steps, c = n[1] + (n[3] - n[1]) * i / steps
                    model.parts.drag = (n[0] * w + n[1], r * w + c)
                    try? await Task.sleep(for: .milliseconds(220))
                }
                model.parts.drag = nil
                model.send(.area(row: n[0], column: n[1], toRow: n[2], toColumn: n[3]))
            }
            return true
        }
        if command == "click:companion" {
            // A click on the companion in the scene, where it is a button (Which Cup?'s paw on Sneaky).
            if let frame = playPanel.model?.catchFrame { playPanel.click(at: CGPoint(x: frame.midX, y: frame.midY)) }
            return true
        }
        if command.hasPrefix("click:") {
            // `click:x,y`: a click at that point of the panel (points from its top left), as the mouse would.
            let n = command.dropFirst(6).split(separator: ",").compactMap { Double($0) }
            if n.count == 2 { playPanel.click(at: CGPoint(x: n[0], y: n[1])) }
            return true
        }
        if command.hasPrefix("key:") {
            // Timed now, as a key's own timestamp would be (a reflex press).
            _ = playPanel.model?.press(String(command.dropFirst(4)), at: ProcessInfo.processInfo.systemUptime)
            return true
        }
        if command == "closeGame" {
            playPanel.hide()
            return true
        }
        if command == "playMenu" {
            openPlayMenu(focus: false)
            return true
        }
        return false
    }
    #endif
}
