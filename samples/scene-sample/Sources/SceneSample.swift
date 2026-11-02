import Foundation
import SidefolkExtensionKit

/// Four small surfaces, kept apart from the wiring so tests can read their scenes. Every scene is built whole from the
/// state each time: Sidefolk keeps what is the same on screen, and only what changed moves.
@MainActor
enum SceneSample {
    static func install(on ext: Extension) {
        ext.surface("shuffle", open: { _ in
            shuffle = Shuffle()
            return SurfaceReply(session: "shuffle", scene: shuffle.scene())
        }, move: { request in
            switch request.move {
            case .click(area: "pick", value: let value?, ms: _): shuffle.pick(Int(value) ?? 0)
            case .click(area: "again", value: _, ms: _): shuffle = Shuffle()
            default: break
            }
            return shuffle.scene()
        })
        ext.surface("drag", open: { _ in
            board = DragBoard()
            return SurfaceReply(session: "drag", scene: board.scene())
        }, move: { request in
            switch request.move {
            case .dragPoints(area: "pin", value: _, from: _, to: let to): board.drop(to[0], to[1])
            case .dragCells(area: "field", value: _, from: let from, to: let to): board.plant(from, to)
            default: break
            }
            return board.scene()
        })
        ext.surface("keys", open: { _ in
            word = WordBoard()
            return SurfaceReply(session: "keys", scene: word.scene())
        }, move: { request in
            if case .click(area: "kb", value: let key?, ms: _) = request.move { word.press(key) }
            return word.scene()
        })
        ext.surface("coin", open: { _ in
            coin = Coin()
            return SurfaceReply(session: "coin", scene: coin.scene())
        }, move: { request in
            if case .click(area: "coin", value: _, ms: _) = request.move { coin.flip() }
            return coin.scene()
        })
    }

    static var shuffle = Shuffle()
    static var board = DragBoard()
    static var word = WordBoard()
    static var coin = Coin()
}

func sampleTitle(_ words: String) -> Node {
    Node.text(words, size: 17, weight: "heavy", design: "rounded", lines: 2).size(372, 44).at(14, 8)
}

/// Three tiles from the pack: seen, turned over, shuffled by the app from the swaps alone, then one picked.
struct Shuffle {
    static let faces = ["tile-star.png", "tile-leaf.png", "tile-moon.png"]
    static let names = ["star", "leaf", "moon"]
    static let side = 104.0, top = 96.0, gap = 22.0
    static func slot(_ i: Int) -> Double { 14 + Double(i) * (side + gap) }

    /// Where each tile sits now: `order[position] = tile`.
    var order = [0, 1, 2]
    /// The swaps of this round, as positions, fixed before it plays.
    var swaps: [(Int, Int)] = (0..<5).map { _ in
        let a = Int.random(in: 0..<3)
        return (a, (a + Int.random(in: 1..<3)) % 3)
    }
    var picked: Int?

    mutating func pick(_ position: Int) {
        guard picked == nil, (0..<3).contains(position) else { return }
        order = Self.after(swaps)
        picked = position
    }

    static func after(_ swaps: [(Int, Int)]) -> [Int] {
        var order = [0, 1, 2]
        for (a, b) in swaps { order.swapAt(a, b) }
        return order
    }

    func tile(_ i: Int, x: Double, showing: String) -> Node {
        Node.flip(front: .image(Self.faces[i]).size(Self.side, Self.side), back: .image("back.png").size(Self.side, Self.side), showing: showing)
            .size(Self.side, Self.side).at(x, Self.top).id("tile\(i)").leftToRight()
    }

