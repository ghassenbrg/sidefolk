import AppKit
import SidefolkCore

/// What Sidefolk keeps for the later board parts while a board shows: the person's draft word or number, the cell the
/// arrow keys point at, the pads' playback, the cups' shuffle and the reflex signal. All timing is Sidefolk's (D75):
/// a game only says how long.
struct PartsState {
    /// Letters or digits typed, until Return sends them.
    var draft = ""
    /// The cell or cup the arrow keys point at.
    var cursor: Int?
    /// The pad lit now, during the playback or a press.
    var lit: Int?
    /// The pads' sequence is playing: no presses yet.
    var playing = false
    /// When the cups' shuffle began (the gem shows first), for the drawing; presses wait until it ends.
    var shuffleStart = Date.distantPast
    var shuffling = false
    /// The reflex signal shows ("Boop!"), and when it was drawn, on the clock key events use.
    var signal: TimeInterval?
    /// The person pressed before the signal: "Too soon!" at once, the verdict after its beat.
    var early = false
    /// A board's `after` is running: only the game's next board may come.
    var waiting = false
    /// Rows and guesses on the last board, so a new one (a word or number accepted) clears the draft.
    var rowsSeen = 0
    var guessesSeen: Int?
}

extension PlayModel {
    /// Whether a move the board offered can be made now: not during a playback, a shuffle, or a board's wait.
    func ready(for move: GameMove) -> Bool {
        if parts.waiting { return move == .next }
        switch move {
        case .pad: return !parts.playing
        case .cell: return !(board?.cups != nil && parts.shuffling)
        default: return true
        }
    }

