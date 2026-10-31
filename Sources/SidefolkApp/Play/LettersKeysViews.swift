import SidefolkCore
import SwiftUI

// The word games' parts: letter tiles (Daily Word's rows, Balloon Words' slots), an on-screen keyboard in the game's
// script, and a text field for what only an input method types (Chinese idioms, an animal's name).

/// Rows of letter tiles; the newest flips tile by tile, and what the person types shows in the next row.
struct LettersView: View {
    var letters: GameBoard.Letters
    var model: PlayModel

    var body: some View {
        let side = Self.side(letters)
        VStack(spacing: 6) {
            ForEach(0..<(letters.style == .slots ? 1 : letters.tries), id: \.self) { r in
                row(r, side: side)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    /// Tiles as large as the row allows: up to 46 pt, smaller for long words.
    static func side(_ l: GameBoard.Letters) -> CGFloat {
        let widest = max(l.length, l.rows.map(\.count).max() ?? 0)
        let room = PlayView.width - 32 - CGFloat(max(0, widest - 1)) * 5
        return min(l.style == .slots ? 34 : 46, room / CGFloat(max(widest, 1)))
    }

    @ViewBuilder private func row(_ r: Int, side: CGFloat) -> some View {
        if letters.rows.indices.contains(r) {
            tiles(letters.rows[r], side: side, flipping: letters.flip == r)
        } else if letters.draft && r == letters.rows.count {
            // The row being typed: the person's letters, grouped as they will be (jamo into syllables).
            let typed = Hangul.split(model.parts.draft, script: letters.script)
            let row = (0..<letters.length).map { i in
                i < typed.count ? GameBoard.Letters.Tile(text: typed[i].text, mark: .none, group: typed[i].group)
                    : GameBoard.Letters.Tile(text: "", mark: .none, group: typed.last.map { $0.group + 1 + i - typed.count } ?? i)
            }
            tiles(row, side: side, flipping: false, draft: true)
        } else {
            tiles((0..<letters.length).map { GameBoard.Letters.Tile(text: "", mark: .none, group: $0) }, side: side, flipping: false)
        }
    }

    /// One row, letters of one group close together (a Korean syllable, a pinyin syllable, a word).
    private func tiles(_ row: [GameBoard.Letters.Tile], side: CGFloat, flipping: Bool, draft: Bool = false) -> some View {
        let groups = Dictionary(grouping: row.indices, by: { row[$0].group }).sorted { $0.key < $1.key }
        let tight = letters.script == .hangul || letters.style == .slots
        return HStack(spacing: tight ? 10 : 5) {
            ForEach(groups, id: \.key) { _, members in
                HStack(spacing: tight ? 2 : 5) {
                    ForEach(members, id: \.self) { i in
                        LetterTileView(tile: row[i], side: side, slot: letters.style == .slots, draft: draft,
                                       delay: flipping ? Double(i) * 0.22 : nil)
                    }
                }
                .padding(letters.script == .hangul && members.count > 1 ? 3 : 0)
                .background(letters.script == .hangul && members.count > 1
                            ? RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.surfaceSunken.opacity(0.7)) : nil)
            }
        }
    }
}

/// A letter in its place: its mark's colour with a symbol (● right, ◐ elsewhere), never colour alone.
struct LetterTileView: View {
    var tile: GameBoard.Letters.Tile
    var side: CGFloat
    var slot: Bool
    var draft: Bool
    /// When this tile of a just-played row turns over.
    var delay: Double?
    @State private var turned = true
    /// A fixed moment, for the UI snapshots: drawn turned.
    @Environment(\.revealProgress) private var fixed

    private var fill: Color {
        guard turned else { return Theme.surfaceSunken }
        switch tile.mark {
        case .right: return Theme.success
        case .elsewhere: return Theme.sun
        case .absent: return Theme.inkFaint.opacity(0.35)
        case .none, .hidden: return slot ? .clear : Theme.surfaceSunken
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: slot ? 4 : 8, style: .continuous).fill(fill)
            if slot {
                Rectangle().fill(Theme.ink.opacity(0.6)).frame(height: 2.5).frame(maxHeight: .infinity, alignment: .bottom)
            } else if tile.mark == .none {
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(draft && !tile.text.isEmpty ? Theme.inkMuted : Theme.line,
                                                                                   lineWidth: draft && !tile.text.isEmpty ? 2 : 1)
            }
            Text(verbatim: tile.mark == .hidden ? "" : tile.text)
                .font(.system(size: side * 0.52, weight: .bold, design: .rounded))
                .foregroundStyle(turned && tile.mark == .right ? .white : Theme.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if turned, let symbol {
                Text(verbatim: symbol).font(.system(size: max(7, side * 0.2))).foregroundStyle(tile.mark == .right ? .white : Theme.ink)
                    .padding(3)
            }
        }
        .frame(width: side, height: side)
        // A flip drawn flat (a 3D rotation inside the panel drew the turning tile at the panel's corner).
        .scaleEffect(x: 1, y: turned ? 1 : 0.02)
        .onAppear {
            guard let delay, fixed == nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            turned = false
            withAnimation(.easeOut(duration: 0.25).delay(delay)) { turned = true }
        }
        .accessibilityLabel(Text(verbatim: accessibility))
    }

    private var symbol: String? {
        switch tile.mark {
        case .right: "●"
        case .elsewhere: "◐"
        default: nil
        }
    }

    private var accessibility: String {
        let what = tile.text.isEmpty ? String(localized: "blank", comment: "An empty letter place in a word game, read by VoiceOver") : tile.text
        return switch tile.mark {
        case .right: what + ", " + String(localized: "right place", comment: "A word game's letter, read by VoiceOver")
        case .elsewhere: what + ", " + String(localized: "in the word, elsewhere", comment: "A word game's letter, read by VoiceOver")
        case .absent: what + ", " + String(localized: "not in the word", comment: "A word game's letter, read by VoiceOver")
        default: what
        }
    }
}

/// An on-screen keyboard in the game's script: pages to switch between (あ, が, ゃ), each key its own cap with its mark,
/// and ⌫ and ↵ when a word is spelled.
struct KeyboardView: View {
    var keys: GameBoard.Keys
    var model: PlayModel
    @State private var page = 0

    var body: some View {
        let shown = keys.pages[min(page, keys.pages.count - 1)]
        VStack(spacing: 5) {
            if keys.pages.count > 1 {
                HStack(spacing: 4) {
                    ForEach(Array(keys.pages.enumerated()), id: \.offset) { i, p in
                        Button { page = i } label: {
                            Text(verbatim: p.label).font(Theme.Font.captionStrong).frame(maxWidth: .infinity).padding(.vertical, 4)
                                .foregroundStyle(i == page ? Theme.onAccent : Theme.ink)
                                .background(Capsule().fill(i == page ? Theme.accent : .clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Capsule().fill(Theme.surfaceSunken))
            }
            ForEach(Array(shown.rows.enumerated()), id: \.offset) { r, row in
                HStack(spacing: 4) {
                    if keys.mode == .spell, r == shown.rows.count - 1 {
                        special("return", symbol: "return", wide: true) { model.submitDraft() }
                    }
                    ForEach(row, id: \.key) { key in keyButton(key) }
                    if keys.mode == .spell, r == shown.rows.count - 1 {
                        special("delete", symbol: "delete.left", wide: true) { model.deleteBack() }
                    }
                }
            }
        }
        .opacity(keys.locked ? 0.55 : 1)
        .allowsHitTesting(!keys.locked)
    }

    private func keyButton(_ key: GameBoard.Keys.Key) -> some View {
        let (fill, ink) = Self.colors(key.mark)
        return Button { model.type(key.key) } label: {
            Text(verbatim: keys.script == .latin ? key.key.uppercased() : key.key)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .strikethrough(key.mark == .miss || key.mark == .absent, color: ink.opacity(0.7))
                .frame(maxWidth: 30, minHeight: 32)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.line, lineWidth: key.mark == .none ? 1 : 0))
        }
        .buttonStyle(.plain)
        // Not `disabled`, which would grey out the marks: a used key just takes no more presses.
        .allowsHitTesting(!(keys.mode == .letter && key.mark != .none))
        .accessibilityLabel(Text(verbatim: key.key))
    }

    private func special(_ name: String, symbol: String, wide: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                .frame(minWidth: 40, minHeight: 32)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.surfaceRaised))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name == "return" ? String(localized: "Try this word", comment: "A word game's Return key, read by VoiceOver")
                            : String(localized: "Delete", comment: "A word game's delete key, read by VoiceOver"))
    }

    /// A used key: right (success, as on the tiles), elsewhere (the tiles' yellow), absent or missed (faded and struck
    /// through, never red).
    static func colors(_ mark: GameBoard.Keys.Mark) -> (Color, Color) {
        switch mark {
        case .right, .hit: (Theme.success, .white)
        case .elsewhere: (Theme.sun, Theme.ink)
        case .absent: (Theme.inkFaint.opacity(0.3), Theme.inkMuted)
        case .miss: (GameColors.lostSoft, Theme.inkMuted)
        case .none: (Theme.surfaceSunken, Theme.ink)
        }
    }
}

/// A text field for what only the person's input method types; Return or its button sends it.
struct GameEntryView: View {
    var entry: GameBoard.Entry
    var model: PlayModel
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label = entry.label { Text(verbatim: label).font(Theme.Font.captionStrong).foregroundStyle(Theme.inkMuted) }
            HStack(spacing: 8) {
                TextField(entry.placeholder ?? "", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surfaceSunken))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    .onSubmit(submit)
                    .onChange(of: text) { _, new in if new.count > entry.max { text = String(new.prefix(entry.max)) } }
                Button(entry.button ?? String(localized: "OK", comment: "Sends what was typed in a game")) { submit() }
                    .buttonStyle(.sf(.primary))
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .disabled(entry.locked)
    }