    func scene() -> Scene {
        if let picked {
            let won = order[picked] == 0
            return Scene(width: 400, height: 370) {
                sampleTitle(won ? "You found the star!" : "That was the \(Self.names[order[picked]]).")
                Node.companion(pose: won ? "waiting" : "celebrating").size(60, 60).at(14, 256)
                for i in 0..<3 { tile(order[i], x: Self.slot(i), showing: i == picked ? "back" : "back") }
                Node.symbol(won ? "checkmark.circle.fill" : "xmark.circle.fill", color: won ? .win : .loss).size(26, 26).at(Self.slot(picked) + 39, 210)
                Node.rect(fill: .accent, corner: 12).size(140, 40).at(246, 270)
                    .children { Node.text("Again", size: 15, weight: "bold", color: .onAccent).size(140, 40) }
                    .area("again", label: "Play again", key: "return")
            }
            .animating(.flip("tile\(order[picked])", 2, ms: 500, ease: "in_out"))
            .react(Reaction(move: won ? "sulk" : "cheer", look: "panel"))
            .animating(.sound(won ? "ding.wav" : "tick.wav"))
            .announcing(won ? "You found the star" : "Not this time")
            .over(outcome: won ? "win" : "loss", tally: won ? [1, 0] : [0, 1])
        }
        var steps: [Anim] = [.wait(ms: 900), .sound("whoosh.wav")]
        steps.append(.together((0..<3).map { .flip("tile\($0)", 1, ms: 360, ease: "in_out") }))
        // Each swap moves the tiles at those positions, whichever they are by then.
        var at = [0, 1, 2]
        for (a, b) in swaps {
            steps.append(.sound("tick.wav"))
            steps.append(.swap("tile\(at[a])", fromX: Self.slot(a), "tile\(at[b])", fromX: Self.slot(b), restY: Self.top, ms: 360))
            at.swapAt(a, b)
        }
        return Scene(width: 400, height: 370) {
            sampleTitle("Watch the star, then pick it. {companion} is watching too.")
            Node.companion(pose: "thinking").size(60, 60).at(14, 256)
            Node.person().size(30, 30).corner(15).at(82, 280)
            for i in 0..<3 { tile(i, x: Self.slot(i), showing: "front") }
            // The areas stay at the places, under the tiles' path: a pick is a position, as the swaps are.
            for i in 0..<3 {
                Node.rect(fill: .clear).size(Self.side, Self.side).at(Self.slot(i), Self.top).id("slot\(i)").z(5)
                    .area("pick", value: "\(i)", label: "Tile \(i + 1)", key: "\(i + 1)")
            }
            Node.text("Keys 1, 2 and 3 work too", size: 12, color: .inkMuted).size(240, 20).at(146, 300)
        }
        .animating(Anim.sequence(steps).essential().blocksInput().named("round"))
        .react(Reaction(move: "shuffle", look: "panel"))
    }
}

/// A pin dragged freely onto a ring, and rectangles dragged over a grid of cells, the preview drawn by the app as it goes.
struct DragBoard {
    static let cell = 34.0, rows = 4, columns = 8, top = 190.0, left = 64.0
    var pin = (x: 40.0, y: 70.0)
    var plots: [(row: Int, column: Int, height: Int, width: Int)] = []
    var onRing: Bool { abs(pin.x - 300) < 40 && abs(pin.y - 110) < 40 }

    mutating func drop(_ x: Double, _ y: Double) { pin = (min(max(x, 20), 380), min(max(y, 60), 170)) }

    mutating func plant(_ from: [Int], _ to: [Int]) {
        let plot = (row: min(from[0], to[0]), column: min(from[1], to[1]), height: abs(from[0] - to[0]) + 1, width: abs(from[1] - to[1]) + 1)
        plots.removeAll { $0.row == plot.row && $0.column == plot.column && $0.height == plot.height && $0.width == plot.width }
        plots.append(plot)
    }

    func scene() -> Scene {
        Scene(width: 400, height: 350) {
            sampleTitle(onRing ? "On the ring!" : "Drag the pin to the ring, and drag across the grid")
            Node.ellipse(stroke: onRing ? .win : .inkFaint, lineWidth: 4).size(84, 84).at(258, 68)
            Node.image("pin.png").size(44, 44).at(pin.x - 22, pin.y - 22).id("pin").z(6)
                .area("pin", label: "The pin", drag: .free(ghost: "pin"))
            Node.group {
                Node.rect(fill: .surfaceSunken, stroke: .line, corner: 8).size(Self.cell * Double(Self.columns), Self.cell * Double(Self.rows))
                for r in 0..<Self.rows {
                    for c in 0..<Self.columns {
                        Node.rect(stroke: .line).size(Self.cell, Self.cell).at(Double(c) * Self.cell, Double(r) * Self.cell)
                    }
                }
                for (i, p) in plots.enumerated() {
                    Node.rect(fill: .accentSoft, stroke: .accent, lineWidth: 2, corner: 6)
                        .size(Double(p.width) * Self.cell, Double(p.height) * Self.cell).at(Double(p.column) * Self.cell, Double(p.row) * Self.cell).id("plot\(i)")
                }
                Node.rect(stroke: .accent, lineWidth: 2, corner: 6, dash: [6, 4]).size(0, 0).opacity(0).id("preview").z(4)
                Node.rect(fill: .clear).size(Self.cell * Double(Self.columns), Self.cell * Double(Self.rows)).id("field").z(5)
                    .area("field", label: "A field to draw plots on", drag: .cells(rows: Self.rows, columns: Self.columns, ghost: "preview"))
            }
            .size(Self.cell * Double(Self.columns), Self.cell * Double(Self.rows)).at(Self.left, Self.top).leftToRight()
        }
        .transition(ms: 160)
    }
}

/// A keyboard and rows of letters: each press comes back as a move, and the row just played turns tile after tile.
struct WordBoard {
    static let answer = Array("star")
    static let rows = [Array("qwertyuiop"), Array("asdfghjkl"), Array("zxcvbnm")]
    var draft = ""
    var played: [String] = []
    var justPlayed = false

