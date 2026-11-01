import SidefolkCharacter
import SidefolkCore
import SwiftUI

/// The Play panel (D75, dressed as a game in D79 amended, the look v2): the game's scene by day or at night behind it
/// all, a header card with its icon, title and whose game it is, "You vs <companion>" with the score, the companion in
/// the scene saying the prompt, the board, and a hint card of keys. Everything is drawn by Sidefolk from the board's
/// data and its own art.
struct PlayView: View {
    var model: PlayModel
    var onSpeaker: () -> Void = {}

    static let width: CGFloat = 400
    static let pad: CGFloat = 14
    /// The room inside the panel's padding, for parts that size themselves.
    static let inner: CGFloat = width - 2 * pad
    static let accent = Theme.folkColor("play")

    var style: GameStyle { .of(model.info.look) }

    /// The panel stays under about 720 pt, so it never crowds a 13" screen: a board taller than its room scrolls.
    static let maxHeight: CGFloat = 720
    static let boardRoom: CGFloat = 540

    var body: some View {
        VStack(spacing: 8) {
            PlayHeader(model: model, style: style, onSpeaker: onSpeaker)
            // A puzzle is played alone against the clock: no "You vs" bar, so a 9 × 9 Sudoku keeps its room.
            if model.board?.puzzle == nil {
                ScoreBar(score: model.board?.score, companionName: model.companionName, portrait: model.portrait, you: model.you, style: style)
                    .padding(.horizontal, Self.pad)
            }
            Group {
                if let failure = model.failure {
                    failed(failure).padding(.horizontal, Self.pad)
                } else if let board = model.board {
                    ScrollView(.vertical, showsIndicators: false) {
                        BoardView(model: model, board: board, style: style)
                            .padding(.horizontal, Self.pad).padding(.vertical, 2)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: Self.boardRoom)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity).frame(height: 160)
                }
            }
            HintRow(text: model.footer).padding(.horizontal, Self.pad)
        }
        .padding(.top, 7).padding(.bottom, 10)
        .frame(width: Self.width)
        .background(GameSceneBackground(style: style))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: model.info.title))
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller").font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            Text(verbatim: message).font(Theme.Font.body).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            Button(String(localized: "Close", comment: "Closes the Play panel")) { model.onClose?() }.buttonStyle(.sf(.secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .gameCard()
    }
}

/// A round button in the header card: back, the speaker, ✕.
struct HeaderButton: View {
    var symbol: String
    var label: String
    /// Its key, in the tooltip.
    var shortcut: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).frame(width: 30, height: 30)
                .foregroundStyle(Theme.ink)
                .background(Circle().fill(GamePaint.inset))
                .overlay(Circle().strokeBorder(GamePaint.edge, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(GamePressStyle())
        .focusable(false)
        .help(shortcut.map { "\(label) (\u{2066}\($0)\u{2069})" } ?? label)
        .accessibilityLabel(label)
    }
}

/// The game's header, a card over the top of its scene: back to the menu, its icon on a tile, its title and whose game
/// it is, the speaker and ✕. The game's colour is its icon tile's; the card itself is the panel's, so the words read
/// the same in every game.
struct PlayHeader: View {
    var model: PlayModel
    var style: GameStyle
    var onSpeaker: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let back = model.onBack {
                // Never disabled: whatever the game is doing, it is put away and the menu shows (`PlayBack`).
                HeaderButton(symbol: "chevron.backward", label: String(localized: "All games", comment: "Play panel: back to the menu of games"),
                             shortcut: "⌘[", action: back)
            }
            GameIconTile(info: model.info, style: style, side: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: model.info.title).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if !model.info.isSidefolk {
                    // Whose game it is, so it never passes for Sidefolk's own.
                    HStack(spacing: 4) {
                        ExtensionBadge(look: ExtensionLook(name: model.info.extensionName, iconPath: model.info.iconPath, folk: "play"), size: 13)
                        Text(verbatim: model.info.extensionName).font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1)
                    }
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.leading, 3).padding(.trailing, 8).padding(.vertical, 2)
                    .background(Capsule().fill(GamePaint.inset))
                }
            }
            Spacer(minLength: 4)
            HeaderButton(symbol: model.soundsOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                         label: model.soundsOn ? String(localized: "Turn the game's sounds off") : String(localized: "Turn the game's sounds on"),
                         action: onSpeaker)
            HeaderButton(symbol: "xmark", label: String(localized: "Close", comment: "Closes the Play panel")) { model.onClose?() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .gameCard(corner: 20, opacity: 0.97)
        .padding(.horizontal, 7)
    }
}