    private func submit() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        switch entry.kind {
        case .word: model.send(.word(value.lowercased()))
        case .text: model.send(.text(name: entry.name, value: value))
        }
        text = ""
    }
}

/// Korean jamo typed one by one, grouped into the syllables they make (ㅅ ㅏ ㄱ ㅗ ㅏ is 사 과), so a half-typed word is
/// drawn as the blocks it will be. Other scripts: one group per letter.
enum Hangul {
    static let leads: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    static let vowels: Set<Character> = Set("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅛㅜㅠㅡㅣ")
    /// Vowels that join into one (ㅗ ㅏ is ㅘ).
    static let compound: Set<String> = ["ㅗㅏ", "ㅗㅐ", "ㅗㅣ", "ㅜㅓ", "ㅜㅔ", "ㅜㅣ", "ㅡㅣ"]
    /// Final consonants that join (ㄹ ㄱ is ㄺ).
    static let tails: Set<String> = ["ㄱㅅ", "ㄴㅈ", "ㄴㅎ", "ㄹㄱ", "ㄹㅁ", "ㄹㅂ", "ㄹㅅ", "ㄹㅌ", "ㄹㅍ", "ㄹㅎ", "ㅂㅅ"]

    static func split(_ typed: String, script: GameBoard.Keys.Script) -> [(text: String, group: Int)] {
        let jamo = Array(typed)
        guard script == .hangul else { return jamo.enumerated().map { (String($1), $0) } }
        var out: [(String, Int)] = []
        var i = 0, group = 0
        func isVowel(_ k: Int) -> Bool { k < jamo.count && vowels.contains(jamo[k]) }
        func isLead(_ k: Int) -> Bool { k < jamo.count && leads.contains(jamo[k]) }
        while i < jamo.count {
            var end = i + 1
            if isLead(i), isVowel(i + 1) {
                end = i + 2
                if isVowel(end), compound.contains(String([jamo[end - 1], jamo[end]])) { end += 1 }
                // A consonant after the vowel closes the syllable unless a vowel follows it (then it starts the next).
                if isLead(end), !isVowel(end + 1) {
                    end += 1
                    if isLead(end), !isVowel(end + 1), tails.contains(String([jamo[end - 1], jamo[end]])) { end += 1 }
                }
            }
            for k in i..<end { out.append((String(jamo[k]), group)) }
            group += 1
            i = end
        }
        return out
    }
}