    /// A new board shows: its parts start their own time. A build-up (`verdict` false) only stops what ran.
    func shown(_ board: GameBoard, verdict: Bool) {
        partsTask?.cancel()
        afterTask?.cancel()
        parts.playing = false
        parts.shuffling = false
        parts.lit = nil
        parts.waiting = false
        if parts.signal != nil, board.reflex?.armed != true { parts.signal = nil }
        guard verdict else { return }
        parts.early = false
        parts.signal = nil
        // A word accepted (a new row) or a part gone clears what was typed; a refused one stays to be fixed.
        if board.keys?.mode != .spell, board.numberField == nil { parts.draft = "" }
        if let letters = board.letters, letters.rows.count != parts.rowsSeen { parts.draft = "" }
        parts.rowsSeen = board.letters?.rows.count ?? 0
        if board.numberField?.history.count != parts.guessesSeen { parts.draft = "" }
        parts.guessesSeen = board.numberField?.history.count
        if let cursor = parts.cursor, cursor >= cells(board) { parts.cursor = nil }
        if let pads = board.pads, !pads.play.isEmpty, !pads.locked { play(pads) }
        if let cups = board.cups, cups.shuffleSeconds > 0 { shuffle(cups) }
        if let reflex = board.reflex, reflex.armed, let after = reflex.after { arm(after, window: reflex.window) }
        if let after = board.after {
            parts.waiting = true
            afterTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(after))
                guard !Task.isCancelled, let self else { return }
                self.parts.waiting = false
                self.send(.next)
            }
        }
    }

    private func cells(_ board: GameBoard) -> Int { board.grid.map { $0.rows * $0.columns } ?? board.cups?.count ?? 0 }

    /// Sidefolk plays the sequence: each pad lit with its note, the companion doing its move, then the person's turn.
    private func play(_ pads: GameBoard.Pads) {
        parts.playing = true
        partsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            for i in pads.play {
                guard !Task.isCancelled, let self else { return }
                self.parts.lit = i
                if self.soundsOn { GameSounds.shared.note(i) }
                self.onPadStep?(pads.pads[i])
                try? await Task.sleep(for: .seconds(pads.stepSeconds * 0.7))
                self.parts.lit = nil
                try? await Task.sleep(for: .seconds(pads.stepSeconds * 0.3))
            }
            self?.parts.playing = false
        }
    }

    private func shuffle(_ cups: GameBoard.Cups) {
        parts.shuffling = true
        parts.shuffleStart = Date()
        partsTask = Task { [weak self] in
            if self?.soundsOn == true { GameSounds.shared.play(.shuffle) }
            try? await Task.sleep(for: .seconds(cups.shuffleSeconds))
            guard !Task.isCancelled else { return }
            self?.parts.shuffling = false
        }
    }

    /// "Steady…" for the game's wait, then the signal, timed from the moment it is drawn; no press in the window is a
    /// timeout.
    private func arm(_ after: Double, window: Double) {
        partsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(after))
            guard !Task.isCancelled, let self, !self.parts.early else { return }
            self.parts.signal = ProcessInfo.processInfo.systemUptime
            if self.soundsOn { GameSounds.shared.play(.boop) }
            try? await Task.sleep(for: .seconds(window))
            guard !Task.isCancelled, self.parts.signal != nil else { return }
            self.send(.timeout)
        }
    }

    /// The reflex button, clicked or pressed: before the signal "Too soon!" at once, after it the time since it showed.
    /// - Parameter time: the event's timestamp (seconds since boot, the clock the signal was stamped with).
    func boop(at time: TimeInterval? = nil) {
        guard let board, board.reflex?.armed == true, pending == nil else { return }
        guard let signal = parts.signal else {
            partsTask?.cancel()
            parts.early = true
            send(.early)
            return
        }
        let at = time ?? NSApp.currentEvent?.timestamp ?? ProcessInfo.processInfo.systemUptime
        partsTask?.cancel()
        send(.press(milliseconds: max(0, Int(((at - signal) * 1000).rounded()))))
    }

    /// A pad pressed: lit a moment, its note, then the move.
    func pressPad(_ i: Int) {
        guard let pads = board?.pads, pads.pads.indices.contains(i), !parts.playing, !pads.locked else { return }
        parts.lit = i
        if soundsOn { GameSounds.shared.note(i) }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.18))
            if self?.parts.lit == i { self?.parts.lit = nil }
        }
        send(.pad(i))
    }

    // MARK: Typing

    /// A letter on the keyboard part: sent at once, or added to the word being spelled.
    func type(_ letter: String) {
        guard let keys = board?.keys, !keys.locked, pending == nil else { return }
        switch keys.mode {
        case .letter: if let c = letter.first, letter.count == 1 { send(.letter(c)) }
        case .spell: if parts.draft.count < keys.length { parts.draft += letter }
        }
    }

    func deleteBack() {
        guard !parts.draft.isEmpty else { return }
        parts.draft.removeLast()
    }

    /// Return on a word or a number being typed.
    func submitDraft() {
        guard let board else { return }
        if let keys = board.keys, keys.mode == .spell, parts.draft.count == keys.length {
            send(.word(parts.draft.lowercased()))
        } else if let field = board.numberField, let n = Int(parts.draft), (field.min...field.max).contains(n) {
            send(.number(n))
        }
    }

    func typeDigit(_ d: String) {
        guard let field = board?.numberField, !field.locked, parts.draft.count < String(field.max).count else { return }
        parts.draft = parts.draft == "0" ? d : parts.draft + d
    }

    /// A key on a part, before the board's own keys (tiles, buttons, Return for the main button). True when used.
    func pressPart(_ k: String, at time: TimeInterval?) -> Bool {
        guard let board else { return false }
        if board.reflex?.armed == true, k == "space" || k == "return" {
            boop(at: time)
            return true
        }
        if let pads = board.pads, !pads.locked, let n = Int(k), pads.pads.indices.contains(n - 1) {
            pressPad(n - 1)
            return true
        }
        if let sticks = board.sticks, !sticks.locked, let n = Int(k), (1...min(sticks.take, sticks.left)).contains(n) {
            send(.number(n))
            return true
        }
        if let grid = board.grid, !grid.locked {
            if grid.numpad, let n = Int(k), (1...9).contains(n) {
                let cell = (2 - (n - 1) / 3) * 3 + (n - 1) % 3
                send(.cell(row: cell / 3, column: cell % 3))
                return true
            }
            if moveCursor(k, columns: grid.columns, count: grid.rows * grid.columns) { return true }
            if k == "return" || k == "space", let c = parts.cursor {
                send(.cell(row: c / grid.columns, column: c % grid.columns))
                return true
            }
        }
        if let cups = board.cups, !cups.locked, !cups.revealed {
            if let n = Int(k), (1...cups.count).contains(n) {
                send(.cell(row: 0, column: n - 1))
                return true
            }
            if moveCursor(k, columns: cups.count, count: cups.count) { return true }
            if k == "return" || k == "space", let c = parts.cursor {
                send(.cell(row: 0, column: c))
                return true
            }
        }
        if let field = board.numberField, !field.locked {
            if let d = Int(k), (0...9).contains(d) { typeDigit(k); return true }
            if k == "delete" { deleteBack(); return true }
            if k == "return", !parts.draft.isEmpty { submitDraft(); return true }
        }
        if let keys = board.keys, !keys.locked, k.count == 1, k.first!.isLetter {
            type(k)
            return true
        }
        if board.keys?.mode == .spell {
            if k == "delete" { deleteBack(); return true }
            if k == "return", !parts.draft.isEmpty { submitDraft(); return true }
        }
        return false
    }

    /// The arrow keys move the pointer over cells or cups, starting at the first.
    private func moveCursor(_ k: String, columns: Int, count: Int) -> Bool {
        let step = switch k {
        case "left": -1
        case "right": 1
        case "up": -columns
        case "down": columns
        default: 0
        }
        guard step != 0 else { return false }
        // Left and right follow the reading direction: in Arabic the next cell is to the left.
        let rtl = NSApp.userInterfaceLayoutDirection == .rightToLeft && abs(step) == 1 ? -1 : 1
        let next = (parts.cursor ?? -step * rtl) + step * rtl
        parts.cursor = min(max(next, 0), count - 1)
        return true
    }

    /// The keys a part takes, for the quiet line under the board.
    var partsFooter: String? {
        guard let board else { return nil }
        if let r = board.reflex, r.armed {
            return String(localized: "Space: \(r.go)", comment: "Keys in the Play panel: press Space when the game's word (“Boop!”) shows")
        }
        if let p = board.pads, !p.locked {
            return String(localized: "1–\(p.pads.count) to copy", comment: "Keys in the Play panel: the pads of Copy Me")
        }
        if let s = board.sticks, !s.locked {
            return String(localized: "1–\(min(s.take, s.left)) to take", comment: "Keys in the Play panel: how many sticks to take")
        }
        if let g = board.grid, !g.locked {
            return g.numpad ? String(localized: "1–9 to play", comment: "Keys in the Play panel: the number pad picks a cell")
                : String(localized: "Arrows and Return to pick", comment: "Keys in the Play panel: arrows move over the cells")
        }
        if let c = board.cups, !c.locked, !c.revealed {
            return String(localized: "1–\(c.count) to pick", comment: "Keys in the Play panel: which cup")
        }
        if let n = board.numberField, !n.locked {
            return String(localized: "Type a number, Return to guess", comment: "Keys in the Play panel")
        }
        if let k = board.keys, !k.locked {
            return k.mode == .spell ? String(localized: "Type a word, Return to try", comment: "Keys in the Play panel")
                : String(localized: "Type a letter", comment: "Keys in the Play panel")
        }
        return nil
    }
}
