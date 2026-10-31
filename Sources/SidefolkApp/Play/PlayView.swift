import SidefolkCharacter
import SidefolkCore
import SwiftUI

/// The Play panel (D75, dressed as a game in D79 amended): a header in the game's colour with its icon, title and
/// whose game it is, "You vs <companion>" with the score, the game's scene with the companion in it saying the
/// prompt, the board, and a hint line of keys. Everything is drawn by Sidefolk from the board's data and its own art.
struct PlayView: View {
    var model: PlayModel
    var onSpeaker: () -> Void = {}

    static let width: CGFloat = 400
    static let pad: CGFloat = 14
    /// The room inside the panel's padding, for parts that size themselves.
    static let inner: CGFloat = width - 2 * pad
    static let accent = Theme.folkColor("play")

    var style: GameStyle { .of(model.info.look) }

    var body: some View {
        VStack(spacing: 0) {
            PlayHeader(model: model, style: style, onSpeaker: onSpeaker)
            ZStack(alignment: .top) {
                GameSceneBackground(style: style)
                VStack(spacing: 10) {
                    ScoreBar(score: model.board?.score, companionName: model.companionName, portrait: model.portrait, you: model.you, style: style)
                    if let failure = model.failure {
                        failed(failure)
                    } else if let board = model.board {
                        BoardView(model: model, board: board, style: style)
                    } else {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity).frame(height: 160)
                    }
                    HintRow(text: model.footer)
                }
                .padding(Self.pad)
            }
        }
        .frame(width: Self.width)
        .background(Theme.surface)
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
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
    }
}

/// A round button on the header's colour: back, the speaker, ✕.
struct HeaderButton: View {
    var symbol: String
    var label: String
    var style: GameStyle
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).frame(width: 30, height: 30)
                .foregroundStyle(style.onColor)
                .background(Circle().fill(style.onColor.opacity(0.2)))
                .contentShape(Circle())
        }
        .buttonStyle(GamePressStyle())
        .focusable(false)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The game's band: back to the menu, its icon on a tile, its title and whose game it is, the speaker and ✕.
struct PlayHeader: View {
    var model: PlayModel
    var style: GameStyle
    var onSpeaker: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let back = model.onBack {
                HeaderButton(symbol: "chevron.backward", label: String(localized: "All games", comment: "Play panel: back to the menu of games"),
                             style: style, action: back)
            }
            GameIconTile(info: model.info, style: style, side: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: model.info.title).font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(style.onColor)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .shadow(color: .black.opacity(style.onColor == .white ? 0.18 : 0), radius: 1, y: 1)
                if !model.info.isSidefolk {
                    // Whose game it is, so it never passes for Sidefolk's own.
                    HStack(spacing: 4) {
                        ExtensionBadge(look: ExtensionLook(name: model.info.extensionName, iconPath: model.info.iconPath, folk: "play"), size: 12)
                        Text(verbatim: model.info.extensionName).font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1)
                    }
                    .foregroundStyle(style.onColor)
                    .padding(.leading, 3).padding(.trailing, 8).padding(.vertical, 2)
                    .background(Capsule().fill(style.onColor.opacity(0.2)))
                }
            }
            Spacer(minLength: 4)
            HeaderButton(symbol: model.soundsOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                         label: model.soundsOn ? String(localized: "Turn the game's sounds off") : String(localized: "Turn the game's sounds on"),
                         style: style, action: onSpeaker)
            HeaderButton(symbol: "xmark", label: String(localized: "Close", comment: "Closes the Play panel"), style: style) { model.onClose?() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(style.gradient.overlay(alignment: .top) {
            LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom).frame(height: 24)
        })
    }
}

/// A game's icon on a white tile with a lip in its colour: Sidefolk's picture for its look, else its symbol.
struct GameIconTile: View {
    var info: GameInfo
    var style: GameStyle
    var side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.28, style: .continuous).fill(style.bottom).brightness(-0.12).offset(y: 2.5)
            RoundedRectangle(cornerRadius: side * 0.28, style: .continuous).fill(.white)
            if let icon = style.icon, icon.image != nil {
                icon.view(fitting: side * 0.78)
            } else {
                Image(systemName: info.symbol ?? "gamecontroller.fill").font(.system(size: side * 0.42, weight: .bold)).foregroundStyle(style.bottom)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// "You vs <companion>": both faces and names, the score large (or round pips for a match), a streak, and the
/// companion's sealed pick. It mirrors in right-to-left languages like any row.
struct ScoreBar: View {
    var score: GameBoard.Score?
    var companionName: String
    var portrait: NSImage?
    var you: NSImage?
    var style: GameStyle

    var body: some View {
        HStack(spacing: 6) {
            side(name: String(localized: "You", comment: "The person, on a game's score"), points: score?.you, won: .win, mine: true) {
                PlayerAvatar(picture: you, size: 36)
            }
            Text(String(localized: "VS", comment: "Between the person and the companion on a game's score bar"))
                .font(.system(size: 15, weight: .black, design: .rounded)).italic()
                .foregroundStyle(style.night ? Color(hex: 0x7A4FE0) : style.bottom)
                .accessibilityHidden(true)
            side(name: companionName, points: score?.companion, won: .loss, mine: false) {
                GameAvatar(portrait: portrait, size: 36).overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface.opacity(0.95))
            .shadow(color: .black.opacity(0.1), radius: 6, y: 3))
        .foregroundStyle(Theme.ink)
    }

    private func side<Face: View>(name: String, points: Int?, won: GameVerdict, mine: Bool, @ViewBuilder face: () -> Face) -> some View {
        HStack(spacing: 8) {
            face()
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: name).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.inkMuted).lineLimit(1)
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
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.surfaceSunken.opacity(0.7)))
        .accessibilityElement(children: .combine)
    }

    /// Rounds won, as pips: the person's in the win colour, the companion's (the person's losses) in the calm loss tone.
    @ViewBuilder private func tally(_ n: Int, won: GameVerdict) -> some View {
        if let rounds = score?.rounds {
            HStack(spacing: 4) {
                ForEach(0..<rounds, id: \.self) { i in
                    Circle().fill(i < n ? GameColors.color(won) : Theme.line).frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: i < n ? 1.5 : 0))
                }
            }
            .padding(.vertical, 4)
            .accessibilityLabel(Text(verbatim: Toss.number(n)))
        } else {
            Text(verbatim: Toss.number(n)).font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}

/// The quiet line of keys under the board, on a pill with a lightbulb.
struct HintRow: View {
    var text: String

    var body: some View {
        HStack(spacing: 7) {
            if GameArt.bulb.image != nil { GameArt.bulb.view(height: 18) } else { Image(systemName: "lightbulb.fill").foregroundStyle(Theme.sun) }
            Text(verbatim: text).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.inkMuted)
                .lineLimit(2).multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Theme.surface.opacity(0.92)))
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