/// A game's icon on a tile with a lip in its colour: Sidefolk's picture for its look, else its symbol. Shared by the
/// header, the menu's cards and Playtime's page in Home (`GameArtTile`).
struct GameIconTile: View {
    var info: GameInfo
    var style: GameStyle
    var side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.28, style: .continuous).fill(style.bottom).brightness(-0.12).offset(y: 2.5)
            RoundedRectangle(cornerRadius: side * 0.28, style: .continuous).fill(GamePaint.card)
            RoundedRectangle(cornerRadius: side * 0.28, style: .continuous).fill(style.top.opacity(0.12))
            if let icon = style.icon, icon.image != nil {
                icon.view(fitting: side * 0.8)
            } else {
                Image(systemName: info.symbol ?? "gamecontroller.fill").font(.system(size: side * 0.42, weight: .bold)).foregroundStyle(style.bottom)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// "You vs <companion>": both faces and names, the score large (or round pips for a match), a streak, and the
/// companion's sealed pick, on one card over the scene. It mirrors in right-to-left languages like any row.
struct ScoreBar: View {
    var score: GameBoard.Score?
    var companionName: String
    var portrait: NSImage?
    var you: NSImage?
    var style: GameStyle

    var body: some View {
        HStack(spacing: 4) {
            side(name: String(localized: "You", comment: "The person, on a game's score"), points: score?.you, won: .win, mine: true) {
                PlayerAvatar(picture: you, size: 36)
            }
            VersusMark(color: style.levelChip)
            side(name: companionName, points: score?.companion, won: .loss, mine: false) {
                GameAvatar(portrait: portrait, size: 36).overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            }
        }
        .padding(4)
        .gameCard(corner: 19)
        .foregroundStyle(Theme.ink)
    }

    private func side<Face: View>(name: String, points: Int?, won: GameVerdict, mine: Bool, @ViewBuilder face: () -> Face) -> some View {
        HStack(spacing: 8) {
            face()
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: name).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
                if let points { tally(points, won: won) }
            }
            Spacer(minLength: 0)
            if mine, let streak = score?.streak, streak >= 2 {
                // A streak is the person's winning run: success, with its flame.
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill").foregroundStyle(GameColors.color(.win))
                    Text(verbatim: Toss.number(streak)).monospacedDigit()
                }
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Theme.successSoft))
                .accessibilityLabel(String(localized: "\(streak) in a row", comment: "A streak in a game"))
            }
            if !mine, score?.companionPicked == true {
                SealedCard(portrait: portrait)
                    .accessibilityLabel(String(localized: "\(companionName) has picked", comment: "The companion chose its answer and keeps it hidden"))
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(GamePaint.inset))
        .accessibilityElement(children: .combine)
    }

    /// Rounds won, as pips: the person's in the win colour, the companion's (the person's losses) in the calm loss tone.
    @ViewBuilder private func tally(_ n: Int, won: GameVerdict) -> some View {
        if let rounds = score?.rounds {
            HStack(spacing: 4) {
                ForEach(0..<rounds, id: \.self) { i in
                    Circle().fill(i < n ? GameColors.color(won) : Theme.line).frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: i < n ? 1.5 : 0))
                }
            }
            .padding(.vertical, 4)
            .accessibilityLabel(Text(verbatim: Toss.number(n)))
        } else {
            Text(verbatim: Toss.number(n)).font(.system(size: 22, weight: .black, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}

/// "VS" between the two sides, with a few still sparks either side: the bar's one flourish.
struct VersusMark: View {
    var color: Color

    var body: some View {
        HStack(spacing: 1) {
            Sparks().frame(width: 10, height: 24)
            Text(String(localized: "VS", comment: "Between the person and the companion on a game's score bar"))
                .font(.system(size: 16, weight: .black, design: .rounded)).italic()
                .foregroundStyle(color)
            Sparks().frame(width: 10, height: 24).scaleEffect(x: -1)
        }
        .accessibilityHidden(true)
    }
}

/// Three short strokes fanning out from the trailing side, apart from it and from each other: a cartoon's "ta-da",
/// drawn once and still.
struct Sparks: View {
    var color: Color = Theme.sun

    var body: some View {
        Canvas { context, size in
            let from = CGPoint(x: size.width, y: size.height / 2), reach = Double(min(size.width * 1.1, size.height / 1.6))
            for angle in [-0.85, 0.0, 0.85] {
                var stroke = Path()
                stroke.move(to: CGPoint(x: from.x - cos(angle) * reach * 0.5, y: from.y + sin(angle) * reach * 0.5))
                stroke.addLine(to: CGPoint(x: from.x - cos(angle) * reach, y: from.y + sin(angle) * reach))
                context.stroke(stroke, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The line of keys under the board, on a card with a lightbulb: what to press first in ink, the rest quieter.
struct HintRow: View {
    var text: String

    var body: some View {
        let parts = text.components(separatedBy: " · ")
        HStack(spacing: 8) {
            if GameArt.bulb.image != nil { GameArt.bulb.view(height: 20) } else { Image(systemName: "lightbulb.fill").foregroundStyle(Theme.sun) }
            (Text(verbatim: parts[0]).foregroundStyle(Theme.ink)
                + Text(verbatim: parts.count > 1 ? " · " + parts.dropFirst().joined(separator: " · ") : "").foregroundStyle(Theme.inkMuted))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(2).multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .gameCard(corner: 15, opacity: 0.94)
    }
}

/// The companion's face, round.
struct GameAvatar: View {
    var portrait: NSImage?
    var size: CGFloat

    var body: some View {
        Group {
            if let portrait { Image(nsImage: portrait).resizable().scaledToFill() } else { Circle().fill(PlayView.accent.opacity(0.4)) }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// A small card face down with the companion's face on it: it has picked and isn't telling.
struct SealedCard: View {
    var portrait: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(colors: [Theme.navy, Theme.navy.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1.5).padding(2)
            GameAvatar(portrait: portrait, size: 14)
        }
        .frame(width: 22, height: 30)
        .rotationEffect(.degrees(-8))
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        .transition(.scale.combined(with: .opacity))
    }
}