    var solved: Bool { played.last == String(Self.answer) }

    mutating func press(_ key: String) {
        justPlayed = false
        guard !solved, played.count < 3 else { return }
        switch key {
        case "⌫": if !draft.isEmpty { draft.removeLast() }
        case "↵":
            if draft.count == Self.answer.count {
                played.append(draft)
                draft = ""
                justPlayed = true
            }
        default: if draft.count < Self.answer.count { draft += key }
        }
    }

    func mark(_ letter: Character, _ i: Int) -> Color? {
        Self.answer[i] == letter ? .win : Self.answer.contains(letter) ? .warning : .inkFaint
    }

    func scene() -> Scene {
        let side = 54.0, gap = 6.0, left = (440 - (side + gap) * 4 + gap) / 2
        var flips: [String] = []
        let tiles = (0..<3).flatMap { r -> [Node] in
            let word = r < played.count ? Array(played[r]) : r == played.count ? Array(draft) : []
            return (0..<4).map { c -> Node in
                let letter = c < word.count ? String(word[c]).uppercased() : ""
                let done = r < played.count
                let id = "t\(r).\(c)"
                if done, justPlayed, r == played.count - 1 { flips.append(id) }
                let plain = Node.group {
                    Node.rect(fill: .surfaceSunken, stroke: .line, corner: 8).size(side, side)
                    Node.text(letter, size: 24, weight: "heavy", design: "rounded").size(side, side)
                }.size(side, side)
                let marked = Node.group {
                    Node.rect(fill: done && c < word.count ? mark(word[c], c) : .surfaceSunken, corner: 8).size(side, side)
                    Node.text(letter, size: 24, weight: "heavy", design: "rounded", color: .onAccent).size(side, side)
                }.size(side, side)
                return Node.flip(front: plain, back: marked, showing: done && !(justPlayed && r == played.count - 1) ? "back" : "front", axis: "x")
                    .size(side, side).id(id).label(letter.isEmpty ? "empty" : letter)
            }
        }
        let keys: [[KeyCap]] = Self.rows.enumerated().map { i, row in
            var caps = row.map { k -> KeyCap in
                let s = String(k)
                let used = played.contains { $0.contains(k) }
                return KeyCap(s, label: s.uppercased(), faded: used && !Self.answer.contains(k))
            }
            if i == 2 {
                caps.insert(KeyCap("↵", spoken: "Try this word", typed: "return", fill: .accent, ink: .onAccent, width: 52), at: 0)
                caps.append(KeyCap("⌫", spoken: "Delete a letter", typed: "delete", width: 52))
            }
            return caps
        }
        var scene = Scene(width: 440, height: 400) {
            sampleTitle(solved ? "That's it!" : played.count == 3 ? "It was STAR" : "Spell a word of four letters").size(412, 34)
            Node.grid(columns: 4, cell: (side, side), gap: (gap, gap)) { tiles }.at(left, 50).leftToRight()
            Node.keyset(name: "kb", rows: keys, key: (38, 44), gap: (4, 6), sound: "tick.wav").at(8, 250).size(424, 144)
        }
        if !flips.isEmpty {
            scene = scene.animating(Anim.stagger(flips, stepMs: 140, ["flip": 1], ms: 340, ease: "in_out").blocksInput())
        }
        return scene
    }
}

/// A coin in the air above the companion: the result is fixed before it plays, the app only draws it.
struct Coin {
    var heads = Bool.random()
    var round = 0

    mutating func flip() {
        heads = Bool.random()
        round += 1
    }

    func scene() -> Scene {
        let turns = heads ? 12.0 : 11.0
        return Scene(width: 200, height: 220) {
            Node.flip(front: .image("coin-heads.png").size(84, 84), back: .image("coin-tails.png").size(84, 84), axis: "x")
                .size(84, 84).at(58, 120).id("coin").area("coin", label: "Flip the coin again")
            Node.capsule(fill: .surface, stroke: .line).size(96, 32).at(52, 8).id("word").opacity(0)
                .children { Node.text(heads ? "Heads!" : "Tails!", size: 16, weight: "heavy", design: "rounded").size(96, 32) }
        }
        .animating(Anim.together([
            .react(Reaction(move: "flick")),
            .sound("whoosh.wav"),
            .flip("coin", turns, ms: 1100, ease: "out"),
            .keys("coin", [["t": 0, "y": 120], ["t": 0.5, "y": 44], ["t": 1, "y": 120]], ms: 1100, ease: "in_out"),
            .fade("word", 1, ms: 200).delay(ms: 1150),
            .sound("ding.wav").delay(ms: 1100),
        ]).named("flip\(round)"))
        .announcing(heads ? "Heads" : "Tails")
    }
}
